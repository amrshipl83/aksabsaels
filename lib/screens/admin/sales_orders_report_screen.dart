import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:sizer/sizer.dart';

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
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('userData');
    if (data != null) {
      _userData = jsonDecode(data);
      await _fetchHierarchy();
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _fetchHierarchy() async {
    String role = _userData?['role'] ?? '';
    String myDocId = _userData?['docId'] ?? '';
    List<String> codes = [];

    try {
      if (role == 'sales_manager') {
        // جلب المشرفين التابعين للمدير
        var supervisors = await FirebaseFirestore.instance
            .collection('managers')
            .where('managerId', isEqualTo: myDocId)
            .get();
        
        List<String> supervisorIds = supervisors.docs.map((d) => d.id).toList();

        if (supervisorIds.isNotEmpty) {
          // جلب المناديب التابعين للمشرفين
          var reps = await FirebaseFirestore.instance
              .collection('salesRep')
              .where('supervisorId', whereIn: supervisorIds)
              .get();
          codes = reps.docs.map((d) => d['repCode'] as String).toList();
        }
      } else if (role == 'sales_supervisor') {
        // المشرف يجيب مناديبه مباشرة بمفتاح docId
        var reps = await FirebaseFirestore.instance
            .collection('salesRep')
            .where('supervisorId', isEqualTo: myDocId)
            .get();
        codes = reps.docs.map((d) => d['repCode'] as String).toList();
      }

      setState(() => _targetRepCodes = codes);
    } catch (e) {
      debugPrint("Error Building Sales Hierarchy: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F6FA),
        appBar: AppBar(
          title: Text("تقرير الطلبات", style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF2F3542),
          elevation: 0.5,
        ),
        body: _targetRepCodes.isEmpty 
            ? _emptyState() 
            : _buildOrdersStream(),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_2_outlined, size: 50.sp, color: Colors.grey),
          SizedBox(height: 10.sp),
          Text("لا توجد طلبات لعرضها حالياً", style: TextStyle(fontSize: 14.sp, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildOrdersStream() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('orders')
          .where('buyer.repCode', whereIn: _targetRepCodes)
          .orderBy('orderDate', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text("حدث خطأ في جلب الطلبات"));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        var orders = snapshot.data!.docs;
        if (orders.isEmpty) return _emptyState();

        return ListView.builder(
          padding: EdgeInsets.all(10.sp),
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
      margin: EdgeInsets.only(bottom: 12.sp),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: const Color(0xFF1ABC9C).withOpacity(0.1),
          child: Icon(Icons.shopping_cart, color: const Color(0xFF1ABC9C), size: 18.sp),
        ),
        title: Text(buyer?['name'] ?? 'بدون اسم', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.sp)),
        subtitle: Text("القيمة: ${order['total']} ج.م", style: TextStyle(color: Colors.blue, fontWeight: FontWeight.w600)),
        children: [
          Padding(
            padding: EdgeInsets.all(12.sp),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _infoRow(Icons.numbers, "رقم الطلب", id),
                _infoRow(Icons.calendar_today, "التاريخ", _formatDate(order['orderDate'])),
                _infoRow(Icons.location_on, "العنوان", buyer?['address'] ?? '-'),
                _infoRow(Icons.person_outline, "المندوب", buyer?['repName'] ?? '-'),
                const Divider(),
                Text("الأصناف:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.sp)),
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
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 12.sp, color: Colors.grey),
          SizedBox(width: 5.sp),
          Text("$label: ", style: TextStyle(color: Colors.grey[600], fontSize: 11.sp)),
          Expanded(child: Text(value, style: TextStyle(fontSize: 11.sp, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }

  String _formatDate(dynamic ts) {
    if (ts == null) return "-";
    DateTime dt = (ts as Timestamp).toDate();
    return DateFormat('yyyy-MM-dd').format(dt);
  }
}

