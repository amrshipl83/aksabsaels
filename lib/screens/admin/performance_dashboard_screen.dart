import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sizer/sizer.dart';
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
  DateTime _startDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _endDate = DateTime.now();
  bool _isLoading = true;

  double totalSales = 0;
  int totalOrders = 0;
  int activeCustomers = 0;
  double workingHours = 0;
  int executedVisits = 0;
  Map<String, dynamic> targets = {};
  bool _repOutsideScope = false;
  // Monthly follow-up state (supervisor branch only).
  int _selYear = DateTime.now().year;
  int _selMonth = DateTime.now().month;
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
    _endDate = DateTime(_selYear, _selMonth + 1, 0);
    _fetchData();
  }

  Future<void> _fetchData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      List<String> codesToQuery = [];
      // Visit codes: team repCodes plus the supervisor's own repCode when
      // their doc carries one (same key visits use). Orders, customers and
      // hours always use codesToQuery (team-only).
      List<String> visitCodes = [];

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
        visitCodes = [...codesToQuery];
        // The supervisor's own visits join the team visits ONLY, when their
        // doc carries a repCode (the same key visits use). Orders, customers
        // and hours stay team-only; supervisor personal hours are excluded
        // and will live in the future attendance page.
        final supCode = supData?['repCode']?.toString().trim() ?? '';
        if (supCode.isNotEmpty && !visitCodes.contains(supCode)) {
          visitCodes.add(supCode);
        }
      } else {
        codesToQuery = [widget.repCode ?? ''];
        visitCodes = [...codesToQuery];
        var repDoc = await _db.collection('salesRep').doc(widget.targetDocId).get();
        final repData = repDoc.data();
        targets = repData?['targets'] ?? {};
        _repOutsideScope = !isTargetEligible(repData?['repType']);
      }

      final safeCodes = codesToQuery.where((e) => e.trim().isNotEmpty).toList();
      if (safeCodes.length > 10) {
        debugPrint("Performance: too many repCodes (${safeCodes.length}), showing first 10 only");
      }
      final queryCodes = safeCodes.take(10).toList();
      final visitSafeCodes =
          visitCodes.where((e) => e.trim().isNotEmpty).toList();
      if (visitSafeCodes.length > 10) {
        debugPrint("Performance: too many visit repCodes (${visitSafeCodes.length}), showing first 10 only");
      }
      final visitQueryCodes = visitSafeCodes.take(10).toList();

      double salesSum = 0;
      Set<String> buyersSet = {};
      int orderCount = 0;
      double hours = 0;
      int visitCount = 0;

      if (queryCodes.isNotEmpty) {
        // 2. جلب الأوردرات — كل الحالات بما فيها الملغاة (نفس سلوك العرض
        // الحالي؛ إخراج الملغاة يغيّر أرقام الإنجاز لذا يُوثَّق ولا يُغيَّر).
        var orders = await _db
            .collection('orders')
            .where('buyer.repCode', whereIn: queryCodes)
            .where('orderDate', isGreaterThanOrEqualTo: Timestamp.fromDate(_startDate))
            .where('orderDate', isLessThanOrEqualTo: Timestamp.fromDate(_endDate.add(const Duration(days: 1))))
            .get();

        for (var doc in orders.docs) {
          final total = (doc.data()['total'] ?? 0);
          salesSum += ((total is num) ? total.toDouble() : 0);
          if (doc['buyer']?['id'] != null) buyersSet.add(doc['buyer']['id'].toString());
        }
        orderCount = orders.docs.length;

        // 4. جلب ساعات العمل — الفريق فقط (أكواد المناديب). ساعات المشرف
        // الشخصية مستبعدة عمداً وستكون في صفحة الحضور لاحقاً.
        var logs = await _db
            .collection('daily_logs')
            .where('repCode', whereIn: queryCodes)
            .where('startTime', isGreaterThanOrEqualTo: Timestamp.fromDate(_startDate))
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

      // 3. جلب الزيارات (الحقل الفعلي startTime وليس timestamp) — الفريق
      // زائد المشرف نفسه (برمز زيارته إن وُجد في مستنده).
      if (visitQueryCodes.isNotEmpty) {
        var visits = await _db
            .collection('visits')
            .where('repCode', whereIn: visitQueryCodes)
            .where('startTime', isGreaterThanOrEqualTo: Timestamp.fromDate(_startDate))
            .where('startTime', isLessThanOrEqualTo: Timestamp.fromDate(_endDate.add(const Duration(days: 1))))
            .get();
        visitCount = visits.docs.length;
      }

      if (mounted) {
        setState(() {
          totalSales = salesSum;
          totalOrders = orderCount;
          activeCustomers = buyersSet.length;
          executedVisits = visitCount;
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
      body: _isLoading
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
    );
  }

  void _onMonthChanged(int? year, int? month) {
    if (year == null || month == null) return;
    if (year == _selYear && month == _selMonth) return;
    setState(() {
      _selYear = year;
      _selMonth = month;
      _startDate = DateTime(year, month, 1);
      _endDate = DateTime(year, month + 1, 0);
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
        monthProgress(now: DateTime.now(), year: _selYear, month: _selMonth);
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
        _supKpiCard(
          title: 'الفواتير / الأوردرات',
          actual: totalOrders.toDouble(),
          goal: values['invoicesTarget']!,
          unit: 'فاتورة',
        ),
        _supKpiCard(
          title: 'العملاء',
          actual: activeCustomers.toDouble(),
          goal: values['clientsTarget']!,
          unit: 'عميل',
        ),
        _supKpiCard(
          title: 'الزيارات',
          actual: executedVisits.toDouble(),
          goal: values['visitsTarget']!,
          unit: 'زيارة',
          note: isSupervisor
              ? 'زياراتك وزيارات فريقك (تُحسب زيارتك برمز زيارتك إن وُجد).'
              : 'زياراتك المسجلة خلال الشهر.',
        ),
        _supKpiCard(
          title: 'الهدف المالي',
          actual: totalSales,
          goal: values['financialTarget']!,
          unit: 'ج.م',
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
            ? 'طريقة العد: الفواتير تشمل جميع الحالات بما فيها الملغاة (دون تغيير في التعريف)؛ '
                'العملاء مميزون بمعرف العميل الثابت؛ الزيارات تشمل المشرف (برمز زيارته إن وُجد) وفريقه؛ '
                'الساعات للفريق فقط.'
            : 'طريقة العد: الفواتير تشمل جميع الحالات بما فيها الملغاة (دون تغيير في التعريف)؛ '
                'العملاء مميزون بمعرف العميل الثابت.',
        style: const TextStyle(fontSize: 11),
      ),
    );
  }

}
