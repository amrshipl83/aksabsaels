import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sizer/sizer.dart';
import '../../utils/client_counts.dart';
import '../../utils/order_counts.dart';
import '../../utils/visit_counts.dart';
import '../../utils/firestore_helpers.dart';
import '../../utils/target_distribution.dart';

class PerformanceDashboardScreen extends StatefulWidget {
  final String targetDocId;
  final String targetType;
  final String targetName;
  final String? repCode;
  final FirebaseFirestore? firestore;

  const PerformanceDashboardScreen({
    super.key,
    required this.targetDocId,
    required this.targetType,
    required this.targetName,
    this.repCode,
    this.firestore,
  });

  @override
  State<PerformanceDashboardScreen> createState() => _PerformanceDashboardScreenState();
}

class _PerformanceDashboardScreenState extends State<PerformanceDashboardScreen> {
  DateTime _startDate = DateTime(cairoNow().year, cairoNow().month, 1);
  bool _isLoading = true;

  double workingHours = 0;
  Map<String, dynamic> targets = {};
  bool _repOutsideScope = false;
  // Monthly follow-up state (supervisor branch only).
  int _selYear = cairoNow().year;
  int _selMonth = cairoNow().month;
  int _repCount = 0;

  static const List<String> _arabicMonths = <String>[
    'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
    'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
  ];
  static const List<int> _years = <int>[2025, 2026, 2027, 2028, 2029, 2030];

  String get _monthKey =>
      '${_selYear.toString().padLeft(4, '0')}-${_selMonth.toString().padLeft(2, '0')}';

  // Supervisor-branch palette (same values as the rep KPI card locals).
  static const Color _kPrimary = Color(0xFF1ABC9C);
  static const Color _kSidebar = Color(0xFF2F3542);

  FirebaseFirestore get _db => widget.firestore ?? FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    // Supervisor follow-up is month-based: bound the range to the whole
    // selected month. The rep branch keeps its day-range filter.
    // Follow-up is month-based for both roles now: bound the range to the
    // whole selected month.
    _startDate = DateTime(_selYear, _selMonth, 1);
    _fetchData();
  }

  Future<void> _fetchData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      // Visit totals are NOT read here: the visits card below streams the
      // unified `salesRep.visitsByMonth.{Cairo month}.total` counter live
      // (team sum for supervisors, single rep for rep view).
      List<String> codesToQuery = [];

      // 1. تحديد الـ repCodes المستهدفة
      if (widget.targetType == 'sales_supervisor') {
        var reps = await _db
            .collection('salesRep')
            .where('supervisorId', isEqualTo: widget.targetDocId)
            .get();
        // Supervisor tracking is permanent-only: freelance reps never enter
        // the aggregated codes (client-side: legacy docs lack the field).
        codesToQuery = reps.docs
            // Null-safe map access: legacy docs lack repType/repCode and
            // operator [] would throw (caught below as zeros). Missing type
            // counts as permanent, matching the lists.
            .where((d) => isTargetEligible(d.data()['repType']))
            .map((d) => d.data()['repCode']?.toString() ?? '')
            .toList();

        var supervisorDoc = await _db.collection('managers').doc(widget.targetDocId).get();
        final supData = supervisorDoc.data();
        targets = supData?['targets'] ?? {};
        _repCount = codesToQuery.where((e) => e.trim().isNotEmpty).length;
      } else {
        codesToQuery = [widget.repCode ?? ''];
        var repDoc = await _db.collection('salesRep').doc(widget.targetDocId).get();
        final repData = repDoc.data();
        targets = repData?['targets'] ?? {};
        _repOutsideScope = !isTargetEligible(repData?['repType']);
      }

      // الطلبات/المبيعات تُبثّ من المجمّع الموحد
      // (`salesRep.ordersByMonth.{month}`) في بطاقتين مستقلتين أدناه —
      // بلا استعلام `orders` هنا وبلا إعادة حساب. العملاء المؤهلون
      // والزيارات كذلك من عدّاديهما الموحدين.
      final safeCodes = codesToQuery.where((e) => e.trim().isNotEmpty).toList();

      double hours = 0;

      if (safeCodes.isNotEmpty) {
        // جلب ساعات العمل — الفريق فقط (أكواد المناديب). ساعات المشرف
        // الشخصية مستبعدة عمداً وستكون في صفحة الحضور لاحقاً.
        // مقسّم على دفعات (10 لكل استعلام) بلا اقتطاع.
        for (final chunk in chunkList(safeCodes, 10)) {
          var logs = await _db
              .collection('daily_logs')
              .where('repCode', whereIn: chunk)
              .where('startTime',
                  isGreaterThanOrEqualTo: Timestamp.fromDate(_startDate))
              .get();

          for (var log in logs.docs) {
            var data = log.data();
            try {
              if (data['startTime'] != null && data['endTime'] != null) {
                DateTime start = (data['startTime'] as Timestamp).toDate();
                DateTime end = (data['endTime'] as Timestamp).toDate();
                if (!end.isBefore(start)) {
                  hours += end.difference(start).inMinutes / 60;
                }
              }
            } catch (_) {}
          }
        }
      }

      if (mounted) {
        setState(() {
          workingHours = hours;
        });
      }
    } catch (e) {
      debugPrint("Error fetching performance: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("تعذر تحميل بيانات الأداء")),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: Text(
            widget.targetType == 'sales_supervisor'
                ? "متابعة أداء المشرفين"
                : "أداء ${widget.targetName}",
            style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
        elevation: 0.5,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF2F3542),
        centerTitle: true,
      ),
      // SafeArea أعلى وأسفل: لا bottomNavigationBar هنا، والتمرير
      // يبقى طبيعيًا داخل SingleChildScrollView.
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF1ABC9C)))
            : RefreshIndicator(
                onRefresh: _fetchData,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.all(15.sp),
                  child: _buildFollowUpBody(
                      isSupervisor:
                          widget.targetType == 'sales_supervisor'),
                ),
              ),
      ),
    );
  }

  void _onMonthChanged(int? year, int? month) {
    if (year == null || month == null) return;
    if (year == _selYear && month == _selMonth) return;
    setState(() {
      _selYear = year;
      _selMonth = month;
      _startDate = DateTime(year, month, 1);
    });
    _fetchData();
  }

  String _fmtNum(double v) => v == v.roundToDouble()
      ? v.toInt().toString()
      : v.toStringAsFixed(1);

  String _fmtPct(double v) => v == v.roundToDouble()
      ? '${v.toInt()}%'
      : '${v.toStringAsFixed(1)}%';

  /// Monthly follow-up body (supervisor or rep): month header, info card
  /// and the five indicators, each with goal / actual / real percent /
  /// remaining. Out-of-hierarchy viewers (freelance) get an explicit badge.
  Widget _buildFollowUpBody({required bool isSupervisor}) {
    final entry = targets[_monthKey];
    final values = normalizeTargets(entry is Map ? entry : null);
    final prog =
        monthProgress(now: cairoNow(), year: _selYear, month: _selMonth);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildMonthHeader(prog),
        SizedBox(height: 2.h),
        if (!isSupervisor && _repOutsideScope)
          Container(
            width: double.infinity,
            margin: EdgeInsets.only(bottom: 2.h),
            padding: EdgeInsets.all(15.sp),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(15),
            ),
            child: const Text(
              "هذا المندوب حر (Freelance) — خارج نطاق توزيع ومتابعة الأهداف.",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        _buildFollowUpInfoCard(isSupervisor: isSupervisor),
        SizedBox(height: 2.h),
        Text(isSupervisor ? 'مؤشرات الفريق الخمسة' : 'المؤشرات الخمسة',
            style: TextStyle(
                fontSize: 15.sp,
                fontWeight: FontWeight.bold,
                color: Colors.blueGrey)),
        SizedBox(height: 1.h),
        _supKpiCard(
          title: isSupervisor ? 'ساعات عمل الفريق' : 'ساعات العمل',
          actual: workingHours,
          goal: values['hoursTarget']!,
          unit: 'ساعة',
          teamHours: isSupervisor,
          note: isSupervisor
              ? 'ساعات الفريق فقط — لا تشمل ساعات المشرف الشخصية.'
              : 'ساعات عملك الشخصية — مرتبطة بالراتب الأساسي.',
        ),
        _buildOrdersCounterCard(
          isSupervisor: isSupervisor,
          goal: values['invoicesTarget']!,
        ),
        _buildClientsCounterCard(
          isSupervisor: isSupervisor,
          goal: values['clientsTarget']!,
        ),
        _buildVisitsCounterCard(
          isSupervisor: isSupervisor,
          goal: values['visitsTarget']!,
        ),
        _buildSalesCounterCard(
          isSupervisor: isSupervisor,
          goal: values['financialTarget']!,
        ),
        _buildCountingNote(isSupervisor: isSupervisor),
      ],
    );
  }

  Widget _buildMonthHeader(Map<String, dynamic> prog) {
    final double percent = (prog['percent'] as double);
    final int remainingDays = prog['remainingDays'] as int;
    final int daysInMonth = prog['daysInMonth'] as int;
    return Container(
      padding: EdgeInsets.all(15.sp),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  key: ValueKey('month_$_selMonth'),
                  initialValue: _selMonth,
                  decoration: const InputDecoration(
                      labelText: 'الشهر', border: OutlineInputBorder()),
                  items: [
                    for (int m = 1; m <= 12; m++)
                      DropdownMenuItem(
                          value: m, child: Text(_arabicMonths[m - 1])),
                  ],
                  onChanged: (m) => _onMonthChanged(_selYear, m),
                ),
              ),
              SizedBox(width: 10.sp),
              Expanded(
                child: DropdownButtonFormField<int>(
                  key: ValueKey('year_$_selYear'),
                  initialValue: _selYear,
                  decoration: const InputDecoration(
                      labelText: 'السنة', border: OutlineInputBorder()),
                  items: [
                    for (final y in _years)
                      DropdownMenuItem(value: y, child: Text(y.toString())),
                  ],
                  onChanged: (y) => _onMonthChanged(y, _selMonth),
                ),
              ),
            ],
          ),
          SizedBox(height: 8.sp),
          Text(
              'الفترة: من $_monthKey-01 إلى $_monthKey-${daysInMonth.toString().padLeft(2, '0')}',
              style: TextStyle(fontSize: 12.sp, color: Colors.grey[700])),
          SizedBox(height: 6.sp),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: (percent / 100).clamp(0.0, 1.0),
              minHeight: 10,
              backgroundColor: Colors.grey[200],
              valueColor:
                  const AlwaysStoppedAnimation<Color>(Color(0xFF1ABC9C)),
            ),
          ),
          SizedBox(height: 4.sp),
          Text('مرور الشهر: ${_fmtPct(percent)} — المتبقي $remainingDays يوم',
              style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildFollowUpInfoCard({required bool isSupervisor}) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(14.sp),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: _kSidebar,
            radius: 24.sp,
            child: Icon(
                isSupervisor ? Icons.supervisor_account : Icons.person,
                color: Colors.white,
                size: 24.sp),
          ),
          SizedBox(width: 12.sp),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.targetName,
                    style: TextStyle(
                        fontSize: 15.sp, fontWeight: FontWeight.bold)),
                SizedBox(height: 4.sp),
                Text(
                    isSupervisor
                        ? 'عدد المندوبين التابعين: $_repCount'
                        : 'كود المندوب: ${widget.repCode ?? '—'}',
                    style:
                        TextStyle(fontSize: 12.sp, color: Colors.grey[700])),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// بطاقة العملاء المؤهلين من العدّاد الموحد (بث حي، Cairo month key).
  /// مشرف: مجموع عدّادات الفريق عبر `supervisorId` (مرة واحدة لكل
  /// مندوب، مقسّم على دفعات بلا اقتطاع). مندوب: عدّاد `repCode` وحده.
  /// غياب العداد = صفر، بلا إعادة حساب من `users`.
  Widget _buildClientsCounterCard({
    required bool isSupervisor,
    required double goal,
  }) {
    final stream = isSupervisor
        ? watchSupervisorMonthTotal(
            db: _db,
            supervisorDocId: widget.targetDocId,
            monthKey: _monthKey,
          )
        : watchRepMonthTotal(
            db: _db,
            repCode: widget.repCode ?? '',
            monthKey: _monthKey,
          );
    return StreamBuilder<int>(
      stream: stream,
      builder: (context, snapshot) {
        final actual = (snapshot.data ?? 0).toDouble();
        return _supKpiCard(
          title: 'العملاء المؤهلون',
          actual: actual,
          goal: goal,
          unit: 'عميل',
          note: 'العدّاد الموحد الحي (بتوقيت القاهرة) — بلا إعادة حساب.',
        );
      },
    );
  }

  /// بطاقة الزيارات من العدّاد الموحد (بث حي، Cairo month key).
  /// مشرف: مجموع عدّادات الفريق عبر `supervisorId` (مرة واحدة لكل
  /// مندوب، مقسّم على دفعات بلا اقتطاع). مندوب: عدّاد `repCode` وحده.
  /// غياب العداد = صفر، بلا عدّ من مجموعة `visits`.
  Widget _buildVisitsCounterCard({
    required bool isSupervisor,
    required double goal,
  }) {
    final stream = isSupervisor
        ? watchSupervisorVisitMonthTotal(
            db: _db,
            supervisorDocId: widget.targetDocId,
            monthKey: _monthKey,
          )
        : watchRepVisitMonthTotal(
            db: _db,
            repCode: widget.repCode ?? '',
            monthKey: _monthKey,
          );
    return StreamBuilder<int>(
      stream: stream,
      builder: (context, snapshot) {
        final actual = (snapshot.data ?? 0).toDouble();
        return _supKpiCard(
          title: 'الزيارات',
          actual: actual,
          goal: goal,
          unit: 'زيارة',
          note: isSupervisor
              ? 'إجمالي الفريق من العدّاد الموحد الحي (بتوقيت القاهرة) — بلا إعادة حساب.'
              : 'زياراتك من العدّاد الموحد الحي (بتوقيت القاهرة) — بلا إعادة حساب.',
        );
      },
    );
  }

  /// بطاقة الفواتير من المجمّع الموحد (عدد المستندات، بث حي).
  /// مشرف: مجموع عدّادات الفريق (مرة واحدة لكل مندوب). مندوب: عدّاده وحده.
  /// غياب العداد = صفر، بلا عدّ من مجموعة `orders`.
  Widget _buildOrdersCounterCard({
    required bool isSupervisor,
    required double goal,
  }) {
    final stream = isSupervisor
        ? watchSupervisorOrderMonthSummary(
            db: _db,
            supervisorDocId: widget.targetDocId,
            monthKey: _monthKey,
          )
        : watchRepOrderMonthSummary(
            db: _db,
            repCode: widget.repCode ?? '',
            monthKey: _monthKey,
          );
    return StreamBuilder<OrderMonthSummary>(
      stream: stream,
      builder: (context, snapshot) {
        final actual = (snapshot.data?.total ?? 0).toDouble();
        return _supKpiCard(
          title: 'الفواتير / الأوردرات',
          actual: actual,
          goal: goal,
          unit: 'فاتورة',
          note: isSupervisor
              ? 'إجمالي الفريق من المجمّع الموحد (عدد المستندات) — بلا إعادة حساب.'
              : 'طلباتك من المجمّع الموحد (عدد المستندات) — بلا إعادة حساب.',
        );
      },
    );
  }

  /// بطاقة المبيعات من المجمّع الموحد (قيمة المسلّم فقط، بث حي).
  Widget _buildSalesCounterCard({
    required bool isSupervisor,
    required double goal,
  }) {
    final stream = isSupervisor
        ? watchSupervisorOrderMonthSummary(
            db: _db,
            supervisorDocId: widget.targetDocId,
            monthKey: _monthKey,
          )
        : watchRepOrderMonthSummary(
            db: _db,
            repCode: widget.repCode ?? '',
            monthKey: _monthKey,
          );
    return StreamBuilder<OrderMonthSummary>(
      stream: stream,
      builder: (context, snapshot) {
        final actual = snapshot.data?.deliveredValue ?? 0;
        return _supKpiCard(
          title: 'الهدف المالي',
          actual: actual,
          goal: goal,
          unit: 'ج.م',
          note: isSupervisor
              ? 'قيمة الطلبات المسلّمة فقط — بلا shipped/processing.'
              : 'قيمة طلباتك المسلّمة فقط — بلا shipped/processing.',
        );
      },
    );
  }

  Widget _supKpiCard({
    required String title,
    required double actual,
    required double goal,
    required String unit,
    bool teamHours = false,
    String? note,
  }) {
    final bool hasGoal = goal > 0;
    final double pct = hasGoal ? actual / goal * 100 : 0;
    final double remaining = hasGoal ? goal - actual : 0;
    final String remainingText = !hasGoal
        ? ''
        : remaining > 0
            ? 'المتبقي: ${_fmtNum(remaining)} $unit'
            : remaining == 0
                ? 'المتبقي: 0 $unit'
                : 'المتبقي: 0 $unit (تجاوز بـ ${_fmtNum(-remaining)} $unit)';
    return Container(
      margin: EdgeInsets.only(bottom: 12.sp),
      padding: EdgeInsets.all(14.sp),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: teamHours
            ? const Border(top: BorderSide(color: _kPrimary, width: 4))
            : null,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title,
                    style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.bold,
                        color: _kSidebar)),
              ),
              if (teamHours)
                Container(
                  padding: EdgeInsets.symmetric(
                      horizontal: 8.sp, vertical: 2.sp),
                  decoration: BoxDecoration(
                      color: _kPrimary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20)),
                  child: Text('مؤشر الحافز',
                      style: TextStyle(
                          fontSize: 10.sp,
                          color: _kPrimary,
                          fontWeight: FontWeight.bold)),
                ),
            ],
          ),
          if (note != null) ...[
            SizedBox(height: 4.sp),
            Text(note,
                style: TextStyle(fontSize: 10.sp, color: Colors.grey[600])),
          ],
          SizedBox(height: 6.sp),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                  'الهدف: ${hasGoal ? _fmtNum(goal) : 'لم يُحدد هدف'} $unit',
                  style: TextStyle(fontSize: 12.sp)),
              Text('الفعلي حتى اليوم: ${_fmtNum(actual)} $unit',
                  style: TextStyle(
                      fontSize: 12.sp, fontWeight: FontWeight.bold)),
            ],
          ),
          if (hasGoal) ...[
            SizedBox(height: 6.sp),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: (pct / 100).clamp(0.0, 1.0),
                minHeight: 10,
                backgroundColor: Colors.grey[200],
                valueColor: AlwaysStoppedAnimation<Color>(
                    pct >= 100 ? Colors.green : _kPrimary),
              ),
            ),
            SizedBox(height: 6.sp),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('الإنجاز: ${_fmtPct(pct)}',
                    style: TextStyle(
                        fontSize: 12.sp, fontWeight: FontWeight.bold)),
                Text(remainingText, style: TextStyle(fontSize: 12.sp)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCountingNote({required bool isSupervisor}) {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(top: 4.sp),
      padding: EdgeInsets.all(12.sp),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        isSupervisor
            ? 'طريقة العد: الفواتير = عدد مستندات الطلبات (new/delivered/cancelled فقط)؛ '
                'المبيعات = قيمة المسلّم فقط (بلا shipped/processing)؛ '
                'العملاء والزيارات من المجمّعين الموحدين الحيّين (مجموع الفريق، مرة واحدة لكل مندوب)؛ '
                'الساعات للفريق فقط.'
            : 'طريقة العد: الفواتير = عدد مستندات طلباتك (new/delivered/cancelled فقط)؛ '
                'المبيعات = قيمة المسلّم فقط؛ '
                'العملاء والزيارات من المجمّعين الموحدين الحيّين لرمز المندوب.',
        style: const TextStyle(fontSize: 11),
      ),
    );
  }

}
