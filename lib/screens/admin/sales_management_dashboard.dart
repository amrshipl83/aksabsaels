import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:sizer/sizer.dart';
// استيراد الصفحة الجديدة
import 'sales_orders_report_screen.dart';

class SalesManagementDashboard extends StatefulWidget {
  const SalesManagementDashboard({super.key});

  @override
  State<SalesManagementDashboard> createState() => _SalesManagementDashboardState();
}

class _SalesManagementDashboardState extends State<SalesManagementDashboard> {
  Map<String, dynamic>? _userData;
  bool _isLoading = true;
  String? _errorMsg;

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
      } else {
        setState(() => _errorMsg = "لم يتم العثور على بيانات المستخدم");
      }
    } catch (e) {
      setState(() => _errorMsg = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadStats() async {
    String role = _userData?['role'] ?? '';
    String managerDocId = _userData?['docId'] ?? '';
    if (managerDocId.isEmpty) return;

    try {
      Query agentsQuery = FirebaseFirestore.instance.collection('salesRep');

      if (role == 'sales_supervisor') {
        agentsQuery = agentsQuery.where('supervisorId', isEqualTo: managerDocId);
      } else if (role == 'sales_manager') {
        agentsQuery = agentsQuery.where('ownerId', isEqualTo: managerDocId);
      }

      final agentsSnap = await agentsQuery.get();
      totalAgents = agentsSnap.size;

      if (agentsSnap.docs.isNotEmpty) {
        List<String> repCodes = agentsSnap.docs.map((doc) => doc['repCode'] as String).toList();

        Query ordersQuery = FirebaseFirestore.instance.collection('orders')
            .where('buyer.repCode', whereIn: repCodes);

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

        setState(() {
          totalOrders = ordersSnap.size;
          totalSales = salesSum;
          avgRating = ratedCount > 0 ? (ratingSum / ratedCount) : 0;
        });
      } else {
        setState(() {
          totalOrders = 0;
          totalSales = 0;
          avgRating = 0;
        });
      }
    } catch (e) {
      debugPrint("Firestore Error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    if (_errorMsg != null) {
      return Scaffold(body: Center(child: Text("خطأ: $_errorMsg", style: const TextStyle(color: Colors.red))));
    }

    String role = _userData?['role'] ?? '';
    String staffManagementTitle = (role == 'sales_manager') ? "المندوبين والمشرفين" : "المندوبين";

    return Scaffold(
      backgroundColor: kBgColor,
      appBar: AppBar(
        title: Text("لوحة التحكم", style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: kSidebarColor,
        elevation: 0.5,
        leading: Builder(builder: (context) {
          return IconButton(
            icon: Icon(Icons.menu, size: 25.sp),
            onPressed: () => Scaffold.of(context).openDrawer(),
          );
        }),
      ),
      drawer: _buildDrawer(staffManagementTitle),
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 2.h),
        child: Column(
          children: [
            _buildWelcomeSection(),
            SizedBox(height: 3.h),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              crossAxisSpacing: 3.w,
              mainAxisSpacing: 3.w,
              childAspectRatio: 1.1,
              children: [
                _buildStatCard("إجمالي الطلبات", "$totalOrders", Icons.shopping_basket, Colors.blue),
                _buildStatCard("إجمالي المبيعات", "${totalSales.toInt()}", Icons.monetization_on, Colors.green),
                _buildStatCard("عدد المندوبين", "$totalAgents", Icons.people, Colors.orange),
                _buildStatCard("متوسط التقييم", avgRating.toStringAsFixed(1), Icons.star, Colors.amber),
              ],
            ),
            SizedBox(height: 4.h),
            _buildQuickAction(Icons.sensors, "تتبع المندوبين لايف", () {
              Navigator.pushNamed(context, '/live_monitoring');
            }),
            _buildQuickAction(Icons.manage_accounts, staffManagementTitle, () {
              Navigator.pushNamed(context, '/manage_users');
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomeSection() {
    return Container(
      padding: EdgeInsets.all(4.w),
      decoration: BoxDecoration(color: kSidebarColor, borderRadius: BorderRadius.circular(15)),
      child: Row(
        children: [
          CircleAvatar(radius: 6.w, backgroundColor: kPrimaryColor, child: Icon(Icons.person, color: Colors.white, size: 8.w)),
          SizedBox(width: 4.w),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("مرحباً بك،", style: TextStyle(color: Colors.white70, fontSize: 13.sp)),
              Text("${_userData?['fullname'] ?? 'مستخدم'}", style: TextStyle(color: Colors.white, fontSize: 17.sp, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 28.sp),
          SizedBox(height: 1.h),
          Text(title, style: TextStyle(fontSize: 12.sp, color: Colors.black54)),
          Text(value, style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold, color: kSidebarColor)),
        ],
      ),
    );
  }

  Widget _buildQuickAction(IconData icon, String title, VoidCallback onTap) {
    return Card(
      elevation: 2,
      margin: EdgeInsets.only(bottom: 2.h),
      child: ListTile(
        leading: Icon(icon, color: kPrimaryColor, size: 22.sp),
        title: Text(title, style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
        // تم حذف const هنا لحل مشكلة البناء 🛑
        trailing: Icon(Icons.arrow_forward_ios, size: 14.sp),
        onTap: onTap,
      ),
    );
  }

  Widget _buildDrawer(String staffTitle) {
    return Drawer(
      child: Container(
        color: kSidebarColor,
        child: Column(
          children: [
            SizedBox(height: 8.h),
            Text("أكسب - إدارة المبيعات", style: TextStyle(color: kPrimaryColor, fontSize: 18.sp, fontWeight: FontWeight.bold)),
            const Divider(color: Colors.white24),
            Expanded(
              child: ListView(
                children: [
                  _drawerItem(Icons.dashboard, "الرئيسية", true, onTap: () => Navigator.pop(context)),
                  _drawerItem(Icons.receipt_long, "تقارير الطلبات", false, onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const SalesOrdersReportScreen()),
                    );
                  }),
                  _drawerItem(Icons.people, "العملاء", false),
                  _drawerItem(Icons.manage_accounts, staffTitle, false, onTap: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/manage_users');
                  }),
                  _drawerItem(Icons.pie_chart, "التقارير الشاملة", false),
                  _drawerItem(Icons.percent, "عروض الشهر", false),
                  _drawerItem(Icons.location_on, "تقارير الزيارات", false),
                  _drawerItem(Icons.sensors, "لايف - المتابعة اللحظية", false, onTap: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/live_monitoring');
                  }),
                  const Divider(color: Colors.white10),
                  _drawerItem(Icons.logout, "تسجيل الخروج", false, color: Colors.redAccent, onTap: () async {
                    await FirebaseAuth.instance.signOut();
                    (await SharedPreferences.getInstance()).clear();
                    if (mounted) Navigator.of(context).pushReplacementNamed('/');
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _drawerItem(IconData icon, String title, bool active, {Color? color, VoidCallback? onTap}) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: color ?? (active ? kPrimaryColor : Colors.white70), size: 22.sp),
      title: Text(title, style: TextStyle(color: color ?? Colors.white, fontSize: 15.sp)),
    );
  }
}

