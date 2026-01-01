import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class AddNewCustomerScreen extends StatefulWidget {
  const AddNewCustomerScreen({super.key});

  @override
  State<AddNewCustomerScreen> createState() => _AddNewCustomerScreenState();
}

class _AddNewCustomerScreenState extends State<AddNewCustomerScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController(); // سنستخدم الهاتف بدلاً من الإيميل
  final _passwordController = TextEditingController();
  final _addressController = TextEditingController();
  
  bool _isLoading = false;
  Position? _currentPosition;
  Map<String, dynamic>? _repData;

  @override
  void initState() {
    super.initState();
    _loadRepData();
    _determinePosition();
  }

  // تحميل بيانات المندوب المسجلة
  Future<void> _loadRepData() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('userData');
    if (data != null) {
      setState(() => _repData = jsonDecode(data));
    }
  }

  // جلب الموقع الجغرافي (بديل Mapbox في الواجهة)
  Future<void> _determinePosition() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      setState(() {
        _currentPosition = position;
        _addressController.text = "تم تحديد الموقع: ${position.latitude}, ${position.longitude}";
      });
    } catch (e) {
      debugPrint("خطأ في جلب الموقع: $e");
    }
  }

  Future<void> _registerCustomer() async {
    if (!_formKey.currentState!.validate() || _currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("يرجى ملء البيانات وتفعيل الموقع")),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // المنطق الذكي: تحويل رقم الهاتف إلى بريد إلكتروني
      String phone = _phoneController.text.trim();
      String smartEmail = "$phone@aksab.com";
      String password = _passwordController.text.trim();

      // 1. إنشاء حساب في Firebase Auth
      UserCredential userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: smartEmail, password: password);

      String userId = userCredential.user!.uid;

      // 2. حفظ البيانات في Firestore (مجموعة users)
      await FirebaseFirestore.instance.collection('users').doc(userId).set({
        'fullname': _nameController.text.trim(),
        'email': smartEmail,
        'phone': phone, // حفظ الرقم الأصلي للرجوع إليه
        'address': _addressController.text.trim(),
        'location': {
          'lat': _currentPosition!.latitude,
          'lng': _currentPosition!.longitude,
        },
        'role': "buyer",
        'country': "egypt",
        'createdAt': FieldValue.serverTimestamp(),
        'isVerified': true,
        'repCode': _repData?['repCode'],
        'repName': _repData?['fullname'],
      });

      // 3. العودة بعد النجاح
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("✅ تم تسجيل العميل بنجاح")),
        );
        Navigator.pop(context); // العودة لشاشة الزيارات أو الرئيسية
      }
    } on FirebaseAuthException catch (e) {
      String msg = "حدث خطأ في التسجيل";
      if (e.code == 'email-already-in-use') msg = "هذا الرقم مسجل مسبقاً";
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("تسجيل عميل جديد")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              _buildInput(_nameController, "اسم المحل / العميل", Icons.store),
              const SizedBox(height: 15),
              _buildInput(_phoneController, "رقم الهاتف (سيكون هو اسم المستخدم)", Icons.phone, keyboard: TextInputType.phone),
              const SizedBox(height: 15),
              _buildInput(_passwordController, "كلمة مرور العميل", Icons.lock, isPass: true),
              const SizedBox(height: 15),
              _buildInput(_addressController, "العنوان", Icons.location_on, readOnly: true),
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: _determinePosition,
                icon: const Icon(Icons.my_location),
                label: const Text("تحديث الموقع الجغرافي"),
              ),
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _registerCustomer,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF43B97F),
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                  child: _isLoading 
                    ? const CircularProgressIndicator(color: Colors.white) 
                    : const Text("تسجيل العميل في النظام", style: TextStyle(fontSize: 18, color: Colors.white)),
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
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: const Color(0xFF43B97F)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
      validator: (v) => (v == null || v.isEmpty) ? "هذا الحقل مطلوب" : null,
    );
  }
}

