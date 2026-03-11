import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:geolocator/geolocator.dart'; 
import 'package:permission_handler/permission_handler.dart'; 
import 'dart:convert';

import 'sales_rep_dashboard.dart';
import 'visit_screen.dart';
import 'goals_screen.dart';
import 'my_customers_screen.dart';
import 'my_orders_screen.dart';
import 'rep_store_lite_screen.dart';
import 'rep_reports_screen.dart';
import '../admin/offers_screen.dart';

// --- الثوابت اللونية لهوية أكسب مبيعات ---
const Color kPrimaryColor = Color(0xFFB21F2D); // أحمر أكسب
const Color kSecondaryColor = Color(0xFF1A2C3D); 
const Color kSuccessColor = Color(0xFF2E7D32); 
const Color kErrorColor = Color(0xFFC62828);   
const Color kBgColor = Color(0xFFF8F9FA);

class SalesRepHomeScreen extends StatefulWidget {
  const SalesRepHomeScreen({super.key});

  @override
  State<SalesRepHomeScreen> createState() => _SalesRepHomeScreenState();
}

class _SalesRepHomeScreenState extends State<SalesRepHomeScreen> {
  Map<String, dynamic>? repData;
  String? currentDayLogId;
  DateTime? currentDayStartTime;
  bool _isLoading = true;
  String _statusMessage = 'جاري التحقق...';
  bool _isDayOpen = false;
  final db = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _checkUserDataAndDayStatus();
    _setupNotifications();
  }

  // --- نظام التنبيهات ---
  Future<void> _setupNotifications() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;
    NotificationSettings settings = await messaging.getNotificationSettings();

    if (settings.authorizationStatus != AuthorizationStatus.authorized) {
      if (mounted) {
        bool? startRequest = await _showDisclosureDialog(
          title: 'تفعيل التنبيهات',
          body: 'نحتاج لتفعيل التنبيهات لإرسال تحديثات الطلبات الميدانية ورسائل الإدارة الهامة لك.',
          icon: Icons.notifications_active_outlined,
        );
        if (startRequest == true) {
          await messaging.requestPermission(alert: true, badge: true, sound: true);
        }
      }
    }
  }

  // --- نظام أذونات الموقع ---
  Future<bool> _handleLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showSnackBar("❌ يرجى تفعيل الـ GPS في هاتفك أولاً");
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      bool? confirm = await _showDisclosureDialog(
        title: 'إذن الوصول للموقع',
        body: 'يتطلب "أكسب مبيعات" الوصول لموقعك الجغرافي لتسجيل "بصمة حضور العمل" وضمان تسجيل الزيارات للعملاء بدقة.',
        icon: Icons.location_on_outlined,
      );
      if (confirm == true) {
        permission = await Geolocator.requestPermission();
      }
    }

    if (permission == LocationPermission.deniedForever) {
      _showSnackBar("❌ إذن الموقع مرفوض دائماً، يرجى تفعيله من إعدادات الجهاز");
      return false;
    }
    return permission == LocationPermission.always || permission == LocationPermission.whileInUse;
  }

  Future<bool?> _showDisclosureDialog({required String title, required String body, required IconData icon}) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Column(
          children: [
            Icon(icon, size: 40, color: kPrimaryColor),
            const SizedBox(height: 10),
            Text(title, textAlign: TextAlign.center),
          ],
        ),
        content: Text(body, textAlign: TextAlign.center),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ليس الآن', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: kPrimaryColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: const Text('موافق وفهمت', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _checkUserDataAndDayStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final userDataString = prefs.getString('userData');
    if (userDataString == null) {
      if (mounted) Navigator.of(context).pushReplacementNamed('/');
      return;
    }
    repData = jsonDecode(userDataString);
    await _checkDayStatus();
  }

  Future<void> _checkDayStatus() async {
    if (repData == null) return;
    if (mounted) setState(() => _isLoading = true);
    try {
      final q = db.collection("daily_logs")
          .where("repCode", isEqualTo: repData!['repCode'])
          .where("status", isEqualTo: "open")
          .limit(1);
      final querySnapshot = await q.get();
      if (querySnapshot.docs.isNotEmpty) {
        final docData = querySnapshot.docs[0].data();
        currentDayLogId = querySnapshot.docs[0].id;
        currentDayStartTime = (docData['startTime'] as Timestamp?)?.toDate();
        setState(() { _isDayOpen = true; _statusMessage = 'يوم العمل مفتوح حالياً'; });
      } else {
        setState(() { 
          _isDayOpen = false; 
          currentDayLogId = null;
          currentDayStartTime = null;
          _statusMessage = 'يرجى بدء يوم العمل'; 
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _startDay() async {
    bool hasPermission = await _handleLocationPermission();
    if (!hasPermission) return;

    setState(() => _isLoading = true);
    try {
      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      await db.collection("daily_logs").add({
        'repCode': repData!['repCode'],
        'repName': repData!['fullname'],
        'startTime': FieldValue.serverTimestamp(),
        'status': "open",
        'startLocation': {
          'lat': position.latitude,
          'lng': position.longitude,
        },
      });
      await _checkDayStatus();
    } catch (e) {
      _showSnackBar("❌ فشل تسجيل الموقع، حاول مرة أخرى");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _endDay() async {
    setState(() => _isLoading = true);
    try {
      await db.collection("daily_logs").doc(currentDayLogId).update({
        'endTime': FieldValue.serverTimestamp(),
        'status': "closed",
      });
      await _checkDayStatus();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: kPrimaryColor));
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: kBgColor,
        drawer: _buildMainDrawer(),
        appBar: AppBar(
          title: const Text('أكسب للمبيعات', style: TextStyle(fontWeight: FontWeight.bold)),
          centerTitle: true,
          backgroundColor: Colors.white,
          foregroundColor: kSecondaryColor,
          elevation: 0,
          actions: [IconButton(icon: const Icon(Icons.sync_rounded), onPressed: _checkDayStatus)],
        ),
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: _checkDayStatus,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildUserInfoHeader(),
                  const SizedBox(height: 20),
                  _buildActionButtons(),
                  const SizedBox(height: 20),
                  if (_isDayOpen && currentDayStartTime != null)
                    SalesRepDashboard(
                      repCode: repData!['repCode'],
                      currentDayStartTime: currentDayStartTime!,
                      onDataRefreshed: _checkDayStatus,
                    )
                  else if (!_isLoading)
                    _buildEmptyState(),
                  if (_isLoading)
                    const Padding(
                      padding: EdgeInsets.only(top: 40),
                      child: CircularProgressIndicator(color: kPrimaryColor),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUserInfoHeader() {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.grey.shade200)),
      child: Row(children: [
        const Icon(Icons.info_outline_rounded, color: kPrimaryColor),
        const SizedBox(width: 10),
        Text(_statusMessage, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      ]),
    );
  }

  Widget _buildActionButtons() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _isLoading ? null : (_isDayOpen ? _endDay : _startDay),
        icon: Icon(_isDayOpen ? Icons.stop_rounded : Icons.play_arrow_rounded, size: 28),
        label: Text(_isDayOpen ? "إنهاء وردية العمل" : "بدء يوم عمل جديد", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        style: ElevatedButton.styleFrom(
          backgroundColor: _isDayOpen ? kErrorColor : kSuccessColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.only(top: 40),
      child: Column(children: [
        Icon(Icons.location_off_outlined, size: 80, color: Colors.grey.shade400),
        const SizedBox(height: 15),
        const Text('يجب فتح يوم العمل لتفعيل عدادات الإنجاز والزيارات والطلبات.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
      ]),
    );
  }

  // --- Drawer (استرجاع كافة الأيقونات من الكود الأصلي) ---
  Widget _buildMainDrawer() {
    return Drawer(
      child: Container(
        color: kSecondaryColor,
        child: SafeArea(
          child: Column(children: [
            UserAccountsDrawerHeader(
              decoration: const BoxDecoration(color: Color(0xFF14212D)),
              currentAccountPicture: const CircleAvatar(backgroundColor: kPrimaryColor, child: Icon(Icons.person, color: Colors.white, size: 40)),
              accountName: Text(repData?['fullname'] ?? 'مندوب مبيعات', style: const TextStyle(fontWeight: FontWeight.bold)),
              accountEmail: Text('كود الموظف: ${repData?['repCode'] ?? '...'}'),
            ),
            Expanded(child: ListView(children: [
              _drawerItem(Icons.dashboard_outlined, "الرئيسية", true, onTap: () => Navigator.pop(context)),
              
              _drawerItem(Icons.storefront_outlined, "المتجر", false, onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (context) => const RepStoreLiteScreen()));
              }),
              
              _drawerItem(Icons.track_changes_outlined, "الأهداف", false, onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (context) => const GoalsScreen()));
              }),

              _drawerItem(Icons.people_outline, "قائمة عملائي", false, onTap: () { 
                Navigator.pop(context); 
                Navigator.push(context, MaterialPageRoute(builder: (context) => const MyCustomersScreen())); 
              }),

              _drawerItem(Icons.receipt_outlined, "طلباتي", false, onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (context) => const MyOrdersScreen()));
              }),

              _drawerItem(Icons.location_on_outlined, "بدء زيارة", false, onTap: () {
                Navigator.pop(context);
                if (_isDayOpen) { Navigator.push(context, MaterialPageRoute(builder: (context) => const VisitScreen())); }
                else { _showSnackBar("❌ يرجى فتح اليوم أولاً لتسجيل الزيارات"); }
              }),

              _drawerItem(Icons.local_offer_outlined, "مركز العروض والجوائز", false, onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (context) => const OffersScreen()));
              }),

              _drawerItem(Icons.bar_chart_outlined, "تقارير الإنجاز", false, onTap: () { 
                Navigator.pop(context); 
                Navigator.push(context, MaterialPageRoute(builder: (context) => const RepReportsScreen())); 
              }),
            ])),
            const Divider(color: Colors.white24),
            _drawerItem(Icons.logout, "تسجيل الخروج", false, color: Colors.redAccent, onTap: () async {
              await FirebaseAuth.instance.signOut();
              final prefs = await SharedPreferences.getInstance();
              await prefs.clear();
              if (mounted) Navigator.of(context).pushReplacementNamed('/');
            }),
          ]),
        ),
      ),
    );
  }

  Widget _drawerItem(IconData icon, String title, bool isSelected, {Color? color, VoidCallback? onTap}) {
    return ListTile(
      leading: Icon(icon, color: color ?? (isSelected ? kPrimaryColor : Colors.white70)),
      title: Text(title, style: TextStyle(color: color ?? Colors.white)),
      onTap: onTap,
    );
  }
}

