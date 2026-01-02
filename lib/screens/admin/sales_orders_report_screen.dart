import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

class SalesOrdersReportScreen extends StatefulWidget {
  const SalesOrdersReportScreen({super.key});

  @override
  State<SalesOrdersReportScreen> createState() => _SalesOrdersReportScreenState();
}

class _SalesOrdersReportScreenState extends State<SalesOrdersReportScreen> {
  Map<String, dynamic>? _userData;
  bool _isLoading = true;
  
  // بيانات الهيكل التنظيمي
  List<Map<String, dynamic>> _allReps = []; 
  List<String> _baseRepCodes = []; 
  
  // قيم الفلاتر
  String? _selectedRepCode;
  DateTimeRange? _selectedDateRange;
  String _activeFilterLabel = "كل التواريخ";

  // تخزين البيانات الحالية للتصدير
  List<DocumentSnapshot> _currentOrders = [];

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

  Future<void> _pickDateRange() async {
    DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) {
      setState(() {
        _selectedDateRange = picked;
        _activeFilterLabel = "${DateFormat('yyyy-MM-dd').format(picked.start)} إلى ${DateFormat('yyyy-MM-dd').format(picked.end)}";
      });
    }
  }

  void _exportToExcel() {
    if (_currentOrders.isEmpty) return;

    String csvData = "رقم الطلب,التاريخ,العميل,المندوب,الإجمالي\n";
    for (var doc in _currentOrders) {
      var d = doc.data() as Map<String, dynamic>;
      var buyer = d['buyer'] as Map<String, dynamic>?;
      csvData += "${doc.id},${_formatDate(d['orderDate'])},${buyer?['name'] ?? 'بدون اسم'},${buyer?['repName'] ?? '-'},${d['total']}\n";
    }

    Share.share(csvData, subject: 'تقرير مبيعات ${_activeFilterLabel}');
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
        actions: [
          IconButton(
            icon: const Icon(Icons.share, color: Colors.green),
            onPressed: _exportToExcel,
          )
        ],
      ),
      body: Column(
        children: [
          _buildFilterBar(),
          Expanded(
            child: _baseRepCodes.isEmpty ? _emptyState() : _buildOrdersStream(),
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
            _filterChip(
              label: _selectedRepCode == null ? "كل المناديب" : _allReps.firstWhere((r) => r['repCode'] == _selectedRepCode)['repName'],
              icon: Icons.person,
              onTap: _showRepSelector,
              active: _selectedRepCode != null,
            ),
            const SizedBox(width: 10),
            _filterChip(
              label: _selectedDateRange == null ? "كل التواريخ" : _activeFilterLabel,
              icon: Icons.calendar_today,
              onTap: _pickDateRange,
              active: _selectedDateRange != null,
            ),
            if (_selectedRepCode != null || _selectedDateRange != null)
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.red),
                onPressed: () => setState(() { _selectedRepCode = null; _selectedDateRange = null; }),
              )
          ],
        ),
      ),
    );
  }

  Widget _filterChip({required String label, required IconData icon, required VoidCallback onTap, bool active = false}) {
    return ActionChip(
      avatar: Icon(icon, size: 16, color: active ? Colors.white : Colors.grey),
      label: Text(label, style: TextStyle(color: active ? Colors.white : Colors.black87, fontSize: 12)),
      backgroundColor: active ? const Color(0xFF1ABC9C) : Colors.grey[200],
      onPressed: onTap,
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
          return ListTile(
            title: Text(rep['repName']),
            onTap: () { setState(() => _selectedRepCode = rep['repCode']); Navigator.pop(context); },
          );
        },
      ),
    );
  }

  Widget _buildOrdersStream() {
    Query query = FirebaseFirestore.instance.collection('orders');

    if (_selectedRepCode != null) {
      query = query.where('buyer.repCode', isEqualTo: _selectedRepCode);
    } else {
      query = query.where('buyer.repCode', whereIn: _baseRepCodes);
    }

    if (_selectedDateRange != null) {
      query = query.where('orderDate', isGreaterThanOrEqualTo: _selectedDateRange!.start);
      query = query.where('orderDate', isLessThanOrEqualTo: _selectedDateRange!.end.add(const Duration(days: 1)));
    }

    return StreamBuilder<QuerySnapshot>(
      stream: query.orderBy('orderDate', descending: true).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text("خطأ: ${snapshot.error}"));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        _currentOrders = snapshot.data!.docs;
        if (_currentOrders.isEmpty) return _emptyState();

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: _currentOrders.length,
          itemBuilder: (context, index) {
            var data = _currentOrders[index].data() as Map<String, dynamic>;
            return _orderCard(data, _currentOrders[index].id);
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
        leading: const CircleAvatar(
          backgroundColor: Color(0xFFF1F2F6),
          child: Icon(Icons.receipt_long, color: Color(0xFF1ABC9C), size: 20),
        ),
        title: Text(buyer?['name'] ?? 'بدون اسم', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Text("القيمة: ${order['total']} ج.م", style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _infoRow(Icons.numbers, "الرقم", id),
                _infoRow(Icons.calendar_month, "التاريخ", _formatDate(order['orderDate'])),
                _infoRow(Icons.person, "المندوب", buyer?['repName'] ?? '-'),
                const Divider(),
                ...((order['items'] as List? ?? []).map((item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(item['productName'] ?? '', style: const TextStyle(fontSize: 12)),
                      Text("x${item['quantity']}", style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
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
      child: Row(
        children: [
          Icon(icon, size: 14, color: Colors.grey),
          const SizedBox(width: 8),
          Text("$label: ", style: const TextStyle(color: Colors.grey, fontSize: 11)),
          Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.search_off, size: 50, color: Colors.grey),
          SizedBox(height: 10),
          Text("لا توجد نتائج بحث", style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  String _formatDate(dynamic ts) {
    if (ts == null) return "-";
    DateTime dt = (ts is Timestamp) ? ts.toDate() : DateTime.parse(ts.toString());
    return DateFormat('yyyy-MM-dd').format(dt);
  }
}

