import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:sizer/sizer.dart';

class GoalsScreen extends StatefulWidget {
  const GoalsScreen({super.key});

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  Map<String, dynamic>? _repData;
  final Color primaryColor = const Color(0xFF1ABC9C);
  final Color darkColor = const Color(0xFF2C3E50);

  @override
  void initState() {
    super.initState();
    _loadRepData();
  }

  Future<void> _loadRepData() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('userData');
    if (data != null) setState(() => _repData = jsonDecode(data));
  }

  String getCurrentMonthYear() => DateFormat('yyyy-MM').format(DateTime.now());

  @override
  Widget build(BuildContext context) {
    if (_repData == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      backgroundColor: const Color(0xFFEEF2F5),
      appBar: AppBar(
        title: Text("أداء المندوب", style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold)),
        backgroundColor: darkColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('salesRep').doc(_repData!['uid']).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          
          var data = snapshot.data!.data() as Map<String, dynamic>;
          String monthYear = getCurrentMonthYear();
          var goals = data['targets'] != null ? data['targets'][monthYear] : null;

          return SingleChildScrollView(
            padding: EdgeInsets.all(15.dp),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildRepHeader(),
                SizedBox(height: 2.h),
                
                Text("مقاييس الشهر الحالي ($monthYear)", 
                    style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.bold, color: darkColor)),
                SizedBox(height: 1.5.h),

                if (goals == null) 
                  _buildNoGoalsCard()
                else ...[
                  _buildKPICard("المبيعات", (data['currentSales'] ?? 0).toDouble(), (goals['financialTarget'] ?? 0).toDouble(), "ج.م"),
                  _buildKPICard("الطلبات", (data['currentOrders'] ?? 0).toDouble(), (goals['invoiceTarget'] ?? 0).toDouble(), "طلب"),
                ],

                SizedBox(height: 2.h),
                Text("منحنى المبيعات اليومي", 
                    style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.bold, color: darkColor)),
                SizedBox(height: 1.5.h),
                
                _buildSalesChart(data['dailySalesProgress'] ?? {}), // نفترض وجود ماب للمبيعات اليومية
                SizedBox(height: 5.h),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildRepHeader() {
    return Container(
      padding: EdgeInsets.all(12.dp),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border(right: BorderSide(color: primaryColor, width: 5)),
      ),
      child: Row(
        children: [
          CircleAvatar(radius: 25.dp, backgroundColor: primaryColor, child: Icon(Icons.person, color: Colors.white, size: 25.dp)),
          SizedBox(width: 10.dp),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_repData!['fullname'], style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold)),
              Text("REP: ${_repData!['repCode']}", style: TextStyle(fontSize: 10.sp, color: Colors.grey)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKPICard(String title, double actual, double target, String unit) {
    double progress = target > 0 ? (actual / target) : 0;
    return Container(
      margin: EdgeInsets.only(bottom: 10.dp),
      padding: EdgeInsets.all(15.dp),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: TextStyle(fontSize: 11.sp, color: Colors.grey)),
              Text("${actual.toInt()} / ${target.toInt()} $unit", style: TextStyle(fontWeight: FontWeight.bold, color: primaryColor)),
            ],
          ),
          SizedBox(height: 10.dp),
          LinearProgressIndicator(
            value: progress > 1 ? 1 : progress,
            minHeight: 8,
            backgroundColor: Colors.grey[200],
            valueColor: AlwaysStoppedAnimation<Color>(progress >= 1 ? Colors.green : primaryColor),
          ),
        ],
      ),
    );
  }

  Widget _buildSalesChart(Map<String, dynamic> dailyData) {
    // تحويل البيانات لـ FlSpot للرسم البياني
    List<FlSpot> spots = [];
    if (dailyData.isEmpty) {
      spots = [const FlSpot(0, 0), const FlSpot(1, 0)];
    } else {
      // ترتيب الأيام ورسمها
      var sortedKeys = dailyData.keys.toList()..sort();
      for (int i = 0; i < sortedKeys.length; i++) {
        spots.add(FlSpot(i.toDouble(), (dailyData[sortedKeys[i]] as num).toDouble()));
      }
    }

    return Container(
      height: 250,
      padding: EdgeInsets.only(right: 20.dp, top: 20.dp, bottom: 10.dp),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: LineChart(
        LineChartData(
          gridData: const FlGridData(show: false),
          titlesData: const FlTitlesData(show: false), // لإبقاء الشكل بسيطاً وجميلاً
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: primaryColor,
              barWidth: 4,
              belowBarData: BarAreaData(show: true, color: primaryColor.withOpacity(0.1)),
              dotData: const FlDotData(show: true),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoGoalsCard() {
    return Card(child: ListTile(leading: const Icon(Icons.info), title: const Text("لا توجد أهداف محددة لهذا الشهر")));
  }
}

