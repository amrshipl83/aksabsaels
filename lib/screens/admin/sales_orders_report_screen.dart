import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:intl/intl.dart';

class SalesOrdersReportScreen extends StatefulWidget {
  const SalesOrdersReportScreen({super.key});

  @override
  State<SalesOrdersReportScreen> createState() => _SalesOrdersReportScreenState();
}

class _SalesOrdersReportScreenState extends State<SalesOrdersReportScreen> {
  Map<String, dynamic>? _userData;
  bool _isLoading = true;
  List<String> _targetRepCodes = [];

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  Future<void> _initializeData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = prefs.getString('userData');
      if (data != null) {
        _userData = jsonDecode(data);
        await _fetchHierarchy();
      }
    } catch (e) {
      debugPrint("Init Data Error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchHierarchy() async {
    String role = _userData?['role'] ?? '';
    String myDocId = _userData?['docId'] ?? '';
    List<String> codes = [];

    try {
      if (role == 'sales_manager') {
        var supervisors = await FirebaseFirestore.instance
            .collection('managers')
            .where('managerId', isEqualTo: myDocId)
            .get();
        
        List<String> supervisorIds = supervisors.docs.map((d) => d.id).toList();

        if (supervisorIds.isNotEmpty) {
          var reps = await FirebaseFirestore.instance
              .collection('salesRep')
              .where('supervisorId', whereIn: supervisorIds)
              .get();
          codes = reps.docs.map((d) => d['repCode'] as String).toList();
        }
      } else if (role == 'sales_supervisor') {
        var reps = await FirebaseFirestore.instance
            .collection('salesRep')
            .where('supervisorId', isEqualTo: myDocId)
            .get();
        codes = reps.docs.map((d) => d['repCode'] as String).toList();
      }

      if (mounted) {
        setState(() {
          _targetRepCodes = codes;
        });
      }
    } catch (e) {
      debugPrint("Error Building Sales Hierarchy: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: const Text("تقرير الطلبات", 
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), // استخدمنا 18 ثابتة
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF2F3542),
        elevation: 0.5,
        centerTitle: true,
      ),
      body: _targetRepCodes.isEmpty 
          ? _emptyState() 
          : _buildOrdersStream(),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.inventory_2_outlined, size: 60, color: Colors.grey),
          SizedBox(height: 16),
          Text("لا توجد طلبات لعرضها حالياً", 
            style: TextStyle(fontSize: 16, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildOrdersStream() {
    // حل مشكلة whereIn لا تقبل قائمة فارغة
    if (_targetRepCodes.isEmpty) return _emptyState();

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('orders')
          .where('buyer.repCode', whereIn: _targetRepCodes)
          .orderBy('orderDate', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text("خطأ: ${snapshot.error}"));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        var orders = snapshot.data!.docs;
        if (orders.isEmpty) return _emptyState();

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: orders.length,
          itemBuilder: (context, index) {
            var data = orders[index].data() as Map<String, dynamic>;
            return _orderCard(data, orders[index].id);
          },
        );
      },
    );
  }

  Widget _orderCard(Map<String, dynamic> order, String id) {
    var buyer = order['buyer'] as Map<String, dynamic>?;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: const Color(0xFF1ABC9C).withOpacity(0.1),
          child: const Icon(Icons.shopping_cart, color: Color(0xFF1ABC9C), size: 20),
        ),
        title: Text(buyer?['name'] ?? 'بدون اسم', 
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Text("القيمة: ${order['total']} ج.م", 
          style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.w600)),
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _infoRow(Icons.numbers, "رقم الطلب", id),
                _infoRow(Icons.calendar_today, "التاريخ", _formatDate(order['orderDate'])),
                _infoRow(Icons.location_on, "العنوان", buyer?['address'] ?? '-'),
                _infoRow(Icons.person_outline, "المندوب", buyer?['repName'] ?? '-'),
                const Divider(),
                const Text("الأصناف:", 
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                ...((order['items'] as List? ?? []).map((item) => ListTile(
                  dense: true,
                  title: Text(item['productName'] ?? ''),
                  trailing: Text("الكمية: ${item['quantity']}"),
                ))),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Colors.grey),
          const SizedBox(width: 8),
          Text("$label: ", style: TextStyle(color: Colors.grey[600], fontSize: 12)),
          Expanded(child: Text(value, 
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }

  String _formatDate(dynamic ts) {
    if (ts == null) return "-";
    try {
      DateTime dt = (ts as Timestamp).toDate();
      return DateFormat('yyyy-MM-dd').format(dt);
    } catch (e) {
      return ts.toString();
    }
  }
}

