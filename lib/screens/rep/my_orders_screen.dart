import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:intl/intl.dart' as intl;
import 'package:url_launcher/url_launcher.dart'; // تأكد من إضافة url_launcher في pubspec.yaml

class MyOrdersScreen extends StatefulWidget {
  const MyOrdersScreen({super.key});

  @override
  State<MyOrdersScreen> createState() => _MyOrdersScreenState();
}

class _MyOrdersScreenState extends State<MyOrdersScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  bool _isLoading = true;
  bool _isMoreLoading = false;
  bool _hasMore = true;
  DocumentSnapshot? _lastDocument; // لتخزين آخر وثيقة للتحميل التالي
  
  List<Map<String, dynamic>> _allOrders = [];
  Map<String, dynamic>? _userData;
  String? _indexErrorUrl; // لتخزين رابط الإندكس لو وجد

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
    _loadOrders(isRefresh: true);
  }

  // دالة جلب البيانات الذكية
  Future<void> _loadOrders({bool isRefresh = false}) async {
    if (isRefresh) {
      setState(() {
        _isLoading = true;
        _allOrders = [];
        _lastDocument = null;
        _hasMore = true;
        _indexErrorUrl = null;
      });
    } else {
      setState(() => _isMoreLoading = true);
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataString = prefs.getString('userData');
      if (userDataString == null) return;
      _userData = jsonDecode(userDataString);
      final String repCode = _userData!['repCode'];

      // بناء الاستعلام
      Query query = _db.collection("orders")
          .where("buyer.repCode", isEqualTo: repCode)
          .orderBy("orderDate", descending: true);

      // تطبيق فلترة الحالة مباشرة في الـ Query لو مختارة
      if (_selectedStatus.isNotEmpty) {
        query = query.where("status", isEqualTo: _selectedStatus);
      }

      // Pagination
      if (_lastDocument != null) {
        query = query.startAfterDocument(_lastDocument!);
      }

      final querySnapshot = await query.limit(20).get();

      if (querySnapshot.docs.length < 20) {
        _hasMore = false;
      }

      if (querySnapshot.docs.isNotEmpty) {
        _lastDocument = querySnapshot.docs.last;
        final List<Map<String, dynamic>> fetched = querySnapshot.docs.map((doc) {
          var data = doc.data() as Map<String, dynamic>;
          data['id'] = doc.id;
          return data;
        }).toList();

        setState(() {
          _allOrders.addAll(fetched);
          _isLoading = false;
          _isMoreLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
          _isMoreLoading = false;
          _hasMore = false;
        });
      }
    } catch (e) {
      _handleError(e);
    }
  }

  void _handleError(dynamic e) {
    String errorMsg = e.toString();
    if (errorMsg.contains("FAILED_PRECONDITION") || errorMsg.contains("index")) {
      // استخراج الرابط من الخطأ
      RegExp regExp = RegExp(r'https://console\.firebase\.google\.com[^\s]+');
      _indexErrorUrl = regExp.stringMatch(errorMsg);
    }
    debugPrint("Order Loading Error: $e");
    setState(() {
      _isLoading = false;
      _isMoreLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("مبيعاتي", style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFF43B97F),
          foregroundColor: Colors.white,
          centerTitle: true,
        ),
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFF5F7FA), Color(0xFFE4E7EB)],
            ),
          ),
          child: Column(
            children: [
              _buildFilterSection(),
              if (_indexErrorUrl != null) _buildIndexWarning(),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: Color(0xFF43B97F)))
                    : _allOrders.isEmpty
                        ? const Center(child: Text("لا توجد طلبات حالياً"))
                        : RefreshIndicator(
                            onRefresh: () => _loadOrders(isRefresh: true),
                            child: ListView.builder(
                              padding: const EdgeInsets.all(10),
                              itemCount: _allOrders.length + (_hasMore ? 1 : 0),
                              itemBuilder: (context, index) {
                                if (index == _allOrders.length) {
                                  return _buildLoadMoreButton();
                                }
                                return _buildOrderCard(_allOrders[index]);
                              },
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIndexWarning() {
    return Container(
      margin: const EdgeInsets.all(10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.orange.withOpacity(0.2), borderRadius: BorderRadius.circular(10)),
      child: Column(
        children: [
          const Text("يجب تفعيل 'الفهرسة' في فايربيز لتشغيل الفلاتر المتقدمة", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          TextButton.icon(
            onPressed: () => launchUrl(Uri.parse(_indexErrorUrl!)),
            icon: const Icon(Icons.settings_input_component),
            label: const Text("اضغط هنا لتفعيل الإندكس"),
          )
        ],
      ),
    );
  }

  Widget _buildLoadMoreButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: _isMoreLoading
          ? const Center(child: CircularProgressIndicator())
          : ElevatedButton(
              onPressed: () => _loadOrders(),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black87),
              child: const Text("عرض المزيد من الطلبات"),
            ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    bool isDelivered = order['status'] == 'delivered';
    Color statusColor = isDelivered ? Colors.green : (order['status'] == 'cancelled' ? Colors.red : Colors.orange);

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
          side: isDelivered ? const BorderSide(color: Color(0xFF43B97F), width: 1) : BorderSide.none
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        onTap: () => _showOrderDetails(order),
        leading: CircleAvatar(
          backgroundColor: statusColor.withOpacity(0.1),
          child: Icon(isDelivered ? Icons.check_circle : Icons.shopping_bag, color: statusColor),
        ),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text("طلب #${order['id'].toString().substring(0, 5)}", style: const TextStyle(fontWeight: FontWeight.bold)),
            Text("${order['total']} ج.م", style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF43B97F))),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 5),
            Text("العميل: ${order['buyer']?['name'] ?? 'غير معروف'}"),
            const SizedBox(height: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(5)),
              child: Text(_statusMap[order['status']] ?? order['status'], style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      ),
    );
  }

  // --- Filter Section ---
  Widget _buildFilterSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              value: _selectedStatus,
              items: _statusMap.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 13)))).toList(),
              onChanged: (val) {
                setState(() => _selectedStatus = val!);
                _loadOrders(isRefresh: true); // تحميل من جديد بفلترة السيرفر
              },
              decoration: const InputDecoration(labelText: "حالة الطلب", contentPadding: EdgeInsets.symmetric(horizontal: 10), border: OutlineInputBorder()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.blueGrey),
            onPressed: () => _loadOrders(isRefresh: true),
          )
        ],
      ),
    );
  }

  // (باقي دوال التفاصيل _showOrderDetails و _detailRow تبقى كما هي في الكود الأصلي)
  void _showOrderDetails(Map<String, dynamic> order) { /* ... نفس الكود السابق ... */ }
  Widget _detailRow(String label, dynamic value) { /* ... نفس الكود السابق ... */ }
}

