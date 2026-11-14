import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import '../../utils/firestore_helpers.dart';
import '../../utils/target_distribution.dart';

class GoalsScreen extends StatefulWidget {
  const GoalsScreen({super.key});

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

/// قراءة هدف شهري واحد من خريطة `targets.<month>`.
/// تستقبل نفس الشكل الذي يكتبه Backend (الحقول الخمسة القانونية) وتعيد
/// 0 عند غياب الحقل — بلا أي حسابات أو قيم بديلة.
double monthlyGoalValue(Map? monthlyGoals, String field) {
  final raw = monthlyGoals?[field];
  if (raw is num) return raw.toDouble();
  return 0;
}

const List<String> _arabicMonths = <String>[
  'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
  'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
];

const Map<String, String> _goalUnits = <String, String>{
  'financialTarget': 'ج.م',
  'hoursTarget': 'ساعة',
  'invoicesTarget': 'فاتورة',
  'clientsTarget': 'عميل',
  'visitsTarget': 'زيارة',
};

const Map<String, IconData> _goalIcons = <String, IconData>{
  'financialTarget': Icons.payments_outlined,
  'hoursTarget': Icons.timer_outlined,
  'invoicesTarget': Icons.description_outlined,
  'clientsTarget': Icons.people_outlined,
  'visitsTarget': Icons.location_on_outlined,
};

/// ترتيب البطاقات: المالي أولًا (مُبرز)، ثم البقية.
const List<String> _goalOrder = <String>[
  'financialTarget',
  'invoicesTarget',
  'hoursTarget',
  'visitsTarget',
  'clientsTarget',
];

class _GoalsScreenState extends State<GoalsScreen> {
  static const Color _teal = Color(0xFF1ABC9C);
  static const Color _tealDark = Color(0xFF0E7C66);
  static const Color _ink = Color(0xFF2C3E50);
  static const Color _page = Color(0xFFEEF2F5);

  bool _isLoading = true;
  Map<String, dynamic>? _userData;
  Map<String, dynamic> _stats = {
    'totalSales': 0.0,
    'totalOrders': 0,
    'workingHours': 0.0,
    'totalVisits': 0,
  };
  List<Offset> _chartData = [];
  Map<String, dynamic>? _monthlyGoals;
  bool _accessDenied = false;
  String _monthKey = '';
  DateTime? _firstDay;
  DateTime? _lastDay;

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataString = prefs.getString('userData');
      if (userDataString == null) return;
      _userData = jsonDecode(userDataString);
      // Goals are permanent-only: freelance reps are stopped here, before
      // any data load, even on direct navigation to this screen.
      if (!canViewGoals(_userData!['repType'])) {
        if (mounted) {
          setState(() {
            _accessDenied = true;
            _isLoading = false;
          });
        }
        return;
      }
      final repCode = _userData!['repCode'];

      DateTime now = DateTime.now();
      DateTime firstDay = DateTime(now.year, now.month, 1);
      DateTime lastDay = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
      String monthKey = DateFormat('yyyy-MM').format(now);

      // 1. جلب الأهداف من مجموعة salesRep
      final repSnap = await FirebaseFirestore.instance
          .collection('salesRep')
          .where('repCode', isEqualTo: repCode)
          .get();
      if (repSnap.docs.isNotEmpty) {
        var data = repSnap.docs.first.data();
        if (data['targets'] != null && data['targets'][monthKey] != null) {
          _monthlyGoals = data['targets'][monthKey];
        }
      }

      // 2. جلب الأوردرات وتحضير بيانات الرسم البياني
      final ordersSnap = await FirebaseFirestore.instance
          .collection('orders')
          .where('buyer.repCode', isEqualTo: repCode)
          .where('orderDate', isGreaterThanOrEqualTo: firstDay)
          .where('orderDate', isLessThanOrEqualTo: lastDay)
          .orderBy('orderDate')
          .get();

      double sales = 0;
      Map<int, double> dailySales = {};
      for (var doc in ordersSnap.docs) {
        var data = doc.data();
        double total = (data['total'] ?? 0).toDouble();
        sales += total;
        
        DateTime date = (data['orderDate'] as Timestamp).toDate();
        dailySales[date.day] = (dailySales[date.day] ?? 0) + total;
      }

      // تحويل البيانات لنقاط على الرسم البياني
        _chartData = dailySales.entries
          .map((e) => Offset(e.key.toDouble(), e.value))
          .toList();
        if (_chartData.isEmpty) _chartData = [Offset.zero];

      // 3. جلب ساعات العمل من daily_logs
      final logsSnap = await FirebaseFirestore.instance
          .collection('daily_logs')
          .where('repCode', isEqualTo: repCode)
          .where('startTime', isGreaterThanOrEqualTo: firstDay)
          .get();

      double hours = 0;
      for (var doc in logsSnap.docs) {
        var log = doc.data();
        if (log['startTime'] != null && log['endTime'] != null) {
          DateTime start = (log['startTime'] as Timestamp).toDate();
          DateTime end = (log['endTime'] as Timestamp).toDate();
          hours += end.difference(start).inMinutes / 60.0;
        }
      }

      setState(() {
        _stats['totalSales'] = sales;
        _stats['totalOrders'] = ordersSnap.docs.length;
        _stats['workingHours'] = hours;
        _stats['totalVisits'] = logsSnap.docs.length;
        _monthKey = monthKey;
        _firstDay = firstDay;
        _lastDay = DateTime(lastDay.year, lastDay.month, lastDay.day);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Error: $e");
      setState(() => _isLoading = false);
    }
  }

  /// المحقق الحالي لكل حقل من نفس مصادر الشاشة — بلا أي مصدر جديد.
  /// العملاء بلا عدّاد محقق في المصادر الحالية فيُعرض المستهدف فقط.
  double? _achievedFor(String field) {
    switch (field) {
      case 'financialTarget':
        return (_stats['totalSales'] as num).toDouble();
      case 'invoicesTarget':
        return (_stats['totalOrders'] as num).toDouble();
      case 'hoursTarget':
        return (_stats['workingHours'] as num).toDouble();
      case 'visitsTarget':
        return (_stats['totalVisits'] as num).toDouble();
      default:
        return null;
    }
  }

  String _fmtNum(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    if (v >= 100) return v.toStringAsFixed(0);
    return v.toStringAsFixed(1);
  }

  String _monthTitle() {
    final now = DateTime.now();
    return 'أهداف شهر ${_arabicMonths[now.month - 1]} ${now.year}';
  }

  String _periodLine() {
    if (_monthKey.isEmpty || _firstDay == null || _lastDay == null) {
      return DateFormat('yyyy-MM').format(DateTime.now());
    }
    final fmt = DateFormat('d/M/yyyy');
    return '$_monthKey • من ${fmt.format(_firstDay!)} إلى ${fmt.format(_lastDay!)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _page,
      appBar: AppBar(
        title: const Text("أهداف الشهر الحالي",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : _accessDenied
              ? const Center(
                  child: Text("شاشة الأهداف متاحة للموظفين الثابتين (Permanent) فقط."))
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth > 600;
                    final rest = _goalOrder.where((f) => f != 'financialTarget').toList();
                    return SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildPeriodCard(),
                          const SizedBox(height: 12),
                          _buildFinancialHero(),
                          const SizedBox(height: 12),
                          if (wide)
                            GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                                mainAxisExtent: 190,
                              ),
                              itemCount: rest.length,
                              itemBuilder: (ctx, i) => _buildGoalCard(rest[i]),
                            )
                          else
                            ...rest.map((f) => Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: _buildGoalCard(f),
                                )),
                          const SizedBox(height: 12),
                          const Text("منحنى المبيعات اليومي",
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 17,
                                  color: _ink)),
                          const SizedBox(height: 8),
                          _buildChartCard(),
                        ],
                      ),
                    );
                  },
                ),
    );
  }

  Widget _buildPeriodCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10)],
      ),
      child: Row(
        children: [
          const Icon(Icons.calendar_month_outlined, color: _teal, size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_monthTitle(),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 17, color: _ink)),
                const SizedBox(height: 4),
                Text(_periodLine(),
                    style: const TextStyle(fontSize: 13, color: Color(0xFF5D6D7E))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFinancialHero() {
    final goal = monthlyGoalValue(_monthlyGoals, 'financialTarget');
    final actual = _achievedFor('financialTarget') ?? 0;
    final percent = goal > 0 ? actual / goal : 0.0;
    final pctText = '${(percent * 100).toStringAsFixed(percent >= 1 ? 0 : 1)}%';
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _tealDark,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: _tealDark.withValues(alpha: 0.25), blurRadius: 14)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.payments_outlined, color: Colors.white, size: 26),
              SizedBox(width: 10),
              Text('الهدف المالي للمبيعات',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 17)),
            ],
          ),
          const SizedBox(height: 12),
          Text('${_fmtNum(actual)} ج.م',
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 32)),
          const SizedBox(height: 4),
          Text(
            goal > 0
                ? 'المستهدف: ${_fmtNum(goal)} ج.م • الإنجاز: $pctText'
                : 'لم يُسند هدف مالي لهذا الشهر بعد',
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          if (goal > 0) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: percent > 1.0 ? 1.0 : percent,
                backgroundColor: Colors.white24,
                color: Colors.white,
                minHeight: 10,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGoalCard(String field) {
    final goal = monthlyGoalValue(_monthlyGoals, field);
    final actual = _achievedFor(field);
    final unit = _goalUnits[field] ?? '';
    final label = kTargetLabelsAr[field] ?? field;
    final percent = (goal > 0 && actual != null) ? actual / goal : 0.0;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(_goalIcons[field], color: _teal, size: 24),
              const SizedBox(width: 10),
              Expanded(
                child: Text(label,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15, color: _ink)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (actual != null)
            Text('${_fmtNum(actual)} $unit',
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 26, color: _ink))
          else
            Text('${_fmtNum(goal)} $unit',
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 26, color: _ink)),
          const SizedBox(height: 4),
          if (goal > 0 && actual != null)
            Text('المستهدف: ${_fmtNum(goal)} $unit',
                style: const TextStyle(fontSize: 14, color: Color(0xFF5D6D7E)))
          else if (goal <= 0)
            const Text('لم يُسند هدف لهذا الشهر بعد',
                style: TextStyle(fontSize: 13, color: Color(0xFFB7791F)))
          else
            Text('المستهدف: ${_fmtNum(goal)} $unit • $_monthKey',
                style: const TextStyle(fontSize: 14, color: Color(0xFF5D6D7E))),
          if (goal > 0 && actual != null) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: percent > 1.0 ? 1.0 : percent,
                backgroundColor: const Color(0xFFE5E8EC),
                color: percent >= 1.0 ? Colors.green : _teal,
                minHeight: 9,
              ),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${(percent * 100).toStringAsFixed(percent >= 1 ? 0 : 1)}%',
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.bold, color: _ink),
              ),
            ),
          ],
          if (actual == null && goal > 0)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('لا يوجد عدّاد محقق مرتبط في المصادر الحالية',
                  style: TextStyle(fontSize: 12, color: Color(0xFF5D6D7E))),
            ),
        ],
      ),
    );
  }

  Widget _buildChartCard() {
    return Container(
      height: 250,
      padding: const EdgeInsets.fromLTRB(10, 20, 20, 10),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: CustomPaint(
        painter: _SalesChartPainter(_chartData),
      ),
    );
  }
}

class _SalesChartPainter extends CustomPainter {
  final List<Offset> data;

  const _SalesChartPainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final sorted = [...data]..sort((a, b) => a.dx.compareTo(b.dx));
    final maxDay = sorted.last.dx <= 0 ? 1.0 : sorted.last.dx;
    final maxSales = sorted.map((point) => point.dy).reduce((a, b) => a > b ? a : b);
    final salesRange = maxSales <= 0 ? 1.0 : maxSales;
    final points = sorted.map((point) => Offset(
          point.dx / maxDay * size.width,
          size.height - point.dy / salesRange * size.height,
        )).toList();

    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      line.lineTo(point.dx, point.dy);
    }
    final area = Path.from(line)
      ..lineTo(points.last.dx, size.height)
      ..lineTo(points.first.dx, size.height)
      ..close();

    canvas.drawPath(area, Paint()..color = const Color(0x1A1ABC9C));
    canvas.drawPath(
      line,
      Paint()
        ..color = const Color(0xFF1ABC9C)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SalesChartPainter oldDelegate) => oldDelegate.data != data;
}
