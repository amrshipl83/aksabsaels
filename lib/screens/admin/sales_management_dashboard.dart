import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:sizer/sizer.dart';

class SalesManagementDashboard extends StatefulWidget {
  const SalesManagementDashboard({super.key});

  @override
  State<SalesManagementDashboard> createState() => _SalesManagementDashboardState();
}

class _SalesManagementDashboardState extends State<SalesManagementDashboard> {
  Map<String, dynamic>? _userData;
  bool _isLoading = true;
  
  // الألوان الأساسية المأخوذة من الـ HTML الخاص بك
  final Color kPrimaryColor = const Color(0xFF1ABC9C);
  final Color kSidebarColor = const Color(0xFF2F3542);
  final Color kBgColor = const Color(0xFFF5F6FA);

  // متغيرات البيانات
  int totalOrders = 0;
  double totalSales = 0;
  int totalAgents = 0;
  double avgRating = 0;

  @override
  void initState() {
    super.initState();
    _initDashboard();
  }

  Future<void> _initDashboard() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('userData');
    if (data != null) {
      _userData = jsonDecode(data);
      await _loadStats();
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadStats() async {
    String role = _userData?['role'] ?? '';
    String managerDocId = _userData!['uid']; // Document ID للمدير/المشرف

    try {
      // 1. حساب عدد المندوبين
      Query agentsQuery = FirebaseFirestore.instance.collection('salesRep');
      if (role == 'sales_supervisor') {
        agentsQuery = agentsQuery.where('supervisorId', 'isEqualTo', managerDocId);
      }
      final agentsSnap = await agentsQuery.get();
      totalAgents = agentsSnap.size;

      // 2. جلب الطلبات وحساب الإجماليات
      Query ordersQuery = FirebaseFirestore.instance.collection('orders');
      if (role == 'sales_supervisor' && agentsSnap.docs.isNotEmpty) {
        List<String> repCodes = agentsSnap.docs.map((doc) => doc['repCode'] as String).toList();
        ordersQuery = ordersQuery.where('buyer.repCode', whereIn: repCodes);
      }

      final ordersSnap = await ordersQuery.get();
      double salesSum = 0;
      double ratingSum = 0;
      int ratedCount = 0;

      for (var doc in ordersSnap.docs) {
        var d = doc.data() as Map<String, dynamic>;
        salesSum += (d['total'] ?? 0).toDouble();
        if (d['rating'] != null) {
          ratingSum += (d['rating'] as num).toDouble();
          ratedCount++;
        }
      }

      if (mounted) {
        setState(() {
          totalOrders = ordersSnap.size;
          totalSales = salesSum;
          avgRating = ratedCount > 0 ? (ratingSum / ratedCount) : 0;
        });
      }
    } catch (e) {
      debugPrint("Error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: kBgColor,
        appBar: AppBar(
          title: Text(_userData?['role'] == 'sales_manager' ? 'لوحة المبيعات' : 'إدارة المشرف'),
          backgroundColor: Colors.white,
          foregroundColor: kSidebarColor,
          elevation: 0.5,
        ),
        drawer: _buildDrawer(),
        body: SingleChildScrollView(
          padding: EdgeInsets.all(16.dp),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildWelcomeSection(),
              SizedBox(height: 20.dp),
              
              // شبكة الإحصائيات (2 في كل صف - مثالية للموبايل)
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                crossAxisSpacing: 12.dp,
                mainAxisSpacing: 12.dp,
                childAspectRatio: 1.2,
                children: [
                  _buildStatCard("إجمالي الطلبات", "$totalOrders", Icons.shopping_basket, Colors.blue),
                  _buildStatCard("إجمالي المبيعات", "${totalSales.toInt()} ج.م", Icons.monetization_on, Colors.green),
                  _buildStatCard("عدد المندوبين", "$totalAgents", Icons.people, Colors.orange),
                  _buildStatCard("متوسط التقييم", avgRating.toStringAsFixed(1), Icons.star, Colors.amber),
                ],
              ),
              
              SizedBox(height: 25.dp),
              Text("الإجراءات السريعة", style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold)),
              SizedBox(height: 10.dp),
              
              // أزرار وصول سريع للتقارير
              _buildQuickAction(Icons.file_copy, "عرض تقارير اليوم", () {}),
              _buildQuickAction(Icons.map, "تتبع المندوبين لايف", () {}),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomeSection() {
    return Container(
      padding: EdgeInsets.all(15.dp),
      decoration: BoxDecoration(
        color: kSidebarColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          CircleAvatar(backgroundColor: kPrimaryColor, child: const Icon(Icons.admin_panel_settings, color: Colors.white)),
          SizedBox(width: 12.dp),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("مرحباً بك،", style: TextStyle(color: Colors.white70, fontSize: 10.sp)),
                Text("${_userData?['fullname']}", style: TextStyle(color: Colors.white, fontSize: 13.sp, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: EdgeInsets.all(12.dp),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5)],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 24.sp),
          SizedBox(height: 8.dp),
          Text(title, style: TextStyle(color: Colors.grey, fontSize: 9.sp), textAlign: TextAlign.center),
          Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.sp, color: kSidebarColor)),
        ],
      ),
    );
  }

  Widget _buildQuickAction(IconData icon, String title, VoidCallback onTap) {
    return Card(
      margin: EdgeInsets.only(bottom: 10.dp),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        leading: Icon(icon, color: kPrimaryColor),
        title: Text(title, style: TextStyle(fontSize: 11.sp)),
        trailing: const Icon(Icons.arrow_forward_ios, size: 14),
        onTap: onTap,
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      child: Container(
        color: kSidebarColor,
        child: SafeArea( // لضمان عدم نزول زر الخروج تحت أزرار الهاتف
          child: Column(
            children: [
              const SizedBox(height: 20),
              Text("أكسب - إدارة المبيعات", style: TextStyle(color: kPrimaryColor, fontSize: 15.sp, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              const Divider(color: Colors.white24),
              Expanded(
                child: ListView(
                  children: [
                    _drawerItem(Icons.bar_chart, "نظرة عامة", true),
                    _drawerItem(Icons.receipt_long, "تقارير الطلبات", false),
                    _drawerItem(Icons.people, "العملاء", false),
                    _drawerItem(Icons.manage_accounts, "المندوبين والمشرفين", false),
                    _drawerItem(Icons.pie_chart, "التقارير الشاملة", false),
                    _drawerItem(Icons.percent, "عروض الشهر", false),
                    _drawerItem(Icons.location_on, "تقارير الزيارات", false),
                    _drawerItem(Icons.sensors, "لايف", false, isLive: true),
                  ],
                ),
              ),
              _drawerItem(Icons.logout, "تسجيل الخروج", false, color: Colors.redAccent, onTap: () async {
                await FirebaseAuth.instance.signOut();
                (await SharedPreferences.getInstance()).clear();
                if (mounted) Navigator.of(context).pushReplacementNamed('/');
              }),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  Widget _drawerItem(IconData icon, String title, bool isSelected, {Color? color, bool isLive = false, VoidCallback? onTap}) {
    return ListTile(
      onTap: onTap ?? () => Navigator.pop(context),
      leading: Icon(icon, color: color ?? (isSelected ? kPrimaryColor : Colors.white70)),
      title: Row(
        children: [
          Text(title, style: TextStyle(color: color ?? Colors.white, fontSize: 11.sp)),
          if (isLive) ...[
            const SizedBox(width: 8),
            Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle)),
          ]
        ],
      ),
      tileColor: isSelected ? Colors.white10 : Colors.transparent,
    );
  }
}

