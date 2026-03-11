import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class AddNewCustomerScreen extends StatefulWidget {
  const AddNewCustomerScreen({super.key});

  @override
  State<AddNewCustomerScreen> createState() => _AddNewCustomerScreenState();
}

class _AddNewCustomerScreenState extends State<AddNewCustomerScreen> {
  final _formKey = GlobalKey<FormState>();
  
  // الكنترولرز مطابقة للتطبيق الأساسي لضمان نفس بنية البيانات
  final _nameController = TextEditingController();      // سيتم تخزينه في fullname
  final _ownerNameController = TextEditingController(); // اسم صاحب النشاط
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _addressController = TextEditingController();
  
  bool _isLoading = false;
  Position? _currentPosition;
  Map<String, dynamic>? _repData;

  @override
  void initState() {
    super.initState();
    _loadRepData();
    // جلب الموقع فوراً بصمت لاعتباره مأخوذ مسبقاً عند بداية اليوم
    _determinePosition(); 
  }

  Future<void> _loadRepData() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('userData');
    if (data != null) {
      setState(() => _repData = jsonDecode(data));
    }
  }

  Future<void> _determinePosition() async {
    setState(() => _isLoading = true);
    try {
      // جلب الإحداثيات مباشرة
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // تحويل الإحداثيات لعنوان نصي لملء حقل العنوان تلقائياً
      List<Placemark> placemarks = await placemarkFromCoordinates(position.latitude, position.longitude);
      String address = "موقع غير محدد";
      if (placemarks.isNotEmpty) {
        Placemark p = placemarks[0];
        address = "${p.street}, ${p.locality}, ${p.subAdministrativeArea}";
      }

      setState(() {
        _currentPosition = position;
        _addressController.text = address;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showSnackBar("⚠️ جاري استخدام نظام الموقع التقريبي: $e");
    }
  }

  void _showSnackBar(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg, style: const TextStyle(fontFamily: 'Cairo')))
      );
    }
  }

  Future<void> _registerCustomer() async {
    // التأكد من ملء البيانات ووجود إحداثيات (اللقطة الجغرافية)
    if (!_formKey.currentState!.validate() || _currentPosition == null) {
      _showSnackBar("❌ يرجى التأكد من البيانات ولقطة الموقع");
      return;
    }

    setState(() => _isLoading = true);
    try {
      String phone = _phoneController.text.trim();
      String smartEmail = "$phone@aksab.com"; // المطابقة مع التطبيق الأساسي
      String password = _passwordController.text.trim();

      // 1. إنشاء الحساب في Firebase Authentication
      UserCredential userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: smartEmail, password: password);

      String userId = userCredential.user!.uid;

      // 2. تجهيز ماب البيانات (نسخة طبق الأصل من الأساسي + بيانات المندوب)
      final Map<String, dynamic> userData = {
        'uid': userId,
        'fullname': _nameController.text.trim(),   // اسم المحل
        'ownerName': _ownerNameController.text.trim(), // اسم صاحب النشاط
        'email': smartEmail,
        'phone': phone,
        'address': _addressController.text.trim(),
        'location': {
          'lat': _currentPosition!.latitude,
          'lng': _currentPosition!.longitude,
        },
        'role': "buyer",       // تحديد الروب كـ تاجر
        'country': "egypt",
        'createdAt': FieldValue.serverTimestamp(),
        'isVerified': true,    // تفعيل فوري لأن المندوب سجل العميل ميدانياً
        'isNewUser': true,     // لضمان استحقاق نقاط الترحيب
        'status': 'active',    // الحالة نشط
        // إضافة معرفات المندوب لربط العميل به
        'repCode': _repData?['repCode'],
        'repName': _repData?['fullname'],
      };

      // 3. الحفظ في كولكشن users (نفس مسار الـ Buyer في التطبيق الأساسي)
      await FirebaseFirestore.instance.collection('users').doc(userId).set(userData);

      if (mounted) {
        _showSuccessDialog();
      }
    } catch (e) {
      _showSnackBar("❌ خطأ في التسجيل: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Text("تم التسجيل ✅", textAlign: TextAlign.center),
        content: const Text("تم إنشاء حساب العميل وتفعيله بنجاح. يمكن للعميل الآن تسجيل الدخول برقم هاتفه."),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2D9E68)),
              onPressed: () {
                Navigator.pop(context); // إغلاق التنبيه
                Navigator.pop(context); // العودة للقائمة الرئيسية
              }, 
              child: const Text("موافق", style: TextStyle(color: Colors.white))
            ),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("تسجيل عميل جديد", style: TextStyle(fontFamily: 'Cairo')),
        backgroundColor: const Color(0xFF2D9E68),
        centerTitle: true,
      ),
      body: _isLoading && _currentPosition == null 
        ? const Center(child: CircularProgressIndicator(color: Color(0xFF2D9E68)))
        : SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  const Icon(Icons.person_add_alt_1_rounded, size: 80, color: Color(0xFF2D9E68)),
                  const SizedBox(height: 20),
                  _buildInput(_nameController, "اسم المحل / السوبر ماركت *", Icons.store),
                  const SizedBox(height: 15),
                  _buildInput(_ownerNameController, "اسم صاحب النشاط (اختياري)", Icons.person_pin),
                  const SizedBox(height: 15),
                  _buildInput(_phoneController, "رقم الهاتف *", Icons.phone_iphone, keyboard: TextInputType.phone),
                  const SizedBox(height: 15),
                  _buildInput(_passwordController, "تعيين كلمة مرور للعميل *", Icons.lock_outline, isPass: true),
                  const SizedBox(height: 15),
                  _buildInput(_addressController, "عنوان الموقع (تلقائي من الـ GPS)", Icons.map_outlined, readOnly: true),
                  const SizedBox(height: 30),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _registerCustomer,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2D9E68),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _isLoading 
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text("حفظ وتفعيل الحساب فوراً", 
                            style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }

  Widget _buildInput(TextEditingController controller, String label, IconData icon, 
      {bool isPass = false, bool readOnly = false, TextInputType keyboard = TextInputType.text}) {
    return TextFormField(
      controller: controller,
      obscureText: isPass,
      readOnly: readOnly,
      keyboardType: keyboard,
      style: const TextStyle(fontFamily: 'Cairo'),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.grey),
        prefixIcon: Icon(icon, color: const Color(0xFF2D9E68)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF2D9E68), width: 2),
        ),
        filled: readOnly,
        fillColor: readOnly ? Colors.grey[100] : Colors.white,
      ),
      validator: (v) {
        if (label.contains('*') && (v == null || v.isEmpty)) return "هذا الحقل مطلوب";
        if (label.contains('الهاتف') && v!.length < 10) return "رقم هاتف غير صحيح";
        return null;
      },
    );
  }
}

