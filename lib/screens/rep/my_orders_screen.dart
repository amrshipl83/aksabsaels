import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:intl/intl.dart' as intl;

class MyOrdersScreen extends StatefulWidget {
  const MyOrdersScreen({super.key});

  @override
  State<MyOrdersScreen> createState() => _MyOrdersScreenState();
}

class _MyOrdersScreenState extends State<MyOrdersScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  bool _isLoading = true;
  List<Map<String, dynamic>> _allOrders = [];
  List<Map<String, dynamic>> _filteredOrders = [];
  Map<String, dynamic>? _userData;

  // فلاتر البحث
  final TextEditingController _searchController = TextEditingController();
  DateTime? _startDate;
  DateTime? _endDate;
  String _selectedStatus = "";

  final Map<String, String> _statusMap = {
    "": "كل الحالات",
    "new-order": "قيد الانتظار",
    "processing": "قيد المعالجة",
    "shipped": "تم الشحن",
    "delivered": "تم التوصيل",
    "cancelled": "ملغاة",
  };

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  Future<void> _loadOrders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataString = prefs.getString('userData');
      if (userDataString == null) return;
      _userData = jsonDecode(userDataString);
      
      final String repCode = _userData!['repCode'];

      // جلب الطلبات المرتبطة بكود المندوب
      final querySnapshot = await _db
          .collection("orders")
          .where("buyer.repCode", isEqualTo: repCode)
          .get();

      final List<Map<String, dynamic>> fetched = [];
      for (var doc in querySnapshot.docs) {
        var data = doc.data();
        data['id'] = doc.id;
        fetched.add(data);
      }

      // ترتيب تنازلي حسب التاريخ
      fetched.sort((a, b) {
        DateTime dateA = (a['orderDate'] as Timestamp?)?.toDate() ?? DateTime(2000);
        DateTime dateB = (b['orderDate'] as Timestamp?)?.toDate() ?? DateTime(2000);
        return dateB.compareTo(dateA);
      });

      setState(() {
        _allOrders = fetched;
        _filteredOrders = fetched;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Error loading orders: $e");
      setState(() => _isLoading = false);
    }
  }

  void _applyFilters() {
    setState(() {
      _filteredOrders = _allOrders.where((order) {
        final orderId = order['id'].toString().toLowerCase();
        final clientName = (order['buyer']?['name'] ?? '').toString().toLowerCase();
        final searchText = _searchController.text.toLowerCase();

        bool matchesSearch = orderId.contains(searchText) || clientName.contains(searchText);
        
        bool matchesStatus = _selectedStatus == "" || 
            (order['status']?.toString().toLowerCase() == _selectedStatus.toLowerCase());

        bool matchesDate = true;
        if (order['orderDate'] != null) {
          DateTime orderDate = (order['orderDate'] as Timestamp).toDate();
          if (_startDate != null && orderDate.isBefore(_startDate!)) matchesDate = false;
          if (_endDate != null && orderDate.isAfter(_endDate!.add(const Duration(days: 1)))) matchesDate = false;
        }

        return matchesSearch && matchesStatus && matchesDate;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("طلباتي", style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFF43B97F),
          foregroundColor: Colors.white,
          centerTitle: true,
        ),
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFF5F7FA), Color(0xFFC3CFE2)],
            ),
          ),
          child: Column(
            children: [
              _buildFilterSection(),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: Color(0xFF43B97F)))
                    : _filteredOrders.isEmpty
                        ? const Center(child: Text("لا توجد طلبات مطابقة للبحث"))
                        : ListView.builder(
                            padding: const EdgeInsets.all(10),
                            itemCount: _filteredOrders.length,
                            itemBuilder: (context, index) {
                              return _buildOrderCard(_filteredOrders[index]);
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
      ),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            onChanged: (value) => _applyFilters(),
            decoration: InputDecoration(
              hintText: "بحث برقم الطلب أو اسم العميل...",
              prefixIcon: const Icon(Icons.search, color: Color(0xFF43B97F)),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _selectedStatus,
                  items: _statusMap.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 12)))).toList(),
                  onChanged: (val) {
                    setState(() => _selectedStatus = val!);
                    _applyFilters();
                  },
                  decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 10), border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () async {
                  DateTimeRange? picked = await showDateRangePicker(context: context, firstDate: DateTime(2022), lastDate: DateTime.now());
                  if (picked != null) {
                    setState(() {
                      _startDate = picked.start;
                      _endDate = picked.end;
                    });
                    _applyFilters();
                  }
                },
                icon: const Icon(Icons.date_range, color: Color(0xFF43B97F)),
              ),
              IconButton(
                onPressed: () {
                  _searchController.clear();
                  setState(() { _startDate = null; _endDate = null; _selectedStatus = ""; });
                  _applyFilters();
                },
                icon: const Icon(Icons.refresh, color: Colors.redAccent),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    String dateStr = order['orderDate'] != null 
        ? intl.DateFormat('yyyy-MM-dd').format((order['orderDate'] as Timestamp).toDate())
        : "غير متوفر";
    
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        onTap: () => _showOrderDetails(order),
        title: Text("طلب رقم: ${order['id']}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("العميل: ${order['buyer']?['name'] ?? 'غير معروف'}"),
            Text("التاريخ: $dateStr | الحالة: ${_statusMap[order['status']] ?? order['status']}"),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text("${order['total']} ج.م", style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF43B97F))),
            const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  void _showOrderDetails(Map<String, dynamic> order) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          maxChildSize: 0.9,
          expand: false,
          builder: (_, controller) {
            return Directionality(
              textDirection: TextDirection.rtl,
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.all(20),
                children: [
                  Center(child: Container(width: 50, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)))),
                  const SizedBox(height: 20),
                  Text("تفاصيل الطلب: ${order['id']}", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF43B97F))),
                  const Divider(),
                  _detailRow("العميل", order['buyer']?['name']),
                  _detailRow("الهاتف", order['buyer']?['phone']),
                  _detailRow("العنوان", order['buyer']?['address']),
                  _detailRow("حالة الطلب", _statusMap[order['status']] ?? order['status']),
                  _detailRow("طريقة الدفع", order['paymentMethod']),
                  _detailRow("الإجمالي", "${order['total']} ج.م"),
                  const SizedBox(height: 20),
                  const Text("المنتجات:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 10),
                  ...(order['items'] as List? ?? []).map((item) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("${item['name']}"),
                        Text("الكمية: ${item['quantity']} | ${item['price']} ج.م"),
                      ],
                    ),
                  )).toList(),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _detailRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Text("$label: ", style: const TextStyle(fontWeight: FontWeight.bold)),
          Expanded(child: Text("${value ?? 'غير متوفر'}")),
        ],
      ),
    );
  }
}

