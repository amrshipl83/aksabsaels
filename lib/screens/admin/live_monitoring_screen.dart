import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:sizer/sizer.dart';
import 'package:url_launcher/url_launcher.dart';

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

  Future<void> _makeCall(String? phone) async {
    if (phone == null || phone.isEmpty) return;
    final Uri url = Uri.parse('tel:$phone');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
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
          title: Text("متابعة المندوبين لايف", style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
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
      return _buildRepsWatcher(FirebaseFirestore.instance.collection('salesRep').where('supervisorId', isEqualTo: myDocId));
    } else if (role == 'sales_manager') {
      return StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('managers').where('managerId', isEqualTo: myDocId).where('role', isEqualTo: 'sales_supervisor').snapshots(),
        builder: (context, supervisorSnap) {
          if (!supervisorSnap.hasData) return const Center(child: CircularProgressIndicator());
          List<String> supervisorIds = supervisorSnap.data!.docs.map((doc) => doc.id).toList();
          if (supervisorIds.isEmpty) return Center(child: Text("لا يوجد مشرفين تابعين لك", style: TextStyle(fontSize: 14.sp)));
          return _buildRepsWatcher(FirebaseFirestore.instance.collection('salesRep').where('supervisorId', whereIn: supervisorIds));
        },
      );
    }
    return const Center(child: Text("غير مسموح بالعرض"));
  }

  Widget _buildRepsWatcher(Query repsQuery) {
    return StreamBuilder<QuerySnapshot>(
      stream: repsQuery.snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        var repsDocs = snapshot.data!.docs;
        if (repsDocs.isEmpty) return Center(child: Text("لا يوجد مندوبين", style: TextStyle(fontSize: 14.sp)));

        Map<String, dynamic> repsFullData = {for (var doc in repsDocs) doc['repCode']: doc.data()};
        List<String> repCodes = repsFullData.keys.toList();

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('daily_logs').where('status', isEqualTo: 'open').where('repCode', whereIn: repCodes).snapshots(),
          builder: (context, logSnapshot) {
            if (!logSnapshot.hasData) return const Center(child: CircularProgressIndicator());
            var activeLogs = logSnapshot.data!.docs;
            if (activeLogs.isEmpty) return Center(child: Text("لا يوجد مندوبون نشطون حالياً", style: TextStyle(fontSize: 13.sp, color: Colors.grey)));

            return ListView.builder(
              padding: EdgeInsets.all(12.sp),
              itemCount: activeLogs.length,
              itemBuilder: (context, index) {
                var logData = activeLogs[index].data() as Map<String, dynamic>;
                return _buildRepLiveCard(logData, repsFullData[logData['repCode']] ?? {});
              },
            );
          },
        );
      },
    );
  }

  Widget _buildRepLiveCard(Map<String, dynamic> logData, Map<String, dynamic> repDocData) {
    String repCode = logData['repCode'];
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('visits').where('repCode', isEqualTo: repCode).where('status', isEqualTo: 'in_progress').snapshots(),
      builder: (context, visitSnapshot) {
        bool inVisit = visitSnapshot.hasData && visitSnapshot.data!.docs.isNotEmpty;
        Map<String, dynamic>? currentVisit = inVisit ? visitSnapshot.data!.docs.first.data() as Map<String, dynamic> : null;

        return Card(
          margin: EdgeInsets.only(bottom: 12.sp),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          elevation: 3,
          child: Column(
            children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 8.sp),
                decoration: BoxDecoration(
                  color: inVisit ? kActiveVisitColor : kPrimaryColor,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
                ),
                child: Row(
                  children: [
                    IconButton(icon: Icon(Icons.phone_in_talk, color: Colors.white, size: 18.sp), onPressed: () => _makeCall(repDocData['phone'])),
                    Expanded(child: Text(logData['repName'] ?? 'مندوب', style: TextStyle(color: Colors.white, fontSize: 14.sp, fontWeight: FontWeight.bold))),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 8.sp, vertical: 3.sp),
                      decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(5)),
                      child: Text(inVisit ? "في زيارة" : "متصل", style: TextStyle(color: Colors.white, fontSize: 9.sp)),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.all(12.sp),
                child: Column(
                  children: [
                    _buildInfoRow(Icons.qr_code, "الكود", repCode),
                    _buildInfoRow(Icons.access_time, "البداية", _formatTimestamp(logData['startTime'])),
                    if (inVisit && currentVisit != null) ...[
                      const Divider(),
                      _buildInfoRow(Icons.store, "العميل", currentVisit['customerName'] ?? 'غير معروف', color: kActiveVisitColor),
                      _buildInfoRow(Icons.location_on_outlined, "العنوان", currentVisit['customerAddress'] ?? 'عنوان غير مسجل', color: Colors.grey[600], isSmall: true),
                    ],
                    if (_userData?['role'] == 'sales_manager') ...[
                      const Divider(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.support_agent, size: 14.sp, color: Colors.orange[700]),
                              SizedBox(width: 5.sp),
                              Text("المشرف: ${repDocData['supervisorName'] ?? 'غير محدد'}", style: TextStyle(fontSize: 11.sp, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          TextButton.icon(
                            onPressed: () async {
                              var sup = await FirebaseFirestore.instance.collection('managers').doc(repDocData['supervisorId']).get();
                              _makeCall(sup.data()?['phone']);
                            },
                            icon: Icon(Icons.phone, size: 12.sp),
                            label: const Text("اتصال"),
                            style: TextButton.styleFrom(foregroundColor: Colors.orange[700], padding: EdgeInsets.zero),
                          )
                        ],
                      )
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

  Widget _buildInfoRow(IconData icon, String label, String value, {Color? color, bool isSmall = false}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 3.sp),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: isSmall ? 12.sp : 14.sp, color: color ?? Colors.grey[600]),
          SizedBox(width: 8.sp),
          Text("$label: ", style: TextStyle(fontSize: isSmall ? 10.sp : 11.sp, color: Colors.grey[700])),
          Expanded(child: Text(value, style: TextStyle(fontSize: isSmall ? 10.sp : 12.sp, fontWeight: isSmall ? FontWeight.normal : FontWeight.bold, color: color ?? kSidebarColor))),
        ],
      ),
    );
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return "--:--";
    DateTime dt = (timestamp as Timestamp).toDate();
    return "${dt.hour > 12 ? dt.hour - 12 : dt.hour}:${dt.minute.toString().padLeft(2, '0')} ${dt.hour >= 12 ? 'م' : 'ص'}";
  }
}

