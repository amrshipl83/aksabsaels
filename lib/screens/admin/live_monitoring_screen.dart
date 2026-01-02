import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:sizer/sizer.dart';

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
      setState(() {
        _userData = jsonDecode(data);
        _isLoading = false;
      });
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
          title: Text("متابعة المندوبين لايف", style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold)),
          backgroundColor: Colors.white,
          foregroundColor: kSidebarColor,
          elevation: 0.5,
        ),
        body: _buildLiveStream(),
      ),
    );
  }

  Widget _buildLiveStream() {
    String role = _userData?['role'] ?? '';
    String myDocId = _userData?['docId'] ?? ''; 

    if (role == 'sales_supervisor') {
      // المشرف يرى مناديبه مباشرة
      return _buildRepsWatcher(
        FirebaseFirestore.instance.collection('salesRep')
            .where('supervisorId', isEqualTo: myDocId)
      );
    } else if (role == 'sales_manager') {
      // المدير يرى مناديب المشرفين التابعين له
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
            return Center(child: Text("لا يوجد مشرفين تابعين لك حالياً", style: TextStyle(fontSize: 14.sp)));
          }

          // جلب المناديب التابعين لهؤلاء المشرفين
          return _buildRepsWatcher(
            FirebaseFirestore.instance.collection('salesRep')
                .where('supervisorId', whereIn: supervisorIds)
          );
        },
      );
    }
    return const Center(child: Text("غير مسموح لهذا الدور بالعرض"));
  }

  // دالة وسيطة لجلب المناديب ثم جلب سجلاتهم اليومية النشطة
  Widget _buildRepsWatcher(Query repsQuery) {
    return StreamBuilder<QuerySnapshot>(
      stream: repsQuery.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const Center(child: Text("حدث خطأ في جلب المندوبين"));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        var repsDocs = snapshot.data!.docs;
        if (repsDocs.isEmpty) {
          return Center(child: Text("لا يوجد مندوبين في فريقك", style: TextStyle(fontSize: 14.sp)));
        }

        List<String> repCodes = repsDocs.map((doc) => doc['repCode'] as String).toList();

        // جلب سجلات اليوم المفتوحة فقط لهؤلاء المناديب
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('daily_logs')
              .where('status', isEqualTo: 'open')
              .where('repCode', whereIn: repCodes)
              .snapshots(),
          builder: (context, logSnapshot) {
            if (logSnapshot.hasError) return const Center(child: Text("خطأ في جلب حالة العمل"));
            if (!logSnapshot.hasData) return const Center(child: CircularProgressIndicator());

            var activeLogs = logSnapshot.data!.docs;
            if (activeLogs.isEmpty) {
              return Center(child: Text("لا يوجد مندوبون في يوم عمل نشط حالياً",
                  style: TextStyle(fontSize: 14.sp, color: Colors.grey)));
            }

            return ListView.builder(
              padding: EdgeInsets.all(12.sp),
              itemCount: activeLogs.length,
              itemBuilder: (context, index) {
                var logData = activeLogs[index].data() as Map<String, dynamic>;
                return _buildRepLiveCard(logData);
              },
            );
          },
        );
      },
    );
  }

  Widget _buildRepLiveCard(Map<String, dynamic> logData) {
    String repCode = logData['repCode'];

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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          elevation: 3,
          child: Column(
            children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: 15.sp, vertical: 10.sp),
                decoration: BoxDecoration(
                  color: inVisit ? kActiveVisitColor : kPrimaryColor,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(logData['repName'] ?? 'مندوب',
                        style: TextStyle(color: Colors.white, fontSize: 16.sp, fontWeight: FontWeight.bold)),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 10.sp, vertical: 4.sp),
                      decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(5)),
                      child: Text(inVisit ? "في زيارة حالياً" : "يوم عمل نشط",
                        style: TextStyle(color: Colors.white, fontSize: 11.sp, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.all(15.sp),
                child: Column(
                  children: [
                    _buildInfoRow(Icons.qr_code, "كود المندوب", repCode),
                    _buildInfoRow(Icons.access_time, "بدء اليوم", _formatTimestamp(logData['startTime'])),
                    if (inVisit && currentVisit != null) ...[
                      const Divider(),
                      _buildInfoRow(Icons.store, "العميل الحالي", currentVisit['customerName'] ?? 'غير معروف', color: kActiveVisitColor),
                      _buildInfoRow(Icons.timer, "بدء الزيارة", _formatTimestamp(currentVisit['startTime']), color: kActiveVisitColor),
                    ],
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
      padding: EdgeInsets.symmetric(vertical: 4.sp),
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
    try {
      DateTime dt = (timestamp as Timestamp).toDate();
      return "${dt.hour}:${dt.minute.toString().padLeft(2, '0')}";
    } catch (e) {
      return "تنسيق غير صحيح";
    }
  }
}

