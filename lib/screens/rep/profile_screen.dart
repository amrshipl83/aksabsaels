import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sizer/sizer.dart';
import 'package:url_launcher/url_launcher.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final User? user = FirebaseAuth.instance.currentUser;
  bool _isLoading = false;

  // رابط نموذج حذف البيانات (متطلب جوجل)
  final String deleteDataUrl = "https://docs.google.com/forms/d/e/YOUR_FORM_ID/viewform";

  Future<void> _launchUrl() async {
    final Uri url = Uri.parse(deleteDataUrl);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("تعذر فتح الرابط حالياً")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F6FA),
        appBar: AppBar(
          title: Text("ملفي الشخصي", style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold)),
          centerTitle: true,
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF2F3542),
          elevation: 0.5,
        ),
        body: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('salesRep').doc(user?.uid).snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) return const Center(child: Text("حدث خطأ في جلب البيانات"));
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
            if (!snapshot.hasData || !snapshot.data!.exists) return const Center(child: Text("بيانات المندوب غير موجودة"));

            var data = snapshot.data!.data() as Map<String, dynamic>;

            return SingleChildScrollView(
              padding: EdgeInsets.all(15.sp),
              child: Column(
                children: [
                  // كارت المعلومات الأساسية
                  _buildProfileHeader(data),
                  SizedBox(height: 3.h),
                  
                  // تفاصيل الحساب
                  _buildInfoSection(data),
                  SizedBox(height: 4.h),

                  // أزرار التحكم (خروج وحذف)
                  _buildActionButtons(),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildProfileHeader(Map<String, dynamic> data) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(20.sp),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 35.sp,
            backgroundColor: const Color(0xFF1ABC9C).withOpacity(0.1),
            child: Icon(Icons.person, size: 40.sp, color: const Color(0xFF1ABC9C)),
          ),
          SizedBox(height: 15.sp),
          Text(data['fullname'] ?? 'غير مسجل',
              style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold, color: const Color(0xFF2F3542))),
          SizedBox(height: 5.sp),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 4.sp),
            decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
            child: Text(data['repCode'] ?? '',
                style: TextStyle(fontSize: 12.sp, color: Colors.green[700], fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoSection(Map<String, dynamic> data) {
    return Container(
      padding: EdgeInsets.all(15.sp),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Column(
        children: [
          _buildInfoRow(Icons.phone_android, "رقم الهاتف", data['phone'] ?? 'لا يوجد'),
          const Divider(),
          _buildInfoRow(Icons.email_outlined, "البريد الإلكتروني", data['email'] ?? 'لا يوجد'),
          const Divider(),
          _buildInfoRow(Icons.location_on_outlined, "العنوان", data['address'] ?? 'غير محدد'),
          const Divider(),
          _buildInfoRow(Icons.calendar_month, "تاريخ التفعيل", _formatTimestamp(data['approvedAt'])),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8.sp),
      child: Row(
        children: [
          Icon(icon, size: 18.sp, color: Colors.grey[600]),
          SizedBox(width: 12.sp),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 11.sp, color: Colors.grey)),
              Text(value, style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.bold, color: const Color(0xFF2F3542))),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        // زر تسجيل الخروج
        ElevatedButton.icon(
          onPressed: () => FirebaseAuth.instance.signOut(),
          icon: const Icon(Icons.logout),
          label: Text("تسجيل الخروج", style: TextStyle(fontSize: 14.sp)),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2F3542),
            foregroundColor: Colors.white,
            minimumSize: Size(double.infinity, 45.sp),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          ),
        ),
        SizedBox(height: 2.h),
        
        // زر حذف الحساب (متوافق مع جوجل)
        TextButton.icon(
          onPressed: _launchUrl,
          icon: const Icon(Icons.delete_forever, color: Colors.red),
          label: Text("طلب حذف الحساب والبيانات", 
              style: TextStyle(fontSize: 12.sp, color: Colors.red, decoration: TextDecoration.underline)),
        ),
        Text("طبقاً لسياسات جوجل، يمكنك طلب حذف بياناتك نهائياً.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 9.sp, color: Colors.grey)),
      ],
    );
  }

  String _formatTimestamp(dynamic ts) {
    if (ts == null) return "غير محدد";
    DateTime dt = (ts as Timestamp).toDate();
    return "${dt.day}/${dt.month}/${dt.year}";
  }
}

