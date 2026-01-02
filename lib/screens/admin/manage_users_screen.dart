import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:sizer/sizer.dart';

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

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('userData');
    if (data != null) {
      setState(() {
        _userData = jsonDecode(data);
        // تحديد عدد التبويبات بناءً على الدور
        int tabCount = (_userData?['role'] == 'sales_manager') ? 2 : 1;
        _tabController = TabController(length: tabCount, vsync: this);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_userData == null || _tabController == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    bool isManager = _userData?['role'] == 'sales_manager';

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F6FA),
        appBar: AppBar(
          title: Text("إدارة الموظفين", style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold)),
          backgroundColor: Colors.white,
          foregroundColor: kSidebarColor,
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
            ? [_buildUserList('managers', 'managerId'), _buildUserList('salesRep', 'managerId')]
            : [_buildUserList('salesRep', 'supervisorId')],
        ),
      ),
    );
  }

  Widget _buildUserList(String collectionName, String filterField) {
    return StreamBuilder<QuerySnapshot>(
      // البحث المباشر عن المعرف (ManagerId أو SupervisorId) بدلاً من المصفوفة
      stream: FirebaseFirestore.instance
          .collection(collectionName)
          .where(filterField, isEqualTo: _userData?['uid'])
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text("حدث خطأ ما"));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        var docs = snapshot.data!.docs;
        if (docs.isEmpty) return const Center(child: Text("لا توجد بيانات للعرض"));

        return ListView.builder(
          padding: EdgeInsets.all(10.sp),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            var data = docs[index].data() as Map<String, dynamic>;
            return _buildUserCard(data, docs[index].id, collectionName);
          },
        );
      },
    );
  }

  Widget _buildUserCard(Map<String, dynamic> data, String docId, String collection) {
    String currentMonth = DateTime.now().toString().substring(0, 7); // 2026-01
    bool hasTarget = data['targets']?[currentMonth] != null;

    return Card(
      elevation: 3,
      margin: EdgeInsets.only(bottom: 12.sp),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(12.sp),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(data['fullname'] ?? 'بدون اسم', 
                  style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.bold, color: kSidebarColor)),
                Icon(Icons.person_pin, color: kPrimaryColor),
              ],
            ),
            const Divider(),
            _infoRow(Icons.email, "البريد:", data['email'] ?? '-'),
            _infoRow(Icons.badge, "الكود:", data['repCode'] ?? 'مشرف'),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(hasTarget ? "🎯 تم تعيين الهدف" : "⚠️ لم يتم تعيين هدف",
                  style: TextStyle(fontSize: 12.sp, color: hasTarget ? Colors.green : Colors.orange)),
                ElevatedButton(
                  style: ElevatedButton.fromStyleFrom(backgroundColor: kPrimaryColor),
                  onPressed: () => _showTargetModal(docId, data['fullname'], collection),
                  child: Text("تعيين هدف", style: TextStyle(color: Colors.white, fontSize: 11.sp)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 2.sp),
      child: Row(
        children: [
          Icon(icon, size: 14.sp, color: Colors.grey),
          SizedBox(width: 5.sp),
          Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 12.sp)),
          SizedBox(width: 5.sp),
          Text(value, style: TextStyle(color: kSidebarColor, fontWeight: FontWeight.w500, fontSize: 12.sp)),
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
        title: Text("تحديد هدف $name"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: financialCtrl, decoration: const InputDecoration(labelText: "الهدف المالي (جنيه)"), keyboardType: TextInputType.number),
            TextField(controller: visitsCtrl, decoration: const InputDecoration(labelText: "عدد الزيارات المستهدف"), keyboardType: TextInputType.number),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("إلغاء")),
          ElevatedButton(
            onPressed: () async {
              String month = DateTime.now().toString().substring(0, 7);
              await FirebaseFirestore.instance.collection(collection).doc(docId).update({
                'targets.$month': {
                  'financialTarget': double.tryParse(financialCtrl.text) ?? 0,
                  'visitsTarget': int.tryParse(visitsCtrl.text) ?? 0,
                  'dateSet': DateTime.now().toIso8601String(),
                }
              });
              Navigator.pop(context);
            },
            child: const Text("حفظ"),
          ),
        ],
      ),
    );
  }
}

