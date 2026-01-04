import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart'; // مكتبة الرسم البياني

class GoalsScreen extends StatefulWidget {
  const GoalsScreen({super.key});

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _userData;
  Map<String, dynamic> _stats = {
    'totalSales': 0.0,
    'totalOrders': 0,
    'workingHours': 0.0,
    'totalVisits': 0,
  };
  List<FlSpot> _chartData = [];
  Map<String, dynamic>? _monthlyGoals;

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
          .map((e) => FlSpot(e.key.toDouble(), e.value))
          .toList();
      if (_chartData.isEmpty) _chartData = [const FlSpot(0, 0)];

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
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Error: $e");
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEEF2F5),
      appBar: AppBar(
        title: const Text("أهداف الشهر الحالي", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1ABC9C),
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1ABC9C)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildKpiCard(
                    "إجمالي مبيعات الشهر",
                    _stats['totalSales'],
                    (_monthlyGoals?['financialTarget'] ?? 0).toDouble(),
                    "ج.م",
                    Icons.payments_outlined,
                  ),
                  _buildKpiCard(
                    "عدد فواتير الشهر",
                    _stats['totalOrders'].toDouble(),
                    (_monthlyGoals?['invoiceTarget'] ?? 0).toDouble(),
                    "فاتورة",
                    Icons.description_outlined,
                  ),
                  const SizedBox(height: 10),
                  const Text("  إحصائيات إضافية", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2C3E50))),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: _buildSmallStat("ساعات العمل", "${_stats['workingHours'].toStringAsFixed(1)} س", Icons.timer_outlined)),
                      const SizedBox(width: 10),
                      Expanded(child: _buildSmallStat("الزيارات", "${_stats['totalVisits']} زيارة", Icons.location_on_outlined)),
                    ],
                  ),
                  const SizedBox(height: 25),
                  const Text("  منحنى المبيعات اليومي", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2C3E50))),
                  const SizedBox(height: 15),
                  _buildChartCard(),
                ],
              ),
            ),
    );
  }

  Widget _buildKpiCard(String title, double actual, double goal, String unit, IconData icon) {
    double percent = (goal > 0) ? (actual / goal) : 0.0;
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10)],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFF1ABC9C), size: 28),
              const SizedBox(width: 12),
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const Spacer(),
              Text("${actual.toStringAsFixed(0)} $unit", style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1ABC9C))),
            ],
          ),
          const SizedBox(height: 15),
          if (goal > 0) ...[
            LinearProgressIndicator(
              value: percent > 1.0 ? 1.0 : percent,
              backgroundColor: Colors.grey[200],
              color: percent >= 1.0 ? Colors.green : const Color(0xFF1ABC9C),
              minHeight: 8,
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("الهدف: $goal", style: const TextStyle(fontSize: 11, color: Colors.grey)),
                Text("${(percent * 100).toStringAsFixed(0)}%", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ],
            ),
          ]
        ],
      ),
    );
  }

  Widget _buildSmallStat(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          Icon(icon, color: const Color(0xFF2C3E50), size: 20),
          const SizedBox(height: 5),
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildChartCard() {
    return Container(
      height: 250,
      padding: const EdgeInsets.fromLTRB(10, 20, 20, 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
      child: LineChart(
        LineChartData(
          gridData: const FlGridData(show: false),
          titlesData: const FlTitlesData(show: false),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: _chartData,
              isCurved: true,
              color: const Color(0xFF1ABC9C),
              barWidth: 4,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(show: true, color: const Color(0xFF1ABC9C).withOpacity(0.1)),
            ),
          ],
        ),
      ),
    );
  }
}

