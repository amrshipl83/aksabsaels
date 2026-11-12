import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:sizer/sizer.dart';
import '../../utils/target_distribution.dart';
import '../../services/target_distribution_service.dart';

/// Manager → supervisor target distribution dialog (manager role only).
///
/// Loads the manager's received monthly target plus every linked
/// supervisor's current share, lets the manager set this supervisor's five
/// indicators, and saves atomically via [distributeSupervisorTarget]
/// (re-validated inside the transaction, so concurrent saves cannot jointly
/// exceed the manager's target). Partial distribution is allowed.
class ManagerDistributionDialog extends StatefulWidget {
  final FirebaseFirestore db;
  final String managerId;
  final String supervisorId;
  final String supervisorName;
  final String setByUid;

  const ManagerDistributionDialog({
    super.key,
    required this.db,
    required this.managerId,
    required this.supervisorId,
    required this.supervisorName,
    required this.setByUid,
  });

  @override
  State<ManagerDistributionDialog> createState() =>
      _ManagerDistributionDialogState();
}

class _ManagerDistributionDialogState
    extends State<ManagerDistributionDialog> {
  bool _loading = true;
  bool _hasManagerTarget = true;
  String? _error;
  String _month = '';
  Map<String, double> _received = {};
  Map<String, double> _othersSum = {};
  // NOTE: recipient ids are resolved server-side now; the backend
  // re-reads every linked doc inside its transaction.
  Map<String, TextEditingController> _ctrls = {};

  @override
  void initState() {
    super.initState();
    _month = targetMonthKey(DateTime.now());
    _load();
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _fmt(double v) => v == v.roundToDouble()
      ? v.toInt().toString()
      : v.toStringAsFixed(1);

  Future<void> _load() async {
    try {
      final managerSnap =
          await widget.db.collection('managers').doc(widget.managerId).get();
      final managerData = managerSnap.data() ?? <String, dynamic>{};
      final managerTargets = (managerData['targets'] is Map)
          ? Map<String, dynamic>.from(managerData['targets'] as Map)
          : <String, dynamic>{};
      final managerEntry = managerTargets[_month];
      if (managerEntry is! Map) {
        if (mounted) {
          setState(() {
            _loading = false;
            _hasManagerTarget = false;
          });
        }
        return;
      }
      final received = normalizeTargets(managerEntry);
      final supsSnap = await widget.db
          .collection('managers')
          .where('managerId', isEqualTo: widget.managerId)
          .get();
      final others = <Map<String, dynamic>>[];
      Map<String, dynamic>? current;
      for (final doc in supsSnap.docs) {
        final data = doc.data();
        final targets = (data['targets'] is Map)
            ? Map<String, dynamic>.from(data['targets'] as Map)
            : <String, dynamic>{};
        final entry = targets[_month];
        if (doc.id == widget.supervisorId) {
          if (entry is Map) current = Map<String, dynamic>.from(entry);
        } else if (entry is Map) {
          others.add(Map<String, dynamic>.from(entry));
        }
      }
      final currentValues = normalizeTargets(current);
      if (mounted) {
        setState(() {
          _received = received;
          _othersSum = sumAllocations(others);
          // _allSupervisorIds removed: backend resolves linked docs itself.
          _ctrls = {
            for (final f in kTargetFields)
              f: TextEditingController(
                  text: currentValues[f] == 0
                      ? ''
                      : _fmt(currentValues[f]!))
          };
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'تعذّر تحميل البيانات: $e';
        });
      }
    }
  }

  Future<void> _save() async {
    final raw = {for (final e in _ctrls.entries) e.key: e.value.text};
    final shapeError = validateTargetInputs(raw);
    if (shapeError != null) {
      setState(() => _error = shapeError);
      return;
    }
    final proposed = normalizeTargets(raw);
    final capError = validateDistribution(
      received: _received,
      othersSum: _othersSum,
      proposed: proposed,
    );
    if (capError != null) {
      setState(() => _error = capError);
      return;
    }
    setState(() => _error = null);
    try {
      // Backend save (Admin SDK): client rules allow self-only writes,
      // so the cross-doc transaction moved server-side.
      await distributeTargetViaBackend(
        holderId: widget.managerId,
        recipientId: widget.supervisorId,
        kind: 'manager_supervisor',
        month: _month,
        values: raw,
      );
    } on TargetDistributeException catch (e) {
      if (mounted) setState(() => _error = e.message);
      return;
    } catch (e) {
      if (mounted) setState(() => _error = 'تعذّر الحفظ: $e');
      return;
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      title: Text('توزيع الهدف: ${widget.supervisorName}',
          style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
      content: SingleChildScrollView(
        child: _loading
            ? const Center(
                child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator()))
            : !_hasManagerTarget
                ? const Text('لا يوجد هدف مسند لهذا الشهر بعد.')
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final f in kTargetFields) ...[
                        TextField(
                          controller: _ctrls[f],
                          decoration: InputDecoration(
                            labelText: kTargetLabelsAr[f],
                            helperText:
                                'المتاح: ${_fmt(_received[f]! - _othersSum[f]!)}',
                            border: const OutlineInputBorder(),
                          ),
                          keyboardType:
                              const TextInputType.numberWithOptions(
                                  decimal: true),
                        ),
                        SizedBox(height: 10.sp),
                      ],
                      if (_error != null)
                        Text(_error!,
                            style: const TextStyle(
                                color: Colors.red, fontSize: 12)),
                      const Text(
                        'يُحفظ في هدف المشرف الشهري، ويُحدَّث إجمالي التوزيع وسجل التدقيق لدى المدير.',
                        style: TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                    ],
                  ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('إلغاء', style: TextStyle(fontSize: 13.sp))),
        if (!_loading && _hasManagerTarget)
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                padding: EdgeInsets.symmetric(horizontal: 20.sp)),
            onPressed: _save,
            child: Text('حفظ التوزيع',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 13.sp,
                    fontWeight: FontWeight.bold)),
          ),
      ],
    );
  }
}
