import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart'; // ✅ استيراد للإشعارات
import 'dart:convert';
import 'sales_rep_dashboard.dart';
import 'visit_screen.dart';
import 'goals_screen.dart'; // استيراد شاشة الأهداف
import 'my_customers_screen.dart'; // ✅ استيراد شاشة عملائي الجديدة
import 'my_orders_screen.dart'; // ✅ استيراد شاشة طلباتي الجديدة
import 'rep_store_lite_screen.dart'; // ✅ استيراد شاشة المتجر الخفيفة
import '../admin/offers_screen.dart'; // ✅ استيراد شاشة العروض المدمجة

// --- الثوابت اللونية ---
const Color kPrimaryColor = Color(0xFF3498db);
const Color kSecondaryColor = Color(0xFF2c3e50);
const Color kSuccessColor = Color(0xFF28a745);
const Color kErrorColor = Color(0xFFdc3545);
const Color kBgColor = Color(0xFFf0f2f5);

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
    _setupNotifications(); // ✅ تشغيل فحص الإشعارات عند الدخول
  }

  // --- 🔔 إعدادات الإشعارات المؤكدة ---
  Future<void> _setupNotifications() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;

    // فحص الحالة الحالية
    NotificationSettings settings = await messaging.getNotificationSettings();

    // 🟢 التعديل المأمن: إذا لم يكن الإذن "مسموحاً" بالفعل، اطلب الإذن واظهر الرسالة
    if (settings.authorizationStatus != AuthorizationStatus.authorized) {
      if (mounted) {
        bool? startRequest = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            title: const Text('تفعيل التنبيهات', textAlign: TextAlign.center),
            content: const Text(
              'يرجى تفعيل التنبيهات لتتمكن من استلام تحديثات الطلبات، تنبيهات الأهداف الميدانية، والرسائل الهامة من الإدارة فور صدورها.',
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
          // طلب إذن النظام الفعلي
          await messaging.requestPermission(
            alert: true,
            badge: true,
            sound: true,
          );
        }
      }
    }
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
        _isDayOpen = true;
        _statusMessage = 'يوم العمل مفتوح حالياً';
      } else {
        _isDayOpen = false;
        currentDayLogId = null;
        currentDayStartTime = null;
        _statusMessage = 'يرجى بدء يوم العمل';
      }
    } catch (e) {
      _statusMessage = 'خطأ في جلب البيانات';
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _startDay() async {
    setState(() => _isLoading = true);
    try {
      await db.collection("daily_logs").add({
        'repCode': repData!['repCode'],
        'repName': repData!['fullname'],
        'startTime': FieldValue.serverTimestamp(),
        'status': "open",
      });
      await _checkDayStatus();
    } catch (e) {
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
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: kBgColor,
        drawer: _buildMainDrawer(),
        appBar: AppBar(
          title: const Text('لوحة المندوب', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          centerTitle: true,
          backgroundColor: Colors.white,
          foregroundColor: kSecondaryColor,
          elevation: 0.5,
          actions: [
            IconButton(icon: const Icon(Icons.refresh), onPressed: _checkDayStatus)
          ],
        ),
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: _checkDayStatus,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildUserInfoHeader(),
                  const SizedBox(height: 20),
                  _buildActionButtons(),
                  const SizedBox(height: 15),
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

  Widget _buildMainDrawer() {
    return Drawer(
      child: Container(
        color: kSecondaryColor,
        child: SafeArea(
          child: Column(
            children: [
              UserAccountsDrawerHeader(
                decoration: const BoxDecoration(color: Color(0xFF1c2a38)),
                currentAccountPicture: const CircleAvatar(
                  backgroundColor: kPrimaryColor,
                  child: Icon(Icons.person, color: Colors.white, size: 40),
                ),
                accountName: Text(repData?['fullname'] ?? 'مندوب المبيعات',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                accountEmail: Text('الكود: ${repData?['repCode'] ?? '...'}'),
              ),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    _drawerItem(Icons.dashboard_outlined, "الرئيسية", true, onTap: () => Navigator.pop(context)),
                    _drawerItem(
                        Icons.storefront_outlined,
                        "المتجر",
                        false,
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(context, MaterialPageRoute(builder: (context) => const RepStoreLiteScreen()));
                        }
                    ),
                    _drawerItem(
                        Icons.track_changes_outlined,
                        "الأهداف",
                        false,
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(context, MaterialPageRoute(builder: (context) => const GoalsScreen()));
                        }
                    ),
                    _drawerItem(
                        Icons.people_outline,
                        "عملائي",
                        false,
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(context, MaterialPageRoute(builder: (context) => const MyCustomersScreen()));
                        }
                    ),
                    _drawerItem(
                        Icons.receipt_outlined,
                        "طلباتي",
                        false,
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(context, MaterialPageRoute(builder: (context) => const MyOrdersScreen()));
                        }
                    ),
                    _drawerItem(
                        Icons.location_on_outlined,
                        "الزيارات",
                        false,
                        onTap: () {
                          Navigator.pop(context);
                          if (_isDayOpen) {
                            Navigator.push(context, MaterialPageRoute(builder: (context) => const VisitScreen()));
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("❌ يجب بدء يوم العمل أولاً لتسجيل الزيارات")),
                            );
                          }
                        }
                    ),
                    _drawerItem(
                        Icons.local_offer_outlined,
                        "مركز العروض والجوائز",
                        false,
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(context, MaterialPageRoute(builder: (context) => const OffersScreen()));
                        }
                    ),
                    _drawerItem(Icons.bar_chart_outlined, "التقارير", false),
                  ],
                ),
              ),
              const Divider(color: Colors.white24),
              _drawerItem(Icons.logout, "خروج", false, color: Colors.redAccent, onTap: () async {
                await FirebaseAuth.instance.signOut();
                final prefs = await SharedPreferences.getInstance();
                await prefs.clear();
                if (mounted) Navigator.of(context).pushReplacementNamed('/');
              }),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  Widget _drawerItem(IconData icon, String title, bool isSelected, {Color? color, VoidCallback? onTap}) {
    return ListTile(
      leading: Icon(icon, color: color ?? (isSelected ? kPrimaryColor : Colors.white70)),
      title: Text(title, style: TextStyle(color: color ?? Colors.white)),
      selected: isSelected,
      onTap: onTap ?? () => Navigator.pop(context),
    );
  }

  Widget _buildUserInfoHeader() {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: kPrimaryColor),
          const SizedBox(width: 10),
          Text(_statusMessage, style: const TextStyle(fontWeight: FontWeight.bold, color: kSecondaryColor)),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _isLoading ? null : (_isDayOpen ? _endDay : _startDay),
        icon: Icon(_isDayOpen ? Icons.stop_circle_outlined : Icons.play_circle_outline),
        label: Text(_isDayOpen ? "إنهاء يوم العمل" : "بدء يوم العمل",
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        style: ElevatedButton.styleFrom(
          backgroundColor: _isDayOpen ? kErrorColor : kSuccessColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.only(top: 60),
      child: Column(
        children: [
          Icon(Icons.event_busy_outlined, size: 80, color: Colors.grey.shade400),
          const SizedBox(height: 15),
          const Text('لا يوجد يوم عمل مفتوح حالياً.\nاضغط على الزر أعلاه للبدء.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 16)),
        ],
      ),
    );
  }
}

