import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:fl_chart/fl_chart.dart'; // تأكد من إضافة fl_chart في pubspec.yaml

// --- الثوابت اللونية ---
const Color kPrimaryColor = Color(0xFF43B97F);
const Color kSecondaryColor = Color(0xFF1A2C3D);
const Color kBgColor = Color(0xFFf0f2f5);

class RepReportsScreen extends StatefulWidget {
  const RepReportsScreen({super.key});

  @override
  State<RepReportsScreen> createState() => _RepReportsScreenState();
}

class _RepReportsScreenState extends State<RepReportsScreen> {
  Map<String, dynamic>? repData;
  bool _isLoading = true;
  List<Map<String, dynamic>> allOrders = [];
  double totalSales = 0.0;
  Map<String, double> salesByStatus = {};
  Map<String, int> ordersCountByStatus = {};

  @override
  void initState() {
    super.initState();
    _loadRepDataAndOrders();
  }

  Future<void> _loadRepDataAndOrders() async {
    final prefs = await SharedPreferences.getInstance();
    final userDataString = prefs.getString('userData');
    if (userDataString != null) {
      repData = jsonDecode(userDataString);
      await _fetchOrders();
    }
  }

  Future<void> _fetchOrders() async {
    setState(() => _isLoading = true);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('orders')
          .where('buyer.repCode', isEqualTo: repData!['repCode'])
          .get();

      double tempTotal = 0;
      Map<String, double> tempStatusSales = {};
      Map<String, int> tempStatusCount = {};

      for (var doc in snapshot.docs) {
        var data = doc.data();
        double orderTotal = (data['total'] ?? 0).toDouble();
        String status = data['status'] ?? 'جديد';

        tempTotal += orderTotal;
        tempStatusSales[status] = (tempStatusSales[status] ?? 0) + orderTotal;
        tempStatusCount[status] = (tempStatusCount[status] ?? 0) + 1;
      }

      setState(() {
        totalSales = tempTotal;
        salesByStatus = tempStatusSales;
        ordersCountByStatus = tempStatusCount;
        _isLoading = false;
      });
    } catch (e) {
      print("Error fetching reports: $e");
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: kBgColor,
        appBar: AppBar(
          title: const Text('تقارير أدائي', style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: Colors.white,
          foregroundColor: kSecondaryColor,
          elevation: 0.5,
          centerTitle: true,
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(color: kPrimaryColor))
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildTotalCard(),
                    const SizedBox(height: 20),
                    _buildStatusChartSection(),
                    const SizedBox(height: 20),
                    _buildStatusTable(),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildTotalCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: kPrimaryColor,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [BoxShadow(color: kPrimaryColor.withOpacity(0.3), blurRadius: 10)],
      ),
      child: Column(
        children: [
          const Text('إجمالي المبيعات', style: TextStyle(color: Colors.white, fontSize: 16)),
          const SizedBox(height: 10),
          Text(
            '${totalSales.toStringAsFixed(2)} ج.م',
            style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChartSection() {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
      child: Column(
        children: [
          const Text('توزيع المبيعات حسب الحالة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 20),
          SizedBox(
            height: 200,
            child: PieChart(
              PieChartData(
                sections: salesByStatus.entries.map((entry) {
                  return PieChartSectionData(
                    value: entry.value,
                    title: '',
                    color: _getStatusColor(entry.key),
                    radius: 50,
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusTable() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
      child: DataTable(
        columnSpacing: 20,
        columns: const [
          DataColumn(label: Text('الحالة')),
          DataColumn(label: Text('الطلبات')),
          DataColumn(label: Text('الإجمالي')),
        ],
        rows: salesByStatus.entries.map((entry) {
          return DataRow(cells: [
            DataCell(Text(entry.key)),
            DataCell(Text(ordersCountByStatus[entry.key].toString())),
            DataCell(Text('${entry.value.toStringAsFixed(0)} ج.م')),
          ]);
        }).toList(),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'delivered': return Colors.green;
      case 'cancelled': return Colors.red;
      case 'processing': return Colors.orange;
      default: return Colors.blue;
    }
  }
}

