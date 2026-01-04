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
    // تأخير بسيط لإظهار رسالة الإفصاح بعد بناء الواجهة
    Future.delayed(Duration.zero, () => _showLocationDisclosure());
  }

  Future<void> _loadRepData() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('userData');
    if (data != null) {
      setState(() => _repData = jsonDecode(data));
    }
  }

  // رسالة إفصاح جوجل (Prominent Disclosure) - تظهر قبل طلب الإذن الرسمي
  void _showLocationDisclosure() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.always || permission == LocationPermission.whileInUse) {
       _determinePosition(); // إذا كان معه إذن مسبق، نجلب الموقع فوراً
       return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.security, color: Color(0xFF43B97F)),
            SizedBox(width: 10),
            Text("خصوصية الموقع"),
          ],
        ),
        content: const Text(
          "تطبيق 'أكسب' يحتاج للوصول إلى موقعك الجغرافي أثناء تسجيل عميل جديد، وذلك لربط المحل بإحداثيات دقيقة تضمن وصول المناديب وعمليات التوصيل والتحصيل بشكل صحيح.",
          style: TextStyle(fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("لاحقاً", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF43B97F),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              Navigator.pop(context);
              _determinePosition();
            },
            child: const Text("موافق، ابدأ التحديد", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showSnackBar("❌ يرجى تفعيل الـ GPS في الهاتف");
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _showSnackBar("❌ تم رفض إذن الموقع");
        return;
      }
    }

    setState(() => _isLoading = true);
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // تحويل الإحداثيات لعنوان نصي مقروء
      List<Placemark> placemarks = await placemarkFromCoordinates(position.latitude, position.longitude);
      String address = "موقع غير محدد";
      if (placemarks.isNotEmpty) {
        Placemark p = placemarks[0];
        address = "${p.street}, ${p.subLocality}, ${p.locality}";
      }

      setState(() {
        _currentPosition = position;
        _addressController.text = address;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showSnackBar("❌ فشل في جلب العنوان: $e");
    }
  }

  void _showSnackBar(String msg) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _registerCustomer() async {
    if (!_formKey.currentState!.validate() || _currentPosition == null) {
      _showSnackBar("يرجى ملء البيانات وتحديد الموقع أولاً");
      return;
    }

    setState(() => _isLoading = true);
    try {
      String phone = _phoneController.text.trim();
      String smartEmail = "$phone@aswaq.com";
      String password = _passwordController.text.trim();

      UserCredential userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: smartEmail, password: password);

      String userId = userCredential.user!.uid;

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
        _showSnackBar("✅ تم تسجيل العميل بنجاح");
        Navigator.pop(context);
      }
    } catch (e) {
      _showSnackBar("❌ حدث خطأ: $e");
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
              _buildInput(_phoneController, "رقم الهاتف", Icons.phone, keyboard: TextInputType.phone),
              const SizedBox(height: 15),
              _buildInput(_passwordController, "كلمة المرور", Icons.lock, isPass: true),
              const SizedBox(height: 15),
              _buildInput(_addressController, "عنوان الموقع (تلقائي)", Icons.location_on, readOnly: true),
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: _isLoading ? null : _determinePosition,
                icon: const Icon(Icons.my_location, color: Color(0xFF43B97F)),
                label: Text(_isLoading ? "جاري التحديد..." : "تحديث العنوان الجغرافي", 
                      style: const TextStyle(color: Color(0xFF43B97F), fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _registerCustomer,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF43B97F),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text("حفظ وتفعيل حساب العميل", 
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
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: const Color(0xFF43B97F)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: readOnly,
        fillColor: readOnly ? Colors.grey[100] : null,
      ),
      validator: (v) => (v == null || v.isEmpty) ? "هذا الحقل مطلوب" : null,
    );
  }
}

