import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:sizer/sizer.dart';
import 'package:url_launcher/url_launcher.dart'; // ضرورية للاتصال

class LiveMonitoringScreen extends StatefulWidget {
  const LiveMonitoringScreen({super.key});

  @override
  State<LiveMonitoringScreen> createState() => _LiveMonitoringScreenState();
}

class _LiveMonitoringScreenState extends State<LiveMonitoringScreen> {
  Map<String, dynamic>? _userData;
  bool _isLoading = true;
  final Color kPrimaryColor = const Color(0xFF1ABC9C);
  final Color kActiveVisitColor = const Color(0xFF3498DB);
  final Color kSidebarColor = const Color(0xFF2F3542);

  @override
  void initState() {
    super.initState();
    _loadUserAndData();
  }

  Future<void> _loadUserAndData() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('userData');
    if (data != null) {
      if (mounted) {
        setState(() {
          _userData = jsonDecode(data);
          _isLoading = false;
        });
      }
    }
  }

  // دالة الاتصال الهاتفي
  Future<void> _makeCall(String? phoneNumber) async {
    if (phoneNumber == null || phoneNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("رقم الهاتف غير مسجل")),
      );
      return;
    }
    final Uri launchUri = Uri(scheme: 'tel', path: phoneNumber);
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F6FA),
        appBar: AppBar(
          title: Text("متابعة المندوبين لايف", 
              style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold)),
          backgroundColor: Colors.white,
          foregroundColor: kSidebarColor,
          elevation: 0.5,
          centerTitle: true,
        ),
        body: _buildLiveStream(),
      ),
    );
  }

  Widget _buildLiveStream() {
    String role = _userData?['role'] ?? '';
    String myDocId = _userData?['docId'] ?? '';

    if (role == 'sales_supervisor') {
      return _buildRepsWatcher(
        FirebaseFirestore.instance.collection('salesRep')
            .where('supervisorId', isEqualTo: myDocId)
      );
    } else if (role == 'sales_manager') {
      return StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('managers')
            .where('managerId', isEqualTo: myDocId)
            .where('role', isEqualTo: 'sales_supervisor')
            .snapshots(),
        builder: (context, supervisorSnap) {
          if (supervisorSnap.hasError) return const Center(child: Text("خطأ في تحميل المشرفين"));
          if (!supervisorSnap.hasData) return const Center(child: CircularProgressIndicator());

          List<String> supervisorIds = supervisorSnap.data!.docs.map((doc) => doc.id).toList();
          if (supervisorIds.isEmpty) {
            return Center(child: Text("لا يوجد مشرفين تابعين لك حالياً", style: TextStyle(fontSize: 15.sp)));
          }

          return _buildRepsWatcher(
            FirebaseFirestore.instance.collection('salesRep')
                .where('supervisorId', whereIn: supervisorIds)
          );
        },
      );
    }
    return const Center(child: Text("غير مسموح للعرض"));
  }

  Widget _buildRepsWatcher(Query repsQuery) {
    return StreamBuilder<QuerySnapshot>(
      stream: repsQuery.snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        var repsDocs = snapshot.data!.docs;
        if (repsDocs.isEmpty) return Center(child: Text("لا يوجد مندوبين", style: TextStyle(fontSize: 15.sp)));

        // تحويل المناديب لـ Map لسهولة الوصول لبياناتهم (مثل التليفون)
        Map<String, dynamic> repsInfo = {};
        for (var doc in repsDocs) {
          repsInfo[doc['repCode']] = doc.data();
        }

        List<String> repCodes = repsInfo.keys.toList();

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('daily_logs')
              .where('status', isEqualTo: 'open')
              .where('repCode', whereIn: repCodes)
              .snapshots(),
          builder: (context, logSnapshot) {
            if (!logSnapshot.hasData) return const Center(child: CircularProgressIndicator());
            var activeLogs = logSnapshot.data!.docs;

            if (activeLogs.isEmpty) {
              return Center(child: Text("لا يوجد نشاط حالياً", style: TextStyle(fontSize: 14.sp, color: Colors.grey)));
            }

            return ListView.builder(
              padding: EdgeInsets.all(12.sp),
              itemCount: activeLogs.length,
              itemBuilder: (context, index) {
                var logData = activeLogs[index].data() as Map<String, dynamic>;
                var repFullData = repsInfo[logData['repCode']] ?? {};
                return _buildRepLiveCard(logData, repFullData);
              },
            );
          },
        );
      },
    );
  }

  Widget _buildRepLiveCard(Map<String, dynamic> logData, Map<String, dynamic> repFullData) {
    String repCode = logData['repCode'];
    bool isManager = _userData?['role'] == 'sales_manager';

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('visits')
          .where('repCode', isEqualTo: repCode)
          .where('status', isEqualTo: 'in_progress')
          .snapshots(),
      builder: (context, visitSnapshot) {
        bool inVisit = visitSnapshot.hasData && visitSnapshot.data!.docs.isNotEmpty;
        Map<String, dynamic>? currentVisit;
        if (inVisit) {
          currentVisit = visitSnapshot.data!.docs.first.data() as Map<String, dynamic>;
        }

        return Card(
          margin: EdgeInsets.only(bottom: 15.sp),
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: Column(
            children: [
              Container(
                padding: EdgeInsets.all(12.sp),
                decoration: BoxDecoration(
                  color: inVisit ? kActiveVisitColor : kPrimaryColor,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: Colors.white24,
                      child: Icon(Icons.person, color: Colors.white, size: 18.sp),
                    ),
                    SizedBox(width: 10.sp),
                    Expanded(
                      child: Text(logData['repName'] ?? 'مندوب',
                          style: TextStyle(color: Colors.white, fontSize: 16.sp, fontWeight: FontWeight.bold)),
                    ),
                    IconButton(
                      icon: Icon(Icons.phone_forwarded, color: Colors.white, size: 22.sp),
                      onPressed: () => _makeCall(repFullData['phone']), // اتصال بالمندوب
                      tooltip: "اتصال بالمندوب",
                    ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.all(15.sp),
                child: Column(
                  children: [
                    _buildInfoRow(Icons.qr_code, "كود المندوب", repCode),
                    _buildInfoRow(Icons.access_time_filled, "بدء اليوم", _formatTimestamp(logData['startTime'])),
                    
                    if (inVisit && currentVisit != null) ...[
                      const Divider(),
                      _buildInfoRow(Icons.store, "العميل", currentVisit['customerName'] ?? 'غير معروف', color: kActiveVisitColor),
                    ],

                    // زرار إضافي للمدير للاتصال بالمشرف
                    if (isManager) ...[
                      SizedBox(height: 10.sp),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          minimumSize: Size(double.infinity, 40.sp),
                          side: BorderSide(color: kSidebarColor),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () async {
                          // جلب رقم المشرف من كولكشن المانجر
                          var supDoc = await FirebaseFirestore.instance
                              .collection('managers')
                              .doc(repFullData['supervisorId'])
                              .get();
                          _makeCall(supDoc.data()?['phone']);
                        },
                        icon: Icon(Icons.support_agent, size: 18.sp, color: kSidebarColor),
                        label: Text("اتصال بالمشرف المسؤول", 
                            style: TextStyle(fontSize: 13.sp, color: kSidebarColor, fontWeight: FontWeight.bold)),
                      ),
                    ]
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value, {Color? color}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 5.sp),
      child: Row(
        children: [
          Icon(icon, size: 16.sp, color: color ?? Colors.grey[600]),
          SizedBox(width: 8.sp),
          Text("$label: ", style: TextStyle(fontSize: 13.sp, color: Colors.grey[700])),
          Expanded(child: Text(value, style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold, color: color ?? kSidebarColor))),
        ],
      ),
    );
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return "غير محدد";
    DateTime dt = (timestamp as Timestamp).toDate();
    return "${dt.hour > 12 ? dt.hour - 12 : dt.hour}:${dt.minute.toString().padLeft(2, '0')} ${dt.hour >= 12 ? 'م' : 'ص'}";
  }
}

