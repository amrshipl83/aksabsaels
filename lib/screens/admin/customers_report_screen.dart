import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:sizer/sizer.dart';

class CustomersReportScreen extends StatefulWidget {
  const CustomersReportScreen({super.key});

  @override
  State<CustomersReportScreen> createState() => _CustomersReportScreenState();
}

class _CustomersReportScreenState extends State<CustomersReportScreen> {
  Map<String, dynamic>? _userData;
  bool _isLoading = true;
  List<String> _targetRepCodes = [];
  String _searchQuery = "";

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
      debugPrint("Init Error: $e");
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
          codes = reps.docs.map((d) => d['repCode']?.toString() ?? '').toList();
        }
      } else if (role == 'sales_supervisor') {
        var reps = await FirebaseFirestore.instance
            .collection('salesRep')
            .where('supervisorId', isEqualTo: myDocId)
            .get();
        codes = reps.docs.map((d) => d['repCode']?.toString() ?? '').toList();
      }
      setState(() => _targetRepCodes = codes);
    } catch (e) {
      debugPrint("Hierarchy Error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    // ✅ يبدأ بـ Scaffold مباشرة بدون Directionality
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: Text("تقرير العملاء والمسحوبات", 
            style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF2F3542),
        elevation: 0.5,
        centerTitle: true,
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          Expanded(
            child: _targetRepCodes.isEmpty
                ? _emptyState("لا يوجد مناديب تابعة لك لعرض عملائهم")
                : _buildCustomersStream(),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: EdgeInsets.all(10.sp),
      color: Colors.white,
      child: TextField(
        onChanged: (v) => setState(() => _searchQuery = v),
        decoration: InputDecoration(
          hintText: "بحث باسم العميل أو الكود...",
          prefixIcon: const Icon(Icons.search),
          filled: true,
          fillColor: const Color(0xFFF1F2F6),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10), 
              borderSide: BorderSide.none),
        ),
      ),
    );
  }

  Widget _buildCustomersStream() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .where('repCode', whereIn: _targetRepCodes)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        var docs = snapshot.data!.docs.where((d) {
          var name = (d['fullname'] ?? '').toString().toLowerCase();
          return name.contains(_searchQuery.toLowerCase());
        }).toList();

        if (docs.isEmpty) return _emptyState("لا يوجد عملاء مطابقين للبحث");

        return ListView.builder(
          padding: EdgeInsets.all(10.sp),
          itemCount: docs.length,
          itemBuilder: (context, index) => _customerCard(docs[index]),
        );
      },
    );
  }

  Widget _customerCard(DocumentSnapshot doc) {
    var data = doc.data() as Map<String, dynamic>;
    return Card(
      margin: EdgeInsets.only(bottom: 12.sp),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: ExpansionTile(
        tilePadding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 4.sp),
        leading: CircleAvatar(
          backgroundColor: const Color(0xFF1ABC9C).withOpacity(0.1),
          child: Icon(Icons.person, color: const Color(0xFF1ABC9C), size: 18.sp),
        ),
        // ✅ الاسم بخط 18 كما طلبت
        title: Text(
          data['fullname'] ?? 'بدون اسم',
          style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold, color: const Color(0xFF2F3542)),
        ),
        subtitle: Text("كود المندوب: ${data['repCode']}", style: TextStyle(fontSize: 10.sp)),
        children: [
          Padding(
            padding: EdgeInsets.all(12.sp),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _infoRow(Icons.phone, "الهاتف", data['phone'] ?? '-'),
                _infoRow(Icons.location_on, "العنوان", data['address'] ?? '-'),
                const Divider(),
                Text("آخر المسحوبات:", 
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.sp, color: Colors.blueGrey)),
                _buildLastOrders(doc.id),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildLastOrders(String customerId) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('orders')
          .where('buyer.id', isEqualTo: customerId)
          .orderBy('orderDate', descending: true)
          .limit(3)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const LinearProgressIndicator();
        if (snapshot.data!.docs.isEmpty) return const Text("لا توجد طلبات سابقة");

        return Column(
          children: snapshot.data!.docs.map((o) {
            Timestamp? t = o['orderDate'] as Timestamp?;
            String dateStr = t != null ? DateFormat('yyyy-MM-dd').format(t.toDate()) : '-';
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text("طلب بتاريخ: $dateStr"),
              trailing: Text("${o['total']} ج.م", 
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 3.sp),
      child: Row(
        children: [
          Icon(icon, size: 12.sp, color: Colors.grey),
          SizedBox(width: 8.sp),
          Text("$label: ", style: TextStyle(fontSize: 10.sp, color: Colors.grey[600])),
          Expanded(child: Text(value, style: TextStyle(fontSize: 11.sp, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }

  Widget _emptyState(String msg) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline, size: 50.sp, color: Colors.grey[300]),
          Text(msg, style: TextStyle(color: Colors.grey, fontSize: 12.sp)),
        ],
      ),
    );
  }
}

