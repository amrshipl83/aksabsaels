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

  final Color kPrimaryColor = const Color(0xFF1ABC9C);
  final Color kSidebarColor = const Color(0xFF2F3542);
  final Color kBgColor = const Color(0xFFF5F6FA);

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
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = prefs.getString('userData');
      if (data != null) {
        _userData = jsonDecode(data);
        await _loadStats();
      }
    } catch (e) {
      debugPrint("Init Error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadStats() async {
    if (_userData == null) return;
    
    String role = _userData?['role'] ?? '';
    String managerDocId = _userData?['uid'] ?? '';

    try {
      Query agentsQuery = FirebaseFirestore.instance.collection('salesRep');
      if (role == 'sales_supervisor') {
        agentsQuery = agentsQuery.where('supervisorId', isEqualTo: managerDocId);
      }
      final agentsSnap = await agentsQuery.get();
      totalAgents = agentsSnap.size;

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
      debugPrint("Firestore Error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    // نستخدم Scaffold بسيط أثناء التحميل لضمان عدم ظهور شاشة بيضاء فارغة
    if (_isLoading) {
      return Scaffold(
        backgroundColor: kBgColor,
        body: const Center(child: CircularProgressIndicator(color: Color(0xFF1ABC9C))),
      );
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: kBgColor,
        appBar: AppBar(
          title: Text(
            _userData?['role'] == 'sales_manager' ? 'لوحة المبيعات' : 'إدارة المشرف',
            style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.white,
          foregroundColor: kSidebarColor,
          elevation: 0.5,
          centerTitle: true,
          // إضافة زر القائمة يدوياً للتأكد من ظهوره
          leading: Builder(
            builder: (context) => IconButton(
              icon: Icon(Icons.menu, size: 24.sp),
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
          ),
        ),
        drawer: _buildDrawer(),
        body: SingleChildScrollView(
          padding: EdgeInsets.all(15.sp), // استخدام sp بدلاً من dp للاتساق
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildWelcomeSection(),
              SizedBox(height: 20.sp),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                crossAxisSpacing: 15.sp,
                mainAxisSpacing: 15.sp,
                childAspectRatio: 1.1,
                children: [
                  _buildStatCard("إجمالي الطلبات", "$totalOrders", Icons.shopping_basket, Colors.blue),
                  _buildStatCard("إجمالي المبيعات", "${totalSales.toInt()}", Icons.monetization_on, Colors.green),
                  _buildStatCard("عدد المندوبين", "$totalAgents", Icons.people, Colors.orange),
                  _buildStatCard("متوسط التقييم", avgRating.toStringAsFixed(1), Icons.star, Colors.amber),
                ],
              ),
              SizedBox(height: 25.sp),
              Text("الإجراءات السريعة", style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold, color: kSidebarColor)),
              SizedBox(height: 15.sp),
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
      padding: EdgeInsets.all(15.sp),
      decoration: BoxDecoration(
        color: kSidebarColor,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 25.sp,
            backgroundColor: kPrimaryColor,
            child: Icon(Icons.admin_panel_settings, color: Colors.white, size: 28.sp),
          ),
          SizedBox(width: 15.sp),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("مرحباً بك،", style: TextStyle(color: Colors.white70, fontSize: 14.sp)),
                Text(
                  "${_userData?['fullname'] ?? 'مدير النظام'}",
                  style: TextStyle(color: Colors.white, fontSize: 18.sp, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: EdgeInsets.all(8.sp),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5)],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 30.sp),
          SizedBox(height: 8.sp),
          Text(title, style: TextStyle(color: Colors.grey[700], fontSize: 12.sp), textAlign: TextAlign.center),
          FittedBox(
            child: Text(
              value,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18.sp, color: kSidebarColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickAction(IconData icon, String title, VoidCallback onTap) {
    return Card(
      margin: EdgeInsets.only(bottom: 12.sp),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: EdgeInsets.symmetric(horizontal: 15.sp, vertical: 5.sp),
        leading: Icon(icon, color: kPrimaryColor, size: 25.sp),
        title: Text(title, style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w500)),
        trailing: Icon(Icons.arrow_forward_ios, size: 15.sp, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      child: Container(
        color: kSidebarColor,
        child: SafeArea(
          child: Column(
            children: [
              SizedBox(height: 20.sp),
              Text("أكسب - إدارة المبيعات", style: TextStyle(color: kPrimaryColor, fontSize: 20.sp, fontWeight: FontWeight.bold)),
              SizedBox(height: 20.sp),
              const Divider(color: Colors.white24, thickness: 1),
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
              const Divider(color: Colors.white24),
              _drawerItem(Icons.logout, "تسجيل الخروج", false, color: Colors.redAccent, onTap: () async {
                await FirebaseAuth.instance.signOut();
                final prefs = await SharedPreferences.getInstance();
                await prefs.clear();
                if (mounted) Navigator.of(context).pushReplacementNamed('/');
              }),
              SizedBox(height: 15.sp),
            ],
          ),
        ),
      ),
    );
  }

  Widget _drawerItem(IconData icon, String title, bool isSelected, {Color? color, bool isLive = false, VoidCallback? onTap}) {
    return ListTile(
      onTap: onTap ?? () => Navigator.pop(context),
      leading: Icon(icon, color: color ?? (isSelected ? kPrimaryColor : Colors.white70), size: 20.sp),
      title: Row(
        children: [
          Text(title, style: TextStyle(color: color ?? Colors.white, fontSize: 15.sp)),
          if (isLive) ...[
            SizedBox(width: 10.sp),
            Container(width: 8.sp, height: 8.sp, decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle)),
          ]
        ],
      ),
      tileColor: isSelected ? Colors.white10 : Colors.transparent,
    );
  }
}

