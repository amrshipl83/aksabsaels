import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:sizer/sizer.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class LiveMonitoringScreen extends StatefulWidget {
  const LiveMonitoringScreen({super.key});

  @override
  State<LiveMonitoringScreen> createState() => _LiveMonitoringScreenState();
}

class _LiveMonitoringScreenState extends State<LiveMonitoringScreen> {
  Map<String, dynamic>? _userData;
  bool _isLoading = true;
  bool _isMapView = false;
  String? _selectedRepCode; // المندوب المختار لعرض مساره

  final Color kPrimaryColor = const Color(0xFF1ABC9C);
  final Color kActiveVisitColor = const Color(0xFF3498DB);
  final Color kSidebarColor = const Color(0xFF2F3542);
  final Color kStartPointColor = Colors.orange;

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
          title: Text("متابعة المندوبين لايف", 
            style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold)),
          backgroundColor: Colors.white,
          foregroundColor: kSidebarColor,
          elevation: 0.5,
          centerTitle: true,
          actions: [
            IconButton(
              icon: Icon(_isMapView ? Icons.list_alt : Icons.map_outlined, size: 22.sp),
              onPressed: () => setState(() => _isMapView = !_isMapView),
              tooltip: _isMapView ? "عرض القائمة" : "عرض الخريطة",
            )
          ],
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
          if (supervisorIds.isEmpty) return Center(child: Text("لا يوجد مشرفين تابعين لك", style: TextStyle(fontSize: 15.sp)));
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
        if (repsDocs.isEmpty) return Center(child: Text("لا يوجد مندوبين مسجلين", style: TextStyle(fontSize: 15.sp)));

        Map<String, dynamic> repsFullData = {for (var doc in repsDocs) doc['repCode']: doc.data()};
        List<String> repCodes = repsFullData.keys.toList();

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('daily_logs').where('status', isEqualTo: 'open').where('repCode', whereIn: repCodes).snapshots(),
          builder: (context, logSnapshot) {
            if (!logSnapshot.hasData) return const Center(child: CircularProgressIndicator());
            var activeLogs = logSnapshot.data!.docs;

            if (activeLogs.isEmpty) return Center(child: Text("لا يوجد مندوبون نشطون حالياً", style: TextStyle(fontSize: 14.sp, color: Colors.grey)));

            if (_isMapView) {
              return _buildGoogleMapView(activeLogs, repsFullData);
            }

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

  Widget _buildGoogleMapView(List<QueryDocumentSnapshot> activeLogs, Map<String, dynamic> repsFullData) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('visits').where('status', isEqualTo: 'in_progress').snapshots(),
      builder: (context, visitSnap) {
        Set<Marker> markers = {};
        Set<Polyline> polylines = {};
        Map<String, dynamic> activeVisitsByRep = {};

        if (visitSnap.hasData) {
          for (var v in visitSnap.data!.docs) {
            activeVisitsByRep[v['repCode']] = v.data();
          }
        }

        for (var log in activeLogs) {
          var logData = log.data() as Map<String, dynamic>;
          String repCode = logData['repCode']?.toString() ?? "";
          var repData = repsFullData[repCode] ?? {};

          // إحداثيات بداية اليوم (من السجل)
          var startLoc = logData['startLocation'];
          // إحداثيات الزيارة الحالية (من الزيارات)
          var currentVisit = activeVisitsByRep[repCode];
          var currentLoc = currentVisit != null ? currentVisit['location'] : null;

          LatLng? startLatLng = _parseLatLng(startLoc);
          LatLng? currentLatLng = _parseLatLng(currentLoc);
          LatLng? displayPos = currentLatLng ?? startLatLng;

          if (displayPos != null) {
            bool hasVisit = activeVisitsByRep.containsKey(repCode);
            
            markers.add(
              Marker(
                markerId: MarkerId("rep_$repCode"),
                position: displayPos,
                icon: BitmapDescriptor.defaultMarkerWithHue(
                  hasVisit ? BitmapDescriptor.hueAzure : BitmapDescriptor.hueYellow
                ),
                onTap: () => setState(() => _selectedRepCode = repCode),
                infoWindow: InfoWindow(
                  title: logData['repName'] ?? 'مندوب',
                  snippet: hasVisit 
                      ? "في زيارة: ${activeVisitsByRep[repCode]['customerName']}\nت: ${repData['phone']}"
                      : "متصل - ت: ${repData['phone']}",
                  onTap: () => _makeCall(repData['phone']),
                ),
              ),
            );

            // رسم المسار فقط للمندوب المختار لعدم تداخل الخطوط
            if (_selectedRepCode == repCode && startLatLng != null && currentLatLng != null) {
              polylines.add(
                Polyline(
                  polylineId: PolylineId("route_$repCode"),
                  points: [startLatLng, currentLatLng],
                  color: kActiveVisitColor,
                  width: 4,
                  patterns: [PatternItem.dash(20), PatternItem.gap(10)], // خط منقط احترافي
                ),
              );
              
              // ماركر لنقطة البداية لتوضيح المسار
              markers.add(
                Marker(
                  markerId: MarkerId("start_$repCode"),
                  position: startLatLng,
                  icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
                  alpha: 0.6,
                  infoWindow: const InfoWindow(title: "نقطة انطلاق المندوب"),
                ),
              );
            }
          }
        }

        return GoogleMap(
          key: ValueKey("${markers.length}_$_selectedRepCode"),
          initialCameraPosition: const CameraPosition(target: LatLng(31.2001, 29.9187), zoom: 12),
          markers: markers,
          polylines: polylines,
          myLocationButtonEnabled: true,
          myLocationEnabled: true,
          onTap: (_) => setState(() => _selectedRepCode = null), // إلغاء الاختيار عند الضغط على الخريطة
        );
      },
    );
  }

  LatLng? _parseLatLng(dynamic loc) {
    if (loc == null || loc is! Map) return null;
    try {
      double? lat = double.tryParse(loc['lat'].toString());
      double? lng = double.tryParse(loc['lng'].toString());
      if (lat != null && lng != null) return LatLng(lat, lng);
    } catch (e) {
      return null;
    }
    return null;
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
                padding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 10.sp),
                decoration: BoxDecoration(
                  color: inVisit ? kActiveVisitColor : kPrimaryColor,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
                ),
                child: Row(
                  children: [
                    IconButton(icon: Icon(Icons.phone_in_talk, color: Colors.white, size: 20.sp), onPressed: () => _makeCall(repDocData['phone'])),
                    Expanded(child: Text(logData['repName'] ?? 'مندوب', style: TextStyle(color: Colors.white, fontSize: 15.sp, fontWeight: FontWeight.bold))),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 10.sp, vertical: 4.sp),
                      decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(5)),
                      child: Text(inVisit ? "في زيارة" : "متصل", style: TextStyle(color: Colors.white, fontSize: 10.sp)),
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
                              Icon(Icons.support_agent, size: 16.sp, color: Colors.orange[700]),
                              SizedBox(width: 5.sp),
                              Text("المشرف: ${repDocData['supervisorName'] ?? 'غير محدد'}", style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          TextButton.icon(
                            onPressed: () async {
                              var sup = await FirebaseFirestore.instance.collection('managers').doc(repDocData['supervisorId']).get();
                              _makeCall(sup.data()?['phone']);
                            },
                            icon: Icon(Icons.phone, size: 14.sp),
                            label: Text("اتصال", style: TextStyle(fontSize: 12.sp)),
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
      padding: EdgeInsets.symmetric(vertical: 4.sp),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: isSmall ? 13.sp : 15.sp, color: color ?? Colors.grey[600]),
          SizedBox(width: 8.sp),
          Text("$label: ", style: TextStyle(fontSize: isSmall ? 11.sp : 12.sp, color: Colors.grey[700])),
          Expanded(child: Text(value, style: TextStyle(fontSize: isSmall ? 11.sp : 13.sp, fontWeight: isSmall ? FontWeight.normal : FontWeight.bold, color: color ?? kSidebarColor))),
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

