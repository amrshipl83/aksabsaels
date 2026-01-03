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
  List<Map<String, dynamic>> _allReps = [];
  List<String> _baseRepCodes = [];
  String? _selectedRepCode;

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
    List<Map<String, dynamic>> repsData = [];

    try {
      if (role == 'sales_manager') {
        // 1. جلب كل المشرفين التابعين لهذا المدير
        var supervisors = await FirebaseFirestore.instance
            .collection('managers')
            .where('managerId', isEqualTo: myDocId)
            .get();
        
        List<String> supervisorIds = supervisors.docs.map((d) => d.id).toList();
        
        // 2. جلب كل المناديب التابعين لهؤلاء المشرفين
        if (supervisorIds.isNotEmpty) {
          var reps = await FirebaseFirestore.instance
              .collection('salesRep')
              .where('supervisorId', whereIn: supervisorIds)
              .get();
          repsData = reps.docs.map((d) => {
            'repCode': d.data().containsKey('repCode') ? d['repCode'].toString() : '',
            'repName': d.data().containsKey('fullname') ? d['fullname'] : 'غير مسمى' // تصحيح من repName إلى fullname
          }).toList();
        }
      } else if (role == 'sales_supervisor') {
        // جلب المناديب التابعين لهذا المشرف مباشرة
        var reps = await FirebaseFirestore.instance
            .collection('salesRep')
            .where('supervisorId', isEqualTo: myDocId)
            .get();
        repsData = reps.docs.map((d) => {
          'repCode': d.data().containsKey('repCode') ? d['repCode'].toString() : '',
          'repName': d.data().containsKey('fullname') ? d['fullname'] : 'غير مسمى'
        }).toList();
      }

      if (mounted) {
        setState(() {
          _allReps = repsData;
          _baseRepCodes = repsData
              .map((e) => e['repCode'] as String)
              .where((c) => c.isNotEmpty)
              .toList();
        });
      }
    } catch (e) {
      debugPrint("Hierarchy Error: $e");
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
          centerTitle: true,
        ),
        body: Column(
          children: [
            _buildFilterBar(),
            Expanded(
              child: _baseRepCodes.isEmpty 
                  ? _emptyState("لا يوجد مناديب مسجلين تحت إدارتك") 
                  : _buildOrdersStream(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(vertical: 10.sp, horizontal: 12.sp),
      color: Colors.white,
      child: Row(
        children: [
          Expanded(
            child: ActionChip(
              backgroundColor: const Color(0xFFF1F2F6),
              avatar: Icon(Icons.person, size: 14.sp, color: const Color(0xFF1ABC9C)),
              label: Text(
                _selectedRepCode == null 
                  ? "كل المناديب (${_allReps.length})" 
                  : _allReps.firstWhere((r) => r['repCode'] == _selectedRepCode)['repName'],
                style: TextStyle(fontSize: 11.sp),
              ),
              onPressed: _showRepSelector,
            ),
          ),
          if (_selectedRepCode != null)
            IconButton(
              icon: Icon(Icons.highlight_off, color: Colors.redAccent, size: 20.sp),
              onPressed: () => setState(() => _selectedRepCode = null)
            ),
        ],
      ),
    );
  }

  void _showRepSelector() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Column(
        children: [
          Padding(
            padding: EdgeInsets.all(12.sp),
            child: Text("اختر المندوب", style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold)),
          ),
          const Divider(),
          Expanded(
            child: ListView.builder(
              itemCount: _allReps.length + 1,
              itemBuilder: (context, i) {
                if (i == 0) {
                  return ListTile(
                    title: const Text("كل المناديب"),
                    leading: const Icon(Icons.group),
                    onTap: () { setState(() => _selectedRepCode = null); Navigator.pop(context); },
                  );
                }
                var rep = _allReps[i - 1];
                return ListTile(
                  title: Text(rep['repName']),
                  leading: const Icon(Icons.person_outline),
                  trailing: _selectedRepCode == rep['repCode'] ? const Icon(Icons.check, color: Colors.green) : null,
                  onTap: () { setState(() => _selectedRepCode = rep['repCode']); Navigator.pop(context); },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrdersStream() {
    Query query = FirebaseFirestore.instance.collection('orders');

    if (_selectedRepCode != null) {
      query = query.where('buyer.repCode', isEqualTo: _selectedRepCode);
    } else {
      // جلب أوردرات كل المناديب التابعين (الكتلة)
      query = query.where('buyer.repCode', whereIn: _baseRepCodes);
    }

    query = query.orderBy('orderDate', descending: true);

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Text("خطأ في البيانات: ${snapshot.error}", textAlign: TextAlign.center),
          ));
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        var orders = snapshot.data?.docs ?? [];
        if (orders.isEmpty) return _emptyState("لا توجد طلبات لهذه الفترة");

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
      elevation: 2,
      margin: EdgeInsets.only(bottom: 10.sp),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: const Color(0xFFF1F2F6),
          child: Icon(Icons.receipt_long, color: const Color(0xFF1ABC9C), size: 18.sp)
        ),
        title: Text(buyer?['name'] ?? 'عميل مجهول', 
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.sp)),
        subtitle: Text("الإجمالي: ${order['total']} ج.م", 
            style: TextStyle(color: Colors.blue[800], fontWeight: FontWeight.bold, fontSize: 11.sp)),
        children: [
          Padding(
            padding: EdgeInsets.all(12.sp),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _infoRow(Icons.numbers, "رقم الطلب", id),
                _infoRow(Icons.calendar_month, "التاريخ", _formatDate(order['orderDate'])),
                _infoRow(Icons.person, "المندوب", buyer?['repName'] ?? '-'),
                const Divider(),
                Text("الأصناف:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.sp)),
                ...((order['items'] as List? ?? []).map((item) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(item['name'] ?? 'منتج', style: TextStyle(fontSize: 10.sp)),
                  trailing: Text("الكمية: ${item['quantity']}", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10.sp)),
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
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Icon(icon, size: 12.sp, color: Colors.grey),
        SizedBox(width: 8.sp),
        Text("$label: ", style: TextStyle(color: Colors.grey, fontSize: 10.sp)),
        Expanded(child: Text(value, style: TextStyle(fontSize: 10.sp, fontWeight: FontWeight.w600))),
      ]),
    );
  }

  Widget _emptyState(String msg) {
    return Center(child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.inbox_rounded, size: 40.sp, color: Colors.grey[300]),
        SizedBox(height: 10.sp),
        Text(msg, style: TextStyle(color: Colors.grey, fontSize: 12.sp)),
      ],
    ));
  }

  String _formatDate(dynamic ts) {
    if (ts == null) return "-";
    if (ts is Timestamp) {
      return DateFormat('yyyy-MM-dd HH:mm').format(ts.toDate());
    }
    return ts.toString();
  }
}

