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

  // فلاتر التاريخ
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 7)); // افتراضياً آخر أسبوع
  DateTime _endDate = DateTime.now();

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
          repsData = reps.docs.map((d) => {
                'repCode': d.data().containsKey('repCode') ? d['repCode'].toString() : '',
                'repName': d.data().containsKey('fullname') ? d['fullname'] : 'غير مسمى'
              }).toList();
        }
      } else if (role == 'sales_supervisor') {
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

    return Scaffold(
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
          _buildTopFilterBar(), // شريط الفلاتر الموحد
          Expanded(
            child: _baseRepCodes.isEmpty
                ? _emptyState("لا يوجد مناديب مسجلين تحت إدارتك")
                : _buildOrdersStream(),
          ),
        ],
      ),
    );
  }

  Widget _buildTopFilterBar() {
    return Container(
      padding: EdgeInsets.all(10.sp),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5)],
      ),
      child: Column(
        children: [
          // فلاتر التاريخ
          Row(
            children: [
              _dateButton("من:", _startDate, (d) => setState(() => _startDate = d!)),
              SizedBox(width: 8.sp),
              _dateButton("إلى:", _endDate, (d) => setState(() => _endDate = d!)),
            ],
          ),
          const Divider(),
          // اختيار المندوب
          Row(
            children: [
              Expanded(
                child: ActionChip(
                  backgroundColor: const Color(0xFFF1F2F6),
                  avatar: Icon(Icons.person, size: 14.sp, color: const Color(0xFF1ABC9C)),
                  label: Text(
                    _selectedRepCode == null
                        ? "كل المناديب (${_allReps.length})"
                        : _allReps.firstWhere((r) => r['repCode'] == _selectedRepCode)['repName'],
                    style: TextStyle(fontSize: 10.sp),
                  ),
                  onPressed: _showRepSelector,
                ),
              ),
              if (_selectedRepCode != null)
                IconButton(
                    icon: Icon(Icons.highlight_off, color: Colors.redAccent, size: 18.sp),
                    onPressed: () => setState(() => _selectedRepCode = null)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dateButton(String label, DateTime date, Function(DateTime?) onSelect) {
    return Expanded(
      child: InkWell(
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: date,
            firstDate: DateTime(2025),
            lastDate: DateTime.now(),
          );
          if (picked != null) onSelect(picked);
        },
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 6.sp, horizontal: 8.sp),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey[200]!),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Text(label, style: TextStyle(fontSize: 9.sp, color: Colors.grey)),
              SizedBox(width: 4.sp),
              Text(DateFormat('yyyy-MM-dd').format(date),
                  style: TextStyle(fontSize: 9.sp, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
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
                    onTap: () {
                      setState(() => _selectedRepCode = null);
                      Navigator.pop(context);
                    },
                  );
                }
                var rep = _allReps[i - 1];
                return ListTile(
                  title: Text(rep['repName']),
                  leading: const Icon(Icons.person_outline),
                  trailing: _selectedRepCode == rep['repCode'] ? const Icon(Icons.check, color: Colors.green) : null,
                  onTap: () {
                    setState(() => _selectedRepCode = rep['repCode']);
                    Navigator.pop(context);
                  },
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

    // تطبيق فلاتر التاريخ (هنا نحتاج حقل orderDate كـ Timestamp)
    query = query
        .where('orderDate', isGreaterThanOrEqualTo: Timestamp.fromDate(DateTime(_startDate.year, _startDate.month, _startDate.day)))
        .where('orderDate', isLessThanOrEqualTo: Timestamp.fromDate(DateTime(_endDate.year, _endDate.month, _endDate.day, 23, 59, 59)));

    // تطبيق فلاتر المندوب
    if (_selectedRepCode != null) {
      query = query.where('buyer.repCode', isEqualTo: _selectedRepCode);
    } else if (_baseRepCodes.isNotEmpty) {
      query = query.where('buyer.repCode', whereIn: _baseRepCodes);
    }

    query = query.orderBy('orderDate', descending: true);

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text("خطأ: يرجى التأكد من وجود Index في Firestore"));
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
      elevation: 1.5,
      margin: EdgeInsets.only(bottom: 10.sp),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        leading: CircleAvatar(
            backgroundColor: const Color(0xFFF1F2F6),
            child: Icon(Icons.receipt_long, color: const Color(0xFF1ABC9C), size: 16.sp)),
        title: Text(buyer?['name'] ?? 'عميل مجهول', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.sp)),
        subtitle: Text("المبلغ: ${order['total']} ج.م",
            style: TextStyle(color: Colors.blue[800], fontWeight: FontWeight.bold, fontSize: 10.sp)),
        children: [
          Padding(
            padding: EdgeInsets.all(10.sp),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _infoRow(Icons.calendar_month, "توقيت الطلب", _formatDate(order['orderDate'])),
                _infoRow(Icons.person, "كود المندوب", buyer?['repCode'] ?? '-'),
                const Divider(),
                ...((order['items'] as List? ?? []).map((item) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(item['name'] ?? 'منتج', style: TextStyle(fontSize: 10.sp)),
                      trailing: Text("سعر: ${item['price']} x ${item['quantity']}",
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 9.sp)),
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
    return Center(
        child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.event_busy, size: 40.sp, color: Colors.grey[300]),
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

