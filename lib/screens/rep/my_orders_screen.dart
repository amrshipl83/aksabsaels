import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:intl/intl.dart' as intl;
import 'package:url_launcher/url_launcher.dart';

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
  DocumentSnapshot? _lastDocument;
  
  List<Map<String, dynamic>> _allOrders = [];
  Map<String, dynamic>? _userData;
  String? _indexErrorUrl;

  final TextEditingController _searchController = TextEditingController();
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

      Query query = _db.collection("orders")
          .where("buyer.repCode", isEqualTo: repCode)
          .orderBy("orderDate", descending: true);

      if (_selectedStatus.isNotEmpty) {
        query = query.where("status", isEqualTo: _selectedStatus);
      }

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
          title: const Text("مبيعاتي (المندوب)", style: TextStyle(fontWeight: FontWeight.bold)),
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
          const Text("يجب تفعيل 'الفهرسة' لتشغيل الفلاتر المتقدمة", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          TextButton.icon(
            onPressed: () => launchUrl(Uri.parse(_indexErrorUrl!)),
            icon: const Icon(Icons.settings_input_component),
            label: const Text("تفعيل الإندكس الآن"),
          )
        ],
      ),
    );
  }

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
                _loadOrders(isRefresh: true);
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

  Widget _buildLoadMoreButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: _isMoreLoading
          ? const Center(child: CircularProgressIndicator())
          : ElevatedButton(
              onPressed: () => _loadOrders(),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black87),
              child: const Text("عرض المزيد"),
            ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    bool isDelivered = order['status'] == 'delivered';
    Color statusColor = isDelivered ? Colors.green : (order['status'] == 'cancelled' ? Colors.red : Colors.orange);
    String dateStr = order['orderDate'] != null
        ? intl.DateFormat('yyyy-MM-dd').format((order['orderDate'] as Timestamp).toDate())
        : "غير متوفر";

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
            Text("التاريخ: $dateStr"),
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
                  Text("تفاصيل الطلب: ${order['id']}", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF43B97F))),
                  const Divider(),
                  _detailRow("العميل", order['buyer']?['name']),
                  _detailRow("الهاتف", order['buyer']?['phone']),
                  _detailRow("العنوان", order['buyer']?['address']),
                  _detailRow("الحالة", _statusMap[order['status']] ?? order['status']),
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
                        Expanded(child: Text("${item['name']}")),
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

