import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'register_screen.dart';

// --- الهوية البصرية الجديدة لأكسب ---
const Color kPrimaryColor = Color(0xFFB21F2D); // أحمر أكسب
const Color kSecondaryColor = Color(0xFF1A2C3D); 

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();

  String? _errorMessage;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkExistingLogin();
  }

  // --- ربط التوكن مع الـ Backend لإرسال الإشعارات ---
  Future<void> _registerNotification(String userId, String role, String address) async {
    try {
      String? token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;

      await http.post(
        Uri.parse('https://5uex7vzy64.execute-api.us-east-1.amazonaws.com/V2/new_nofiction'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'userId': userId,
          'fcmToken': token,
          'role': role,
          'address': address,
        }),
      );
    } catch (e) {
      print("Notification Sync Error: $e");
    }
  }

  Future<void> _checkExistingLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final String? userRole = prefs.getString('userRole');
    final String? userData = prefs.getString('userData');

    if (userRole != null && userData != null) {
      if (mounted) {
        if (userRole == 'sales_rep') {
          Navigator.of(context).pushReplacementNamed('/rep_home');
        } else {
          Navigator.of(context).pushReplacementNamed('/admin_dashboard');
        }
      }
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    String input = _phoneController.text.trim();
    // ✅ التعديل الجوهري: استخدام النطاق الخاص بتطبيق المبيعات فقط
    String smartEmail = input.contains('@') ? input : "$input@aksabsales.com";
    final password = _passwordController.text.trim();

    try {
      final userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: smartEmail,
        password: password,
      );

      final user = userCredential.user;
      if (user == null) throw FirebaseAuthException(code: 'user-null');

      DocumentSnapshot? userDocSnapshot;
      String? userRole;

      // البحث في كولكشن المناديب (تأكد من مطابقة الاسم في Firestore)
      final salesRepQuery = await FirebaseFirestore.instance
          .collection('salesRep') // تم توحيد الاسم لـ salesReps
          .where('uid', isEqualTo: user.uid)
          .limit(1)
          .get();

      if (salesRepQuery.docs.isNotEmpty) {
        userDocSnapshot = salesRepQuery.docs.first;
        userRole = 'sales_rep';
      }

      // البحث في كولكشن المديرين إذا لم يكن مندوباً
      if (userDocSnapshot == null) {
        final managersQuery = await FirebaseFirestore.instance
            .collection('managers')
            .where('uid', isEqualTo: user.uid)
            .limit(1)
            .get();
        if (managersQuery.docs.isNotEmpty) {
          userDocSnapshot = managersQuery.docs.first;
          userRole = userDocSnapshot.get('role')?.toString();
        }
      }

      if (userDocSnapshot != null && userRole != null) {
        final userDocData = userDocSnapshot.data() as Map<String, dynamic>;
        userDocData['docId'] = userDocSnapshot.id;

        // ✅ التأكد من قبول الحساب من قبل الإدارة
        if (userDocData['status'] == 'approved') {
          await _registerNotification(user.uid, userRole, userDocData['address'] ?? "");

          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('userData', json.encode(userDocData));
          await prefs.setString('userRole', userRole);

          if (mounted) {
            Navigator.of(context).pushReplacementNamed(
              userRole == 'sales_rep' ? '/rep_home' : '/admin_dashboard'
            );
          }
        } else {
          await FirebaseAuth.instance.signOut();
          _showError('❌ حسابك بانتظار تفعيل الإدارة (Pending).');
        }
      } else {
        await FirebaseAuth.instance.signOut();
        _showError('❌ بياناتك غير موجودة في سجلات المبيعات.');
      }
    } on FirebaseAuthException {
      _showError('❌ رقم الهاتف أو كلمة المرور غير صحيحة.');
    } catch (e) {
      _showError('❌ خطأ في النظام: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    if (mounted) setState(() => _errorMessage = message);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _phoneController.text.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: kPrimaryColor)));
    }

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFF5F7FA), Color(0xFFEDEFF2)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(30.0),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 400),
              padding: const EdgeInsets.all(30.0),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(25),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 20)],
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    const Icon(Icons.stars_rounded, size: 70, color: kPrimaryColor),
                    const SizedBox(height: 10),
                    const Text('أكسب للمبيعات', 
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: kSecondaryColor)),
                    const Text('منظومة المندوب الذكي', 
                        style: TextStyle(fontSize: 14, color: Colors.grey)),
                    const SizedBox(height: 30),
                    _buildField(_phoneController, 'رقم الهاتف', Icons.phone_android, isPhone: true),
                    const SizedBox(height: 20),
                    _buildField(_passwordController, 'كلمة المرور', Icons.lock_outline, isPass: true),
                    const SizedBox(height: 30),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _login,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kPrimaryColor,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                        ),
                        child: _isLoading
                            ? const CircularProgressIndicator(color: Colors.white)
                            : const Text('دخول للفريق', style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    if (_errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 15),
                        child: Text(_errorMessage!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w500)),
                      ),
                    const SizedBox(height: 20),
                    TextButton(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const RegisterScreen())),
                      child: const Text('طلب انضمام لفريق المبيعات', style: TextStyle(color: kPrimaryColor, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField(TextEditingController controller, String label, IconData icon, {bool isPass = false, bool isPhone = false}) {
    return TextFormField(
      controller: controller,
      obscureText: isPass,
      textAlign: TextAlign.right,
      keyboardType: isPhone ? TextInputType.phone : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: kPrimaryColor),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
        filled: true,
        fillColor: Colors.grey[50],
      ),
      validator: (v) => (v == null || v.isEmpty) ? 'مطلوب' : null,
    );
  }
}

