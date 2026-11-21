import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sizer/sizer.dart';
import '../../utils/client_counts.dart';
import '../../utils/order_counts.dart';
import '../../utils/firestore_helpers.dart';
import '../../utils/target_distribution.dart';
import '../../utils/workday_history.dart';

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
  bool _isLoading = true;

  double workingHours = 0;
  int workdaysClosed = 0;

  double visitHoursHist = 0;

  int openVisitsHist = 0;
  int visitsWithoutDurationHist = 0;
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
    // Follow-up is month-based for both roles: bound the range to the whole
    // selected month (see monthStart/monthEnd in _fetchData).
    _fetchData();
  }

  Future<void> _fetchData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      // Hours/days are read here from the backend aggregates on the rep doc
      // (workingHoursByMonth.<month>.totalSeconds/.sessions) — no UI math.
      // Orders/sales stream from the unified orders aggregate below;
      // Visit durations come from the `visits` records only.
      // qualified clients stream from the unified clients counter below.

      // Visit durations come from the `visits` records only.
      List<String> codesToQuery = [];
      Map<String, Map<String, dynamic>> aggByCode = {};

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
        aggByCode =
            dedupeRepDocsByCode(reps.docs.map((d) => d.data()));

        var supervisorDoc = await _db.collection('managers').doc(widget.targetDocId).get();
        final supData = supervisorDoc.data();
        targets = supData?['targets'] ?? {};
        _repCount = codesToQuery.where((e) => e.trim().isNotEmpty).length;
      } else {
        codesToQuery = [widget.repCode ?? ''];
        var repDoc = await _db.collection('salesRep').doc(widget.targetDocId).get();
        final repData = repDoc.data();
        {
          final code = (repData?['repCode']?.toString() ?? '').trim();
          if (repData != null) {
            aggByCode[code.isEmpty ? '__single__' : code] =
                Map<String, dynamic>.from(repData);
          }
        }
        targets = repData?['targets'] ?? {};
        _repOutsideScope = !isTargetEligible(repData?['repType']);
      }

      // الطلبات/المبيعات تُبثّ من المجمّع الموحد
      // (`salesRep.ordersByMonth.{month}`) في بطاقتين مستقلتين أدناه —
      // بلا استعلام `orders` هنا وبلا إعادة حساب. العملاء المؤهلون
      // من عدّادهم الموحد، والزيارات ومددها من سجلات `visits`، والساعات
      // والأيام من حقول الدالة الخلفية workingHoursByMonth في مستند المندوب.
      final safeCodes = codesToQuery.where((e) => e.trim().isNotEmpty).toList();

      final monthStart = DateTime(_selYear, _selMonth, 1);
      final monthEnd = DateTime(_selYear, _selMonth + 1, 1);
      double hours = 0;
      int wd = 0;

      double vh = 0;

      int ov = 0;
      int vnodur = 0;
      // الساعات والأيام: قراءة مباشرة من إجماليات الدالة الخلفية
      // (workingHoursByMonth.<month>.totalSeconds/.sessions) — بلا تجميع.
      hours = sumTeamWorkSecondsForMonth(
              repDataByCode: aggByCode, monthKey: _monthKey) /
          3600.0;
      wd = sumTeamWorkSessionsForMonth(
          repDataByCode: aggByCode, monthKey: _monthKey);
      if (safeCodes.isNotEmpty) {
        final vhist = await fetchTeamVisitSummary(
          db: _db,
          repCodes: safeCodes,
          startInclusive: monthStart,
          endExclusive: monthEnd,
        );



        vh = vhist.visitHours;

        ov = vhist.openVisits;
        vnodur = vhist.visitsWithoutDuration;
      }

      if (mounted) {
        setState(() {
          workingHours = hours;
          workdaysClosed = wd;

          visitHoursHist = vh;

          openVisitsHist = ov;
          visitsWithoutDurationHist = vnodur;
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
              ? 'إجمالي الدالة الخلفية — ساعات الفريق فقط (totalSeconds) — بلا ساعات المشرف الشخصية.'
              : 'إجمالي ساعاتك المخزن خلفيًا (totalSeconds) — مرتبط بالراتب الأساسي.',
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
        _supKpiCard(
          title: isSupervisor ? 'أيام العمل المغلقة (الفريق)' : 'أيام عملك المغلقة',
          actual: workdaysClosed.toDouble(),
          goal: 0,
          unit: 'يوم',
          note: 'إجمالي الجلسات المحتسبة خلفيًا (sessions) — بلا تجميع في الواجهة.',
        ),
        _supKpiCard(
          title: isSupervisor ? 'إجمالي مدة الزيارات (الفريق)' : 'إجمالي مدة زياراتك',
          actual: visitHoursHist,
          goal: 0,
          unit: 'ساعة',
          note: 'من السجلات التاريخية (الحالات النهائية ذات المدة الصالحة) — $openVisitsHist مفتوحة و$visitsWithoutDurationHist بلا مدة مستبعدة من المدد.',
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

  /// بطاقة الزيارات من السجلات التاريخية (نطاق الشهر على `visits`).
  /// مشرف: مجموع سجلات الفريق عبر `supervisorId` (مرة واحدة لكل
  /// مندوب، مقسّم على دفعات بلا اقتطاع). مندوب: سجلات `repCode` وحده.
  /// المفتوحة (in_progress) مستبعدة؛ بلا مدة مخترعة للسجلات القديمة.
  Widget _buildVisitsCounterCard({
    required bool isSupervisor,
    required double goal,
  }) {
    final stream = isSupervisor
        ? watchSupervisorVisitMonthTotalHist(
            db: _db,
            supervisorDocId: widget.targetDocId,
            monthKey: _monthKey,
          )
        : watchRepVisitMonthTotalHist(
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
              ? 'إجمالي الفريق من السجلات التاريخية (الحالات النهائية فقط — المفتوح مستبعد).'
              : 'زياراتك من السجلات التاريخية (الحالات النهائية فقط — المفتوح مستبعد).',
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
                'الساعات وأيام العمل من حقول الدالة الخلفية (workingHoursByMonth: totalSeconds/sessions)؛ الزيارات ومددها من سجلات `visits` (المغلق فقط)؛ العملاء من المجمّع الموحد الحي؛ '
                'الساعات للفريق فقط.'
            : 'طريقة العد: الفواتير = عدد مستندات طلباتك (new/delivered/cancelled فقط)؛ '
                'المبيعات = قيمة المسلّم فقط؛ '
                'الساعات وأيام العمل من حقول الدالة الخلفية (workingHoursByMonth)؛ الزيارات ومددها من سجلات `visits` (المغلق فقط)؛ العملاء من المجمّع الموحد الحي.',
        style: const TextStyle(fontSize: 11),
      ),
    );
  }
}
