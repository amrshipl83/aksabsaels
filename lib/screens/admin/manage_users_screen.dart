import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:sizer/sizer.dart';
import 'performance_dashboard_screen.dart';

class ManageUsersScreen extends StatefulWidget {
  const ManageUsersScreen({super.key});

  @override
  State<ManageUsersScreen> createState() => _ManageUsersScreenState();
}

class _ManageUsersScreenState extends State<ManageUsersScreen> with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _userData;
  TabController? _tabController;
  final Color kPrimaryColor = const Color(0xFF1ABC9C);
  final Color kSidebarColor = const Color(0xFF2F3542);
  List<String> _mySupervisorsIds = []; 

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('userData');
    if (data != null) {
      if (mounted) {
        setState(() {
          _userData = jsonDecode(data);
          int tabCount = (_userData?['role'] == 'sales_manager') ? 2 : 1;
          _tabController = TabController(length: tabCount, vsync: this);
        });

        if (_userData?['role'] == 'sales_manager') {
          _fetchSupervisorsList();
        }
      }
    }
  }

  Future<void> _fetchSupervisorsList() async {
    String myDocId = _userData?['docId'] ?? '';
    var snapshot = await FirebaseFirestore.instance
        .collection('managers')
        .where('managerId', isEqualTo: myDocId)
        .get();

    if (mounted) {
      setState(() {
        _mySupervisorsIds = snapshot.docs.map((d) => d.id).toList();
      });
    }
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_userData == null || _tabController == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    bool isManager = _userData?['role'] == 'sales_manager';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: Text("إدارة الموظفين والأداء",
            style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold)), // تكبير العنوان
        backgroundColor: Colors.white,
        foregroundColor: kSidebarColor,
        elevation: 0.5,
        bottom: TabBar(
          controller: _tabController,
          labelColor: kPrimaryColor,
          unselectedLabelColor: Colors.grey,
          indicatorColor: kPrimaryColor,
          labelStyle: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold), // تكبير خط التبويبات
          tabs: isManager
              ? [const Tab(text: "المشرفين"), const Tab(text: "جميع المندوبين")]
              : [const Tab(text: "مندوبي المبيعات")],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: isManager
            ? [
                _buildUserList('managers', 'managerId'), 
                _buildAllRepsForManager(), 
              ]
            : [
                _buildUserList('salesRep', 'supervisorId')
              ],
      ),
    );
  }

  Widget _buildAllRepsForManager() {
    if (_mySupervisorsIds.isEmpty) {
      return Center(child: Text("لا يوجد مشرفين تابعين لك حالياً", style: TextStyle(fontSize: 14.sp)));
    }
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('salesRep')
          .where('supervisorId', whereIn: _mySupervisorsIds)
          .snapshots(),
      builder: (context, snapshot) => _handleStreamResult(snapshot, 'salesRep'),
    );
  }

  Widget _buildUserList(String collectionName, String filterField) {
    String myDocId = _userData?['docId'] ?? '';
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection(collectionName)
          .where(filterField, isEqualTo: myDocId)
          .snapshots(),
      builder: (context, snapshot) => _handleStreamResult(snapshot, collectionName),
    );
  }

  Widget _handleStreamResult(AsyncSnapshot<QuerySnapshot> snapshot, String collectionName) {
    if (snapshot.hasError) return const Center(child: Text("حدث خطأ في جلب البيانات"));
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const Center(child: CircularProgressIndicator());
    }
    var docs = snapshot.data?.docs ?? [];
    if (docs.isEmpty) return Center(child: Text("لا توجد سجلات حالياً", style: TextStyle(fontSize: 14.sp)));
    
    return ListView.builder(
      padding: EdgeInsets.all(12.sp),
      itemCount: docs.length,
      itemBuilder: (context, index) {
        var data = docs[index].data() as Map<String, dynamic>;
        return _buildUserCard(data, docs[index].id, collectionName);
      },
    );
  }

  Widget _buildUserCard(Map<String, dynamic> data, String docId, String collection) {
    String currentMonth = DateTime.now().toString().substring(0, 7);
    bool hasTarget = data['targets']?[currentMonth] != null;
    String targetType = (collection == 'managers') ? 'sales_supervisor' : 'sales';
    
    // شرط الصلاحية الجديد: 
    // 1. المدير يحدد للمشرفين فقط (managers collection)
    // 2. المشرف يحدد للمناديب فقط (salesRep collection)
    bool canIEditTarget = false;
    if (_userData?['role'] == 'sales_manager' && collection == 'managers') {
      canIEditTarget = true;
    } else if (_userData?['role'] == 'supervisor' && collection == 'salesRep') {
      canIEditTarget = true;
    }

    return Card(
      elevation: 3,
      margin: EdgeInsets.only(bottom: 15.sp),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PerformanceDashboardScreen(
                targetDocId: docId,
                targetType: targetType,
                targetName: data['fullname'] ?? 'غير معروف',
                repCode: data['repCode'],
              ),
            ),
          );
        },
        child: Padding(
          padding: EdgeInsets.all(15.sp),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(data['fullname'] ?? 'بدون اسم',
                          style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold, color: kSidebarColor)),
                      Text(targetType == 'sales_supervisor' ? "مشرف مبيعات" : "مندوب مبيعات",
                          style: TextStyle(fontSize: 11.sp, color: kPrimaryColor, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  Icon(Icons.analytics_outlined, color: kPrimaryColor, size: 25.sp),
                ],
              ),
              const Divider(height: 25),
              _infoRow(Icons.badge_outlined, "الكود:", data['repCode'] ?? 'إدارة'),
              _infoRow(Icons.phone_android, "الهاتف:", data['phone'] ?? '-'),
              const SizedBox(height: 15),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        hasTarget ? Icons.check_circle : Icons.warning_amber_rounded,
                        size: 16.sp,
                        color: hasTarget ? Colors.green : Colors.orange,
                      ),
                      SizedBox(width: 5.sp),
                      Text(hasTarget ? "هدف الشهر محدد" : "لم يحدد هدف",
                          style: TextStyle(fontSize: 12.sp, color: hasTarget ? Colors.green : Colors.orange, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  
                  // تعديل زر الأهداف بناءً على الصلاحيات وقفل التعديل
                  if (canIEditTarget)
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: hasTarget ? Colors.grey[200] : Colors.white,
                        foregroundColor: hasTarget ? Colors.grey : kPrimaryColor,
                        side: BorderSide(color: hasTarget ? Colors.grey : kPrimaryColor),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        padding: EdgeInsets.symmetric(horizontal: 10.sp, vertical: 5.sp),
                      ),
                      onPressed: hasTarget 
                        ? () => _showLockedMessage() // لو فيه هدف، ممنوع التعديل
                        : () => _showTargetModal(docId, data['fullname'], collection),
                      icon: Icon(hasTarget ? Icons.lock_outline : Icons.edit_calendar, size: 14.sp),
                      label: Text(hasTarget ? "تم القفل" : "الأهداف", style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4.sp),
      child: Row(
        children: [
          Icon(icon, size: 15.sp, color: Colors.grey[400]),
          SizedBox(width: 8.sp),
          Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 13.sp)),
          SizedBox(width: 6.sp),
          Expanded(
            child: Text(value,
                style: TextStyle(color: kSidebarColor, fontWeight: FontWeight.bold, fontSize: 13.sp),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  void _showLockedMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("عفواً، لا يمكن تعديل الهدف بعد اعتماده للشهر الحالي."),
        backgroundColor: Colors.redAccent,
      ),
    );
  }

  void _showTargetModal(String docId, String name, String collection) {
    final TextEditingController financialCtrl = TextEditingController();
    final TextEditingController visitsCtrl = TextEditingController();
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text("تحديد هدف: $name", style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("تحذير: لا يمكن تعديل الهدف بعد الحفظ خلال هذا الشهر.", 
              style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold)),
            SizedBox(height: 10.sp),
            TextField(
              controller: financialCtrl,
              decoration: const InputDecoration(
                labelText: "الهدف المالي المطلوب (جنيه)", 
                prefixIcon: Icon(Icons.money),
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number
            ),
            SizedBox(height: 15.sp),
            TextField(
              controller: visitsCtrl,
              decoration: const InputDecoration(
                labelText: "عدد الزيارات المستهدف", 
                prefixIcon: Icon(Icons.location_on),
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text("إلغاء", style: TextStyle(fontSize: 13.sp))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kPrimaryColor, padding: EdgeInsets.symmetric(horizontal: 20.sp)),
            onPressed: () async {
              if (financialCtrl.text.isEmpty || visitsCtrl.text.isEmpty) return;
              
              String month = DateTime.now().toString().substring(0, 7);
              await FirebaseFirestore.instance.collection(collection).doc(docId).update({
                'targets.$month': {
                  'financialTarget': double.tryParse(financialCtrl.text) ?? 0,
                  'visitsTarget': int.tryParse(visitsCtrl.text) ?? 0,
                  'dateSet': FieldValue.serverTimestamp(),
                  'locked': true, // إضافة علامة القفل
                }
              });
              if (mounted) Navigator.pop(context);
            },
            child: Text("اعتماد الهدف", style: TextStyle(color: Colors.white, fontSize: 13.sp, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

