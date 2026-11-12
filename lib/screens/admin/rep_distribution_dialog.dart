import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:sizer/sizer.dart';
import '../../utils/firestore_helpers.dart';
import '../../utils/target_distribution.dart';

/// Supervisor → sales-rep target distribution dialog (supervisor role only).
///
/// Mirrors [ManagerDistributionDialog]: loads the supervisor's received
/// monthly target plus every permanent rep's current share, lets the
/// supervisor set this rep's five indicators, and saves atomically via
/// [distributeRepTarget] (re-validated inside the transaction, so concurrent
/// saves cannot jointly exceed the supervisor's target). Freelance reps
/// never appear here — they are filtered out upstream, same as the lists.
class RepDistributionDialog extends StatefulWidget {
  final FirebaseFirestore db;
  final String supervisorId;
  final String repId;
  final String repName;
  final String setByUid;

  const RepDistributionDialog({
    super.key,
    required this.db,
    required this.supervisorId,
    required this.repId,
    required this.repName,
    required this.setByUid,
  });

  @override
  State<RepDistributionDialog> createState() => _RepDistributionDialogState();
}

class _RepDistributionDialogState extends State<RepDistributionDialog> {
  bool _loading = true;
  bool _hasHolderTarget = true;
  String? _error;
  String _month = '';
  Map<String, double> _received = {};
  Map<String, double> _othersSum = {};
  List<String> _allRepIds = [];
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
      final holderSnap = await widget.db
          .collection('managers')
          .doc(widget.supervisorId)
          .get();
      final holderData = holderSnap.data() ?? <String, dynamic>{};
      final holderTargets = (holderData['targets'] is Map)
          ? Map<String, dynamic>.from(holderData['targets'] as Map)
          : <String, dynamic>{};
      final holderEntry = holderTargets[_month];
      if (holderEntry is! Map) {
        if (mounted) {
          setState(() {
            _loading = false;
            _hasHolderTarget = false;
          });
        }
        return;
      }
      final received = normalizeTargets(holderEntry);
      final repsSnap = await widget.db
          .collection('salesRep')
          .where('supervisorId', isEqualTo: widget.supervisorId)
          .get();
      // Permanent reps only — freelance reps never enter the hierarchy.
      final eligible =
          repsSnap.docs.where((d) => isTargetEligible(d['repType'])).toList();
      final others = <Map<String, dynamic>>[];
      Map<String, dynamic>? current;
      for (final doc in eligible) {
        final data = doc.data();
        final targets = (data['targets'] is Map)
            ? Map<String, dynamic>.from(data['targets'] as Map)
            : <String, dynamic>{};
        final entry = targets[_month];
        if (doc.id == widget.repId) {
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
          _allRepIds = eligible.map((d) => d.id).toList();
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
      await distributeRepTarget(
        db: widget.db,
        supervisorId: widget.supervisorId,
        repId: widget.repId,
        allRepIds: _allRepIds,
        month: _month,
        values: raw,
        setByUid: widget.setByUid,
        now: DateTime.now(),
      );
    } on StateError catch (e) {
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
      title: Text('توزيع الهدف: ${widget.repName}',
          style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
      content: SingleChildScrollView(
        child: _loading
            ? const Center(
                child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator()))
            : !_hasHolderTarget
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
                        'يُحفظ في هدف المندوب الشهري، ويُحدَّث إجمالي التوزيع وسجل التدقيق لدى المشرف.',
                        style: TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                    ],
                  ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('إلغاء', style: TextStyle(fontSize: 13.sp))),
        if (!_loading && _hasHolderTarget)
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
