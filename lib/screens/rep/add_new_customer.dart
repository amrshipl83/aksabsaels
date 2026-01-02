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
    _determinePosition(); // محاولة جلب الموقع عند فتح الشاشة
  }

  Future<void> _loadRepData() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('userData');
    if (data != null) {
      setState(() => _repData = jsonDecode(data));
    }
  }

  // دالة طلب الإذن وجلب الموقع (المحسنة)
  Future<void> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    // 1. فحص هل خدمة الـ GPS مفعلة في الهاتف
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("❌ يرجى تفعيل خدمة الموقع (GPS) في الهاتف")),
        );
      }
      return;
    }

    // 2. فحص وطلب إذن التطبيق
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("❌ تم رفض إذن الوصول للموقع")),
          );
        }
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("❌ إذن الموقع مرفوض نهائياً، يرجى تفعيله من الإعدادات")),
        );
      }
      return;
    }

    // 3. جلب الإحداثيات
    setState(() => _isLoading = true);
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      setState(() {
        _currentPosition = position;
        _addressController.text = "موقع دقيق: ${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}";
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      debugPrint("Error location: $e");
    }
  }

  Future<void> _registerCustomer() async {
    if (!_formKey.currentState!.validate() || _currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("يرجى ملء البيانات وتحديث الموقع أولاً")),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      String phone = _phoneController.text.trim();
      // استخدام الدومين المتوافق مع تطبيق الزبائن
      String smartEmail = "$phone@aswaq.com"; 
      String password = _passwordController.text.trim();

      // --- الخطوة الأولى: إنشاء حساب المصادقة (Firebase Auth) ---
      UserCredential userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: smartEmail, password: password);

      String userId = userCredential.user!.uid;

      // --- الخطوة الثانية: حفظ المستند في Firestore بنفس الـ UID ---
      await FirebaseFirestore.instance.collection('users').doc(userId).set({
        'uid': userId,
        'fullname': _nameController.text.trim(),
        'email': smartEmail,
        'phone': phone,
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
        'status': 'active',
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("✅ تم تسجيل العميل بنجاح وارتباطه بالمصادقة")),
        );
        Navigator.pop(context);
      }
    } on FirebaseAuthException catch (e) {
      String msg = "حدث خطأ في التسجيل";
      if (e.code == 'email-already-in-use') msg = "هذا الرقم (البريد) مسجل بالفعل";
      if (e.code == 'weak-password') msg = "كلمة المرور ضعيفة جداً";
      
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      debugPrint("Store Error: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("❌ حدث خطأ غير متوقع أثناء الحفظ")),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("تسجيل عميل جديد", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF43B97F),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              _buildInput(_nameController, "اسم المحل / التاجر", Icons.store),
              const SizedBox(height: 15),
              _buildInput(_phoneController, "رقم الهاتف (اسم المستخدم)", Icons.phone, keyboard: TextInputType.phone),
              const SizedBox(height: 15),
              _buildInput(_passwordController, "كلمة مرور العميل", Icons.lock, isPass: true),
              const SizedBox(height: 15),
              _buildInput(_addressController, "تحديد الموقع", Icons.location_on, readOnly: true),
              const SizedBox(height: 10),
              
              TextButton.icon(
                onPressed: _isLoading ? null : _determinePosition,
                icon: const Icon(Icons.my_location, color: Color(0xFF43B97F)),
                label: const Text("تحديث الإحداثيات الجغرافية", style: TextStyle(color: Color(0xFF43B97F))),
              ),
              
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _registerCustomer,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF43B97F),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: _isLoading 
                    ? const CircularProgressIndicator(color: Colors.white) 
                    : const Text("حفظ وتفعيل حساب العميل", style: TextStyle(fontSize: 18, color: Colors.white)),
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
        filled: readOnly,
        fillColor: readOnly ? Colors.grey[100] : null,
      ),
      validator: (v) => (v == null || v.isEmpty) ? "هذا الحقل مطلوب" : null,
    );
  }
}

