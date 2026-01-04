import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:intl/intl.dart' as intl;

class MyCustomersScreen extends StatefulWidget {
  const MyCustomersScreen({super.key});

  @override
  State<MyCustomersScreen> createState() => _MyCustomersScreenState();
}

class _MyCustomersScreenState extends State<MyCustomersScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  bool _isLoading = true;
  List<Map<String, dynamic>> _allCustomers = [];
  List<Map<String, dynamic>> _filteredCustomers = [];
  Map<String, dynamic>? _userData;

  // فلاتر البحث
  final TextEditingController _searchController = TextEditingController();
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  Future<void> _loadCustomers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataString = prefs.getString('userData');
      if (userDataString == null) return;
      _userData = jsonDecode(userDataString);
      
      final String repCode = _userData!['repCode'];

      // جلب العملاء المرتبطين بهذا المندوب من مجموعة users
      final querySnapshot = await _db
          .collection("users")
          .where("repCode", isEqualTo: repCode)
          .get();

      final List<Map<String, dynamic>> fetched = [];
      for (var doc in querySnapshot.docs) {
        var data = doc.data();
        data['id'] = doc.id;
        fetched.add(data);
      }

      setState(() {
        _allCustomers = fetched;
        _filteredCustomers = fetched;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Error loading customers: $e");
      setState(() => _isLoading = false);
    }
  }

  void _applyFilters() {
    setState(() {
      _filteredCustomers = _allCustomers.where((customer) {
        final name = (customer['fullname'] ?? '').toString().toLowerCase();
        final phone = (customer['phone'] ?? '').toString().toLowerCase();
        final address = (customer['address'] ?? '').toString().toLowerCase();
        final searchText = _searchController.text.toLowerCase();

        bool matchesSearch = name.contains(searchText) ||
            phone.contains(searchText) ||
            address.contains(searchText);

        bool matchesDate = true;
        if (customer['createdAt'] != null) {
          DateTime regDate = (customer['createdAt'] as Timestamp).toDate();
          if (_startDate != null && regDate.isBefore(_startDate!)) matchesDate = false;
          if (_endDate != null && regDate.isAfter(_endDate!.add(const Duration(days: 1)))) matchesDate = false;
        }

        return matchesSearch && matchesDate;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("عملائي", style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFF43B97F), // لون HTML الأساسي
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
                    : _filteredCustomers.isEmpty
                        ? const Center(child: Text("لا يوجد عملاء مطابقين للبحث"))
                        : ListView.builder(
                            padding: const EdgeInsets.all(10),
                            itemCount: _filteredCustomers.length,
                            itemBuilder: (context, index) {
                              return _buildCustomerCard(_filteredCustomers[index]);
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
      padding: const EdgeInsets.all(15),
      margin: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10)],
      ),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            onChanged: (value) => _applyFilters(),
            decoration: InputDecoration(
              hintText: "بحث بالاسم، الهاتف، أو العنوان...",
              prefixIcon: const Icon(Icons.search, color: Color(0xFF43B97F)),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    DateTime? picked = await showDatePicker(
                        context: context, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime.now());
                    if (picked != null) {
                      setState(() => _startDate = picked);
                      _applyFilters();
                    }
                  },
                  icon: const Icon(Icons.date_range, size: 18),
                  label: Text(_startDate == null ? "من تاريخ" : intl.DateFormat('yyyy-MM-dd').format(_startDate!)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    DateTime? picked = await showDatePicker(
                        context: context, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime.now());
                    if (picked != null) {
                      setState(() => _endDate = picked);
                      _applyFilters();
                    }
                  },
                  icon: const Icon(Icons.date_range, size: 18),
                  label: Text(_endDate == null ? "إلى تاريخ" : intl.DateFormat('yyyy-MM-dd').format(_endDate!)),
                ),
              ),
              IconButton(
                onPressed: () {
                  _searchController.clear();
                  setState(() {
                    _startDate = null;
                    _endDate = null;
                  });
                  _applyFilters();
                },
                icon: const Icon(Icons.refresh, color: Colors.redAccent),
              )
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerCard(Map<String, dynamic> customer) {
    String regDate = "غير متوفر";
    if (customer['createdAt'] != null) {
      regDate = intl.DateFormat('yyyy-MM-dd HH:mm').format((customer['createdAt'] as Timestamp).toDate());
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 3,
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: const Color(0xFF43B97F).withOpacity(0.1),
          child: const Icon(Icons.person, color: Color(0xFF43B97F)),
        ),
        title: Text(customer['fullname'] ?? 'بدون اسم', style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(customer['phone'] ?? 'لا يوجد هاتف'),
        children: [
          Padding(
            padding: const EdgeInsets.all(15),
            child: Column(
              children: [
                _buildInfoRow(Icons.location_on_outlined, "العنوان", customer['address'] ?? 'غير محدد'),
                _buildInfoRow(Icons.calendar_today_outlined, "تاريخ التسجيل", regDate),
                _buildInfoRow(Icons.map_outlined, "الموقع", _formatLocation(customer['location'])),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          Text("$label: ", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  String _formatLocation(dynamic loc) {
    if (loc == null) return "غير محدد";
    try {
      return "${loc['lat'].toStringAsFixed(4)}, ${loc['lng'].toStringAsFixed(4)}";
    } catch (e) {
      return "بيانات موقع غير صالحة";
    }
  }
}

