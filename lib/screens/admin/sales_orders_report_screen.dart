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
            'repCode': d['repCode']?.toString() ?? '',
            'repName': d['repName'] ?? 'غير مسمى'
          }).toList();
        }
      } else if (role == 'sales_supervisor') {
        var reps = await FirebaseFirestore.instance
            .collection('salesRep')
            .where('supervisorId', isEqualTo: myDocId)
            .get();
        repsData = reps.docs.map((d) => {
          'repCode': d['repCode']?.toString() ?? '',
          'repName': d['repName'] ?? 'غير مسمى'
        }).toList();
      }

      if (mounted) {
        setState(() {
          _allReps = repsData;
          _baseRepCodes = repsData.map((e) => e['repCode'] as String).where((c) => c.isNotEmpty).toList();
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
        title: const Text("تقرير الطلبات", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF2F3542),
        elevation: 0.5,
        centerTitle: true,
      ),
      body: Column(
        children: [
          _buildFilterBar(),
          Expanded(
            child: _baseRepCodes.isEmpty ? _emptyState("لا يوجد مناديب مسجلين") : _buildOrdersStream(),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      color: Colors.white,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            ActionChip(
              avatar: const Icon(Icons.person, size: 16),
              label: Text(_selectedRepCode == null ? "كل المناديب" : _allReps.firstWhere((r) => r['repCode'] == _selectedRepCode)['repName']),
              onPressed: _showRepSelector,
            ),
            if (_selectedRepCode != null)
              IconButton(icon: const Icon(Icons.refresh, color: Colors.red), onPressed: () => setState(() => _selectedRepCode = null)),
          ],
        ),
      ),
    );
  }

  void _showRepSelector() {
    showModalBottomSheet(
      context: context,
      builder: (context) => ListView.builder(
        itemCount: _allReps.length + 1,
        itemBuilder: (context, i) {
          if (i == 0) return ListTile(title: const Text("كل المناديب"), onTap: () { setState(() => _selectedRepCode = null); Navigator.pop(context); });
          var rep = _allReps[i - 1];
          return ListTile(title: Text(rep['repName']), onTap: () { setState(() => _selectedRepCode = rep['repCode']); Navigator.pop(context); });
        },
      ),
    );
  }

  Widget _buildOrdersStream() {
    Query query = FirebaseFirestore.instance.collection('orders');

    // الفلترة حسب المندوب
    if (_selectedRepCode != null) {
      query = query.where('buyer.repCode', isEqualTo: _selectedRepCode);
    } else {
      query = query.where('buyer.repCode', whereIn: _baseRepCodes);
    }

    // 🔥 الترتيب من السيرفر مباشرة (أسرع وأخف للتلفون)
    query = query.orderBy('orderDate', descending: true);

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          // في حال ظهور خطأ الفهرس (Index) سيظهر هنا
          return Center(child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Text("يرجى إنشاء الفهرس المطلوب في Firebase Console\n\nالخطأ: ${snapshot.error}", textAlign: TextAlign.center),
          ));
        }
        
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        var orders = snapshot.data!.docs;
        if (orders.isEmpty) return _emptyState("لا توجد طلبات حالياً");

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
        leading: const CircleAvatar(backgroundColor: Color(0xFFF1F2F6), child: Icon(Icons.receipt, color: Color(0xFF1ABC9C))),
        title: Text(buyer?['name'] ?? 'بدون اسم', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Text("الإجمالي: ${order['total']} ج.م", style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _infoRow(Icons.numbers, "رقم الطلب", id),
                _infoRow(Icons.calendar_month, "التاريخ", _formatDate(order['orderDate'])),
                _infoRow(Icons.person, "المندوب", buyer?['repName'] ?? '-'),
                const Divider(),
                const Text("الأصناف المطلوبة:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                ...((order['items'] as List? ?? []).map((item) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(item['name'] ?? 'منتج غير معروف', style: const TextStyle(fontSize: 12)),
                  trailing: Text("الكمية: ${item['quantity']}", style: const TextStyle(fontWeight: FontWeight.bold)),
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
        Icon(icon, size: 14, color: Colors.grey), 
        const SizedBox(width: 8), 
        Text("$label: ", style: const TextStyle(color: Colors.grey, fontSize: 11)),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600))),
      ]),
    );
  }

  Widget _emptyState(String msg) {
    return Center(child: Text(msg, style: const TextStyle(color: Colors.grey)));
  }

  String _formatDate(dynamic ts) {
    if (ts == null) return "-";
    if (ts is Timestamp) {
      return DateFormat('yyyy-MM-dd HH:mm').format(ts.toDate());
    }
    return ts.toString();
  }
}

