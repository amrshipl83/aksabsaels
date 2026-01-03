import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sizer/sizer.dart';
import 'dart:convert';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _userData;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('userData');
    if (data != null) {
      setState(() => _userData = jsonDecode(data));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      appBar: AppBar(
        title: Text("الملف الشخصي", style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF2F3542),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(5.w),
        child: Column(
          children: [
            // قسم البيانات الأساسية
            _buildProfileHeader(),
            SizedBox(height: 4.h),
            
            // قسم الخصوصية (شرط جوجل)
            _buildSectionTitle("الأمان والخصوصية"),
            _buildMenuCard(Icons.privacy_tip_outlined, "سياسة الخصوصية", () {
               // هنا تضع رابط الويب الخاص بالسياسة
            }),
            
            // قسم حذف الحساب (شرط جوجل الإجباري)
            _buildMenuCard(Icons.delete_forever_outlined, "حذف الحساب نهائياً", () {
              _showDeleteDialog();
            }, color: Colors.redAccent),

            SizedBox(height: 5.h),
            Text("إصدار التطبيق 1.0.0", style: TextStyle(color: Colors.grey, fontSize: 10.sp)),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileHeader() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(6.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 20)],
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 12.w,
            backgroundColor: const Color(0xFF1ABC9C).withOpacity(0.1),
            child: Icon(Icons.person, size: 15.w, color: const Color(0xFF1ABC9C)),
          ),
          SizedBox(height: 2.h),
          Text(_userData?['fullname'] ?? "جاري التحميل...", 
            style: TextStyle(fontSize: 17.sp, fontWeight: FontWeight.w900)),
          Text(_userData?['role'] == 'sales_manager' ? "مدير مبيعات" : "مشرف مبيعات", 
            style: TextStyle(fontSize: 12.sp, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 1.5.h, horizontal: 2.w),
      child: Align(
        alignment: Alignment.centerRight,
        child: Text(title, style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
      ),
    );
  }

  Widget _buildMenuCard(IconData icon, String title, VoidCallback onTap, {Color? color}) {
    return Container(
      margin: EdgeInsets.only(bottom: 1.5.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10)],
      ),
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: color ?? const Color(0xFF1ABC9C)),
        title: Text(title, style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600, color: color)),
        trailing: Icon(Icons.arrow_back_ios_new_rounded, size: 12.sp, color: Colors.grey),
      ),
    );
  }

  void _showDeleteDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("حذف الحساب"),
        content: const Text("هل أنت متأكد من رغبتك في حذف الحساب؟ سيتم مسح جميع بياناتك نهائياً من النظام وفقاً لسياسات جوجل."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("إلغاء")),
          TextButton(
            onPressed: () {
              // هنا نضع كود المسح الفعلي من Firebase
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("تم إرسال طلب حذف الحساب")));
            }, 
            child: const Text("تأكيد الحذف", style: TextStyle(color: Colors.red))
          ),
        ],
      ),
    );
  }
}

