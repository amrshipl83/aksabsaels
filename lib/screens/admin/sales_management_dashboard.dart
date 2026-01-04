import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart'; // ✅ استيراد للإشعارات
import 'dart:convert';
import 'package:sizer/sizer.dart';

// استيراد الصفحات التابعة
import 'sales_orders_report_screen.dart';
import 'customers_report_screen.dart';
import 'offers_screen.dart';
import 'profile_screen.dart'; 

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
  final Color kBgColor = const Color(0xFFF8F9FD);
  final Color kCardColor = Colors.white;

  int totalOrders = 0;
  double totalSales = 0;
  int totalAgents = 0;
  int secondaryStat = 0; 

  @override
  void initState() {
    super.initState();
    _initDashboard();
    _setupNotifications(); // ✅ تفعيل طلب إذن الإشعارات للإدارة عند الدخول
  }

  // --- 🔔 تأمين طلب الإشعارات للمديرين والمشرفين ---
  Future<void> _setupNotifications() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;
    NotificationSettings settings = await messaging.getNotificationSettings();

    // إذا لم يكن الإذن "مسموحاً" بالفعل
    if (settings.authorizationStatus != AuthorizationStatus.authorized) {
      if (mounted) {
        bool? startRequest = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            title: const Text('تفعيل تنبيهات الإدارة', textAlign: TextAlign.center),
            content: const Text(
              'يرجى تفعيل التنبيهات لتتمكن من استلام تقارير المبيعات اليومية، تنبيهات طلبات المناديب، والإحصائيات الهامة فور تحديثها.',
              textAlign: TextAlign.center,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('لاحقاً', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(backgroundColor: kPrimaryColor),
                child: const Text('موافق', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );

        if (startRequest == true) {
          await messaging.requestPermission(alert: true, badge: true, sound: true);
        }
      }
    }
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
    String myDocId = _userData?['docId'] ?? '';
    if (myDocId.isEmpty) return;
    try {
      List<String> repCodes = [];
      if (role == 'sales_supervisor') {
        final agentsSnap = await FirebaseFirestore.instance
            .collection('salesRep')
            .where('supervisorId', isEqualTo: myDocId)
            .get();
        repCodes = agentsSnap.docs.map((doc) => doc['repCode'] as String).toList();
        totalAgents = agentsSnap.size;

        if (repCodes.isNotEmpty) {
           final customersSnap = await FirebaseFirestore.instance
               .collection('deliverySupermarkets') 
               .where('ownerId', whereIn: repCodes)
               .get();
           secondaryStat = customersSnap.size;
        }
      } else if (role == 'sales_manager') {
        final supervisorsSnap = await FirebaseFirestore.instance
            .collection('managers')
            .where('managerId', isEqualTo: myDocId)
            .get();
        secondaryStat = supervisorsSnap.size; 

        List<String> supervisorIds = supervisorsSnap.docs.map((d) => d.id).toList();
        if (supervisorIds.isNotEmpty) {
          final agentsSnap = await FirebaseFirestore.instance
              .collection('salesRep')
              .where('supervisorId', whereIn: supervisorIds)
              .get();
          repCodes = agentsSnap.docs.map((doc) => doc['repCode'] as String).toList();
          totalAgents = agentsSnap.size;
        }
      }

      if (repCodes.isNotEmpty) {
        final ordersSnap = await FirebaseFirestore.instance
            .collection('orders')
            .where('buyer.repCode', whereIn: repCodes)
            .get();
        double salesSum = 0;
        for (var doc in ordersSnap.docs) {
          salesSum += (doc.data()['total'] ?? 0).toDouble();
        }
        setState(() {
          totalOrders = ordersSnap.size;
          totalSales = salesSum;
        });
      }
    } catch (e) {
      debugPrint("Firestore Stats Error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_errorMsg != null) {
      return Scaffold(body: Center(child: Text("خطأ: $_errorMsg", style: const TextStyle(color: Colors.red))));
    }

    String role = _userData?['role'] ?? '';
    String staffTitle = (role == 'sales_manager') ? "المشرفين والمناديب" : "المناديب";
    String secondaryStatTitle = (role == 'sales_manager') ? "عدد المشرفين" : "إجمالي العملاء";

    return Scaffold(
      backgroundColor: kBgColor,
      appBar: AppBar(
        title: Text("لوحة التحكم", style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w900)),
        backgroundColor: Colors.white,
        foregroundColor: kSidebarColor,
        elevation: 0,
        centerTitle: true,
        leading: Builder(builder: (context) {
          return IconButton(
            icon: Icon(Icons.menu_open_rounded, size: 24.sp),
            onPressed: () => Scaffold.of(context).openDrawer(),
          );
        }),
      ),
      drawer: _buildDrawer(staffTitle),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: 5.w, vertical: 2.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildWelcomeSection(),
              SizedBox(height: 3.5.h),
              Text("إحصائيات الأداء", style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.bold, color: kSidebarColor.withOpacity(0.8))),
              SizedBox(height: 1.5.h),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                crossAxisSpacing: 4.w,
                mainAxisSpacing: 4.w,
                children: [
                  _buildStatCard("إجمالي الطلبات", "$totalOrders", Icons.shopping_bag_outlined, const Color(0xFF3498DB)),
                  _buildStatCard("إجمالي المبيعات", "${totalSales.toInt()}", Icons.account_balance_wallet_outlined, const Color(0xFF2ECC71)),
                  _buildStatCard("عدد المندوبين", "$totalAgents", Icons.groups_2_outlined, const Color(0xFFE67E22)),
                  _buildStatCard(secondaryStatTitle, "$secondaryStat", Icons.analytics_outlined, const Color(0xFF9B59B6)),
                ],
              ),
              SizedBox(height: 4.h),
              Text("الوصول السريع", style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.bold, color: kSidebarColor.withOpacity(0.8))),
              SizedBox(height: 1.5.h),
              _buildQuickAction(Icons.card_giftcard_rounded, "مركز العروض والجوائز", () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => const OffersScreen()));
              }),
              _buildQuickAction(Icons.sensors_rounded, "تتبع المندوبين لايف", () {
                Navigator.pushNamed(context, '/live_monitoring');
              }),
              _buildQuickAction(Icons.manage_accounts_outlined, staffTitle, () {
                Navigator.pushNamed(context, '/manage_users');
              }),
              _buildQuickAction(Icons.people_alt_outlined, "تقرير العملاء والمسحوبات", () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => const CustomersReportScreen()));
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomeSection() {
    return Container(
      padding: EdgeInsets.all(5.w),
      decoration: BoxDecoration(
        color: kSidebarColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: kSidebarColor.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 8))],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 7.w,
            backgroundColor: kPrimaryColor.withOpacity(0.1),
            child: Icon(Icons.person_2_rounded, color: kPrimaryColor, size: 10.w)
          ),
          SizedBox(width: 4.w),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("مرحباً بك،", style: TextStyle(color: Colors.white60, fontSize: 13.sp)),
              Text("${_userData?['fullname'] ?? 'مستخدم'}", style: TextStyle(color: Colors.white, fontSize: 18.sp, fontWeight: FontWeight.w900)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: EdgeInsets.all(3.w),
      decoration: BoxDecoration(
        color: kCardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: EdgeInsets.all(3.w),
            decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 26.sp),
          ),
          SizedBox(height: 1.2.h),
          Text(title, textAlign: TextAlign.center, style: TextStyle(fontSize: 10.sp, color: Colors.blueGrey, fontWeight: FontWeight.w600)),
          Text(value, style: TextStyle(fontSize: 17.sp, fontWeight: FontWeight.w900, color: kSidebarColor)),
        ],
      ),
    );
  }

  Widget _buildQuickAction(IconData icon, String title, VoidCallback onTap) {
    return Container(
      margin: EdgeInsets.only(bottom: 2.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 15, offset: const Offset(0, 5))],
      ),
      child: ListTile(
        contentPadding: EdgeInsets.symmetric(horizontal: 5.w, vertical: 0.8.h),
        leading: Container(
          padding: EdgeInsets.all(2.5.w),
          decoration: BoxDecoration(color: kPrimaryColor.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: kPrimaryColor, size: 22.sp),
        ),
        title: Text(title, style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w800, color: kSidebarColor)),
        trailing: Icon(Icons.arrow_forward_ios_rounded, size: 14.sp, color: Colors.grey.shade400),
        onTap: onTap,
      ),
    );
  }

  Widget _buildDrawer(String staffTitle) {
    return Drawer(
      width: 80.w,
      backgroundColor: kSidebarColor,
      child: Column(
        children: [
          Container(
            height: 25.h,
            width: double.infinity,
            padding: EdgeInsets.all(5.w),
            alignment: Alignment.bottomRight,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("أكسب", style: TextStyle(color: kPrimaryColor, fontSize: 24.sp, fontWeight: FontWeight.w900)),
                Text("إدارة المبيعات", style: TextStyle(color: Colors.white70, fontSize: 14.sp)),
              ],
            ),
          ),
          const Divider(color: Colors.white10, height: 1),
          Expanded(
            child: ListView(
              padding: EdgeInsets.symmetric(vertical: 2.h),
              children: [
                _drawerItem(Icons.dashboard_customize_outlined, "الرئيسية", true, onTap: () => Navigator.pop(context)),
                _drawerItem(Icons.account_circle_outlined, "الملف الشخصي والإعدادات", false, onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (context) => const ProfileScreen()));
                }),
                _drawerItem(Icons.card_giftcard_rounded, "مركز العروض", false, onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (context) => const OffersScreen()));
                }),
                _drawerItem(Icons.assignment_outlined, "تقارير الطلبات", false, onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (context) => const SalesOrdersReportScreen()));
                }),
                _drawerItem(Icons.person_pin_circle_outlined, "العملاء", false, onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (context) => const CustomersReportScreen()));
                }),
                _drawerItem(Icons.admin_panel_settings_outlined, staffTitle, false, onTap: () {
                  Navigator.pop(context);
                  Navigator.pushNamed(context, '/manage_users');
                }),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10), child: Divider(color: Colors.white10)),
                _drawerItem(Icons.logout_rounded, "تسجيل الخروج", false, color: Colors.redAccent, onTap: () async {
                  await FirebaseAuth.instance.signOut();
                  (await SharedPreferences.getInstance()).clear();
                  if (mounted) Navigator.of(context).pushReplacementNamed('/');
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _drawerItem(IconData icon, String title, bool active, {Color? color, VoidCallback? onTap}) {
    return ListTile(
      onTap: onTap,
      horizontalTitleGap: 0,
      leading: Icon(icon, color: color ?? (active ? kPrimaryColor : Colors.white70), size: 22.sp),
      title: Text(title, style: TextStyle(color: color ?? (active ? Colors.white : Colors.white70), fontSize: 15.sp, fontWeight: active ? FontWeight.w900 : FontWeight.w500)),
    );
  }
}

