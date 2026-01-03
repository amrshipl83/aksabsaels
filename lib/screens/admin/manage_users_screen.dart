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
  List<String> _mySupervisorsIds = []; // لتخزين معرفات المشرفين التابعين للمدير

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
        
        // إذا كان مديرًا، نحتاج جلب قائمة المشرفين التابعين له مسبقاً
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
            style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: kSidebarColor,
        elevation: 0.5,
        bottom: TabBar(
          controller: _tabController,
          labelColor: kPrimaryColor,
          unselectedLabelColor: Colors.grey,
          indicatorColor: kPrimaryColor,
          tabs: isManager
              ? [const Tab(text: "المشرفين"), const Tab(text: "جميع المندوبين")]
              : [const Tab(text: "مندوبي المبيعات")],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: isManager
            ? [
                _buildUserList('managers', 'managerId'), // تبويب المشرفين
                _buildAllRepsForManager(), // تبويب كل المندوبين (الحل الجديد)
              ]
            : [
                _buildUserList('salesRep', 'supervisorId') // المشرف يرى مناديبه
              ],
      ),
    );
  }

  // دالة خاصة للمدير لجلب كل المندوبين التابعين لمشرفيه
  Widget _buildAllRepsForManager() {
    if (_mySupervisorsIds.isEmpty) {
      return const Center(child: Text("لا يوجد مشرفين تابعين لك حالياً"));
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

  // توحيد معالجة نتائج الـ Stream
  Widget _handleStreamResult(AsyncSnapshot<QuerySnapshot> snapshot, String collectionName) {
    if (snapshot.hasError) return const Center(child: Text("حدث خطأ في جلب البيانات"));
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const Center(child: CircularProgressIndicator());
    }

    var docs = snapshot.data?.docs ?? [];
    if (docs.isEmpty) return const Center(child: Text("لا توجد سجلات حالياً"));

    return ListView.builder(
      padding: EdgeInsets.all(10.sp),
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

    return Card(
      elevation: 2,
      margin: EdgeInsets.only(bottom: 12.sp),
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
          padding: EdgeInsets.all(12.sp),
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
                          style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold, color: kSidebarColor)),
                      Text(targetType == 'sales_supervisor' ? "مشرف مبيعات" : "مندوب مبيعات",
                          style: TextStyle(fontSize: 9.sp, color: kPrimaryColor)),
                    ],
                  ),
                  Icon(Icons.analytics_outlined, color: kPrimaryColor, size: 22.sp),
                ],
              ),
              const Divider(height: 20),
              _infoRow(Icons.badge_outlined, "الكود:", data['repCode'] ?? 'إدارة'),
              _infoRow(Icons.phone_android, "الهاتف:", data['phone'] ?? '-'),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        hasTarget ? Icons.check_circle : Icons.warning_amber_rounded,
                        size: 14.sp,
                        color: hasTarget ? Colors.green : Colors.orange,
                      ),
                      SizedBox(width: 4.sp),
                      Text(hasTarget ? "هدف الشهر محدد" : "لم يحدد هدف",
                          style: TextStyle(fontSize: 10.sp, color: hasTarget ? Colors.green : Colors.orange, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: kPrimaryColor,
                      side: BorderSide(color: kPrimaryColor),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: EdgeInsets.symmetric(horizontal: 8.sp),
                    ),
                    onPressed: () => _showTargetModal(docId, data['fullname'], collection),
                    icon: Icon(Icons.edit_calendar, size: 12.sp),
                    label: Text("الأهداف", style: TextStyle(fontSize: 10.sp)),
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
      padding: EdgeInsets.symmetric(vertical: 2.sp),
      child: Row(
        children: [
          Icon(icon, size: 13.sp, color: Colors.grey[400]),
          SizedBox(width: 6.sp),
          Text(label, style: TextStyle(color: Colors.grey[500], fontSize: 11.sp)),
          SizedBox(width: 4.sp),
          Expanded(
            child: Text(value,
              style: TextStyle(color: kSidebarColor, fontWeight: FontWeight.w500, fontSize: 11.sp),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  void _showTargetModal(String docId, String name, String collection) {
    final TextEditingController financialCtrl = TextEditingController();
    final TextEditingController visitsCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text("تحديد هدف: $name", style: TextStyle(fontSize: 14.sp)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: financialCtrl, 
              decoration: const InputDecoration(labelText: "الهدف المالي المطلوب (جنيه)", prefixIcon: Icon(Icons.money)), 
              keyboardType: TextInputType.number
            ),
            SizedBox(height: 10.sp),
            TextField(
              controller: visitsCtrl, 
              decoration: const InputDecoration(labelText: "عدد الزيارات المستهدف", prefixIcon: Icon(Icons.location_on)), 
              keyboardType: TextInputType.number
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("إلغاء")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kPrimaryColor),
            onPressed: () async {
              String month = DateTime.now().toString().substring(0, 7);
              await FirebaseFirestore.instance.collection(collection).doc(docId).update({
                'targets.$month': {
                  'financialTarget': double.tryParse(financialCtrl.text) ?? 0,
                  'visitsTarget': int.tryParse(visitsCtrl.text) ?? 0,
                  'dateSet': FieldValue.serverTimestamp(),
                }
              });
              if (mounted) Navigator.pop(context);
            },
            child: const Text("حفظ الهدف", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

