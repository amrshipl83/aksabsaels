// lib/screens/rep/add_new_customer_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:aksab_sales/utils/phone_normalize.dart';

// Rep-created buyer is server-owned: the app sends the profile + the rep's
// ID token, the backend validates, creates the passwordless Auth user and
// the users/ buyer doc, and binds repCode/repName from the approved rep
// record. The client never chooses repCode and never sets passwords.
// Function is deployed separately as cashback_logic:repBuyer.
const String kRepBuyerEndpoint =
    'https://us-central1-aksab-erp.cloudfunctions.net/repBuyer';

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
  final _addressController = TextEditingController();

  bool _isLoading = false;
  Position? _currentPosition;

  @override
  void initState() {
    super.initState();
    // جلب الموقع فوراً بصمت لاعتباره مأخوذ مسبقاً
    _determinePosition();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ownerNameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
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
        Placemark p = placemarks.first;
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

  /// Egyptian mobile in 0-format (010/011/012/015 + 8 digits), as the server expects.
  /// Delegates to the shared canonical rule (see lib/utils/phone_normalize.dart):
  /// local 01…, international 20…/+20…/0020… — all collapse to the same local
  /// form, so one number can never produce two different accounts.
  String? _normalizePhone(String raw) => normalizeEgyptianPhoneToLocal(raw);

  Future<void> _registerCustomer() async {
    // التأكد من ملء البيانات ووجود إحداثيات (اللقطة الجغرافية)
    if (!_formKey.currentState!.validate() || _currentPosition == null) {
      _showSnackBar("❌ يرجى التأكد من البيانات ولقطة الموقع");
      return;
    }

    final cleanPhone = _normalizePhone(_phoneController.text.trim());
    if (cleanPhone == null) {
      _showSnackBar("❌ رقم هاتف مصري غير صحيح (11 رقم يبدأ بـ 010/011/012/015)");
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showSnackBar("❌ انتهت الجلسة. أعد تسجيل الدخول.");
      return;
    }

    setState(() => _isLoading = true);
    try {
      final idToken = await user.getIdToken();
      final response = await http.post(
        Uri.parse(kRepBuyerEndpoint),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({
          'fullname': _nameController.text.trim(),
          'ownerName': _ownerNameController.text.trim(),
          'phoneNumber': cleanPhone,
          'address': _addressController.text.trim(),
          'country': 'egypt',
          'location': {
            'lat': _currentPosition!.latitude,
            'lng': _currentPosition!.longitude,
          },
        }),
      );

      if (response.statusCode == 200) {
        if (mounted) _showSuccessDialog();
        return;
      }
      if (mounted) {
        final msg = switch (response.statusCode) {
          409 => "❌ هذا الرقم مسجل بالفعل.",
          400 => "❌ بيانات غير صالحة. راجع الاسم ورقم الهاتف.",
          401 || 403 => "❌ الجلسة غير مخولة. أعد تسجيل الدخول.",
          _ => "❌ تعذر التسجيل حالياً (${response.statusCode}). حاول لاحقاً.",
        };
        _showSnackBar(msg);
      }
    } catch (e) {
      _showSnackBar("❌ خطأ في الاتصال: $e");
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
        title: const Text("تم التسجيل ✅", style: TextStyle(fontFamily: 'Cairo'), textAlign: TextAlign.center),
        content: const Text(
          "تم إنشاء حساب العميل من الخادم وربطه بك.\nيمكن للعميل الآن تحميل التطبيق وتسجيل الدخول المباشر برقم هاتفه وكود الـ OTP فوراً.",
          style: TextStyle(fontFamily: 'Cairo'),
          textAlign: TextAlign.center,
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2D9E68)),
              onPressed: () {
                Navigator.pop(context); // إغلاق التنبيه
                Navigator.pop(context); // العودة للقائمة الرئيسية
              },
              child: const Text("موافق", style: TextStyle(color: Colors.white, fontFamily: 'Cairo'))
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
        title: const Text("تسجيل عميل ميداني جديد", style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: const Color(0xFF2D9E68),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
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
                  _buildInput(_phoneController, "رقم هاتف العميل *", Icons.phone_iphone, keyboard: TextInputType.phone),
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
                        : const Text("حفظ وتأمين الحساب فوراً",
                            style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }

  Widget _buildInput(TextEditingController controller, String label, IconData icon,
      {bool readOnly = false, TextInputType keyboard = TextInputType.text}) {
    return TextFormField(
      controller: controller,
      readOnly: readOnly,
      keyboardType: keyboard,
      style: const TextStyle(fontFamily: 'Cairo'),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.grey, fontFamily: 'Cairo'),
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
        if (label.contains('الهاتف') && _normalizePhone(v ?? '') == null) return "رقم هاتف مصري غير صحيح";
        return null;
      },
    );
  }
}
