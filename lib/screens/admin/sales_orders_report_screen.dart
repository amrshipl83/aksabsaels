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
  String _statusFilter = 'الكل';

  DateTime _startDate = DateTime.now().subtract(const Duration(days: 7));
  DateTime _endDate = DateTime.now();

  final Color kPrimaryColor = const Color(0xFF1ABC9C);
  final Color kSidebarColor = const Color(0xFF2F3542);

  // تحديث الألوان لتشمل الحالات الجديدة
  final Map<String, Color> statusColors = {
    'delivered': const Color(0xFF2ECC71),    // تم التسليم
    'processing': const Color(0xFFF1C40F),   // قيد التجهيز
    'cancelled': const Color(0xFFE74C3C),    // ملغى
    'new-order': const Color(0xFF3498DB),     // طلب جديد
    'shipped': const Color(0xFF9B59B6),       // تم الشحن
    'الكل': const Color(0xFF34495E),
  };

  // خريطة لترجمة الأكواد لأسماء عربية
  final Map<String, String> statusNames = {
    'new-order': 'طلب جديد',
    'processing': 'قيد التجهيز',
    'shipped': 'تم الشحن',
    'delivered': 'تم التسليم',
    'cancelled': 'ملغى',
    'الكل': 'الكل',
  };

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
        var supervisors = await FirebaseFirestore.instance.collection('managers').where('managerId', isEqualTo: myDocId).get();
        List<String> supervisorIds = supervisors.docs.map((d) => d.id).toList();
        if (supervisorIds.isNotEmpty) {
          var reps = await FirebaseFirestore.instance.collection('salesRep').where('supervisorId', whereIn: supervisorIds).get();
          repsData = reps.docs.map((d) => {'repCode': d['repCode'].toString(), 'repName': d['fullname']}).toList();
        }
      } else if (role == 'sales_supervisor') {
        var reps = await FirebaseFirestore.instance.collection('salesRep').where('supervisorId', isEqualTo: myDocId).get();
        repsData = reps.docs.map((d) => {'repCode': d['repCode'].toString(), 'repName': d['fullname']}).toList();
      }
      if (mounted) {
        setState(() {
          _allReps = repsData;
          _baseRepCodes = repsData.map((e) => e['repCode'] as String).where((c) => c.isNotEmpty).toList();
        });
      }
    } catch (e) { debugPrint("Hierarchy Error: $e"); }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      appBar: AppBar(
        title: Text("تقارير العمليات", style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w900)),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: kSidebarColor,
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildFilterPanel(),
            _buildStatusQuickFilter(),
            Expanded(
              child: _baseRepCodes.isEmpty 
                ? _emptyState("لا يوجد مناديب مسجلين لإظهار تقاريرهم") 
                : _buildOrdersStream(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterPanel() {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 5.w, vertical: 1.h),
      padding: EdgeInsets.all(4.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 15, offset: const Offset(0, 5))],
      ),
      child: Column(
        children: [
          Row(
            children: [
              _datePickerBtn("من تاريخ", _startDate, (d) => setState(() => _startDate = d!)),
              SizedBox(width: 4.w),
              _datePickerBtn("إلى تاريخ", _endDate, (d) => setState(() => _endDate = d!)),
            ],
          ),
          SizedBox(height: 1.5.h),
          InkWell(
            onTap: _showRepSelector,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 1.5.h),
              decoration: BoxDecoration(color: const Color(0xFFF1F2F6), borderRadius: BorderRadius.circular(15)),
              child: Row(
                children: [
                  Icon(Icons.person_pin_outlined, color: kPrimaryColor, size: 22.sp),
                  SizedBox(width: 3.w),
                  Expanded(
                    child: Text(
                      _selectedRepCode == null ? "كل المناديب المختصين" : _allReps.firstWhere((r) => r['repCode'] == _selectedRepCode)['repName'],
                      style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(Icons.arrow_drop_down_circle_outlined, color: kSidebarColor, size: 18.sp),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusQuickFilter() {
    List<String> statuses = ['الكل', 'new-order', 'processing', 'shipped', 'delivered', 'cancelled'];
    return Container(
      height: 7.h,
      margin: EdgeInsets.symmetric(vertical: 0.5.h),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: 5.w),
        itemCount: statuses.length,
        itemBuilder: (context, index) {
          String status = statuses[index];
          bool isSelected = _statusFilter == status;
          return Padding(
            padding: EdgeInsets.only(left: 3.w),
            child: ChoiceChip(
              padding: EdgeInsets.symmetric(horizontal: 2.w),
              label: Text(statusNames[status]!, style: TextStyle(color: isSelected ? Colors.white : kSidebarColor, fontWeight: FontWeight.bold, fontSize: 13.sp)),
              selected: isSelected,
              selectedColor: statusColors[status],
              backgroundColor: Colors.white,
              onSelected: (val) => setState(() => _statusFilter = status),
            ),
          );
        },
      ),
    );
  }

  Widget _buildOrdersStream() {
    Query query = FirebaseFirestore.instance.collection('orders');
    query = query
        .where('orderDate', isGreaterThanOrEqualTo: Timestamp.fromDate(DateTime(_startDate.year, _startDate.month, _startDate.day)))
        .where('orderDate', isLessThanOrEqualTo: Timestamp.fromDate(DateTime(_endDate.year, _endDate.month, _endDate.day, 23, 59, 59)));

    if (_selectedRepCode != null) {
      query = query.where('buyer.repCode', isEqualTo: _selectedRepCode);
    } else {
      query = query.where('buyer.repCode', whereIn: _baseRepCodes);
    }

    if (_statusFilter != 'الكل') {
      query = query.where('status', isEqualTo: _statusFilter);
    }

    query = query.orderBy('orderDate', descending: true).limit(60);

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return _emptyState("خطأ في تحميل البيانات");
        
        var orders = snapshot.data?.docs ?? [];
        if (orders.isEmpty) return _emptyState("لم يتم العثور على طلبات مطابقة");

        return ListView.builder(
          padding: EdgeInsets.fromLTRB(5.w, 0, 5.w, 2.h),
          itemCount: orders.length,
          itemBuilder: (context, index) {
            var data = orders[index].data() as Map<String, dynamic>;
            return _orderCard(data);
          },
        );
      },
    );
  }

  Widget _orderCard(Map<String, dynamic> order) {
    var buyer = order['buyer'] as Map<String, dynamic>?;
    String sellerName = order['sellerName'] ?? "مورد غير محدد";
    String status = order['status'] ?? 'processing';
    Color sColor = statusColors[status] ?? kSidebarColor;

    return Container(
      margin: EdgeInsets.only(bottom: 2.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 5))],
      ),
      child: ExpansionTile(
        tilePadding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 0.5.h),
        leading: Container(
          padding: EdgeInsets.all(2.w),
          decoration: BoxDecoration(color: sColor.withOpacity(0.1), shape: BoxShape.circle),
          child: Icon(Icons.shopping_cart_checkout_rounded, color: sColor, size: 22.sp),
        ),
        title: Row(
          children: [
            Expanded(child: Text(buyer?['name'] ?? 'عميل مجهول', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16.sp, color: kSidebarColor))),
            _badge(statusNames[status] ?? status, sColor),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 0.5.h),
            Row(
              children: [
                Icon(Icons.badge_outlined, size: 12.sp, color: kPrimaryColor),
                SizedBox(width: 1.w),
                Text("المندوب: ${buyer?['repName'] ?? buyer?['repCode']}", style: TextStyle(fontSize: 13.sp, color: Colors.blueGrey, fontWeight: FontWeight.w600)),
              ],
            ),
            Text("${order['total']} ج.م", style: TextStyle(color: kPrimaryColor, fontWeight: FontWeight.w900, fontSize: 16.sp)),
          ],
        ),
        children: [
          Container(
            padding: EdgeInsets.all(5.w),
            decoration: BoxDecoration(color: const Color(0xFFF8F9FD), borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _detailRow(Icons.warehouse_rounded, "المورد الأصلي", sellerName),
                _detailRow(Icons.calendar_today_rounded, "تاريخ العملية", _formatDate(order['orderDate'])),
                const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider()),
                Text("قائمة الأصناف:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.sp, color: kSidebarColor)),
                SizedBox(height: 1.h),
                ...(order['items'] as List? ?? []).map((item) => Padding(
                  padding: EdgeInsets.symmetric(vertical: 0.5.h),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          _badge("${item['quantity']}x", kPrimaryColor),
                          SizedBox(width: 3.w),
                          Text(item['name'] ?? 'منتج', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w500)),
                        ],
                      ),
                      Text("${(item['price'] * item['quantity']).toStringAsFixed(2)} ج.م", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.sp)),
                    ],
                  ),
                )),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 2.5.w, vertical: 0.4.h),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withOpacity(0.2))),
      child: Text(text, style: TextStyle(color: color, fontSize: 9.sp, fontWeight: FontWeight.bold)),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 0.5.h),
      child: Row(
        children: [
          Icon(icon, size: 14.sp, color: Colors.blueGrey),
          SizedBox(width: 3.w),
          Text("$label: ", style: TextStyle(color: Colors.grey, fontSize: 13.sp)),
          Expanded(child: Text(value, style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.bold, color: kSidebarColor))),
        ],
      ),
    );
  }

  Widget _datePickerBtn(String label, DateTime date, Function(DateTime?) onSelect) {
    return Expanded(
      child: InkWell(
        onTap: () async {
          final picked = await showDatePicker(context: context, initialDate: date, firstDate: DateTime(2025), lastDate: DateTime.now());
          if (picked != null) onSelect(picked);
        },
        child: Container(
          padding: EdgeInsets.all(3.w),
          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(12)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 10.sp, color: Colors.grey)),
              // تكبير الخط هنا كما طلبت
              Text(DateFormat('yyyy-MM-dd').format(date), style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold, color: kSidebarColor)),
            ],
          ),
        ),
      ),
    );
  }

  void _showRepSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => Padding(
        padding: EdgeInsets.all(5.w),
        child: Column(
          children: [
            Container(width: 10.w, height: 5, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10))),
            SizedBox(height: 2.h),
            Text("اختر المندوب", style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold)),
            const Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: _allReps.length + 1,
                itemBuilder: (context, i) {
                  if (i == 0) return ListTile(
                    leading: const Icon(Icons.groups_rounded),
                    title: Text("تحليل أداء كل المناديب", style: TextStyle(fontSize: 15.sp)), 
                    onTap: () { setState(() => _selectedRepCode = null); Navigator.pop(context); }
                  );
                  var rep = _allReps[i - 1];
                  return ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: Text(rep['repName'], style: TextStyle(fontSize: 15.sp)), 
                    onTap: () { setState(() => _selectedRepCode = rep['repCode']); Navigator.pop(context); }
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(String msg) => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.search_off_rounded, size: 50.sp, color: Colors.grey.shade300), SizedBox(height: 2.h), Text(msg, style: TextStyle(color: Colors.grey, fontSize: 14.sp), textAlign: TextAlign.center)]));

  String _formatDate(dynamic ts) => ts is Timestamp ? DateFormat('yyyy-MM-dd HH:mm').format(ts.toDate()) : ts.toString();
}

