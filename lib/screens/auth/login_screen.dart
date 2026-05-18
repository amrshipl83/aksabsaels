// lib/screens/auth/login_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:convert';
import 'register_screen.dart';

// --- الهوية البصرية الجديدة لأكسب ---
const Color kPrimaryColor = Color(0xFFB21F2D); // أحمر أكسب المعتمد
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

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ✅ دالة التعامل مع الـ Timestamp أثناء تحويل البيانات لـ JSON (من الكود الأصلي)
  dynamic _encoder(dynamic item) {
    if (item is Timestamp) return item.toDate().toIso8601String();
    return item;
  }

  // ✅ تحديث توكن الإشعارات مباشرة داخل الفايربيز (بديل أمازون المستقر)
  Future<void> _updateFcmTokenInFirestore(String docId, String collectionName) async {
    try {
      String? token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;

      await FirebaseFirestore.instance
          .collection(collectionName)
          .doc(docId)
          .update({
            'fcmToken': token,
            'lastLogin': FieldValue.serverTimestamp(),
          });
    } catch (e) {
      debugPrint("FCM Token Local Update Error: $e");
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
    // ✅ النطاق الذكي الحصري لفريق المبيعات والإدارة
    String smartEmail = input.contains('@') ? input : "$input@aksabsales.com";
    final password = _passwordController.text.trim();

    try {
      // الدخول المباشر بالرقم والباسورد يدوياً بدون تفعيل تلقائي
      final userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: smartEmail,
        password: password,
      );

      final user = userCredential.user;
      if (user == null) throw FirebaseAuthException(code: 'user-null');

      DocumentSnapshot? userDocSnapshot;
      String? userRole;
      String? matchedCollection;

      // ✅ البحث في كولكشن salesRep (المفرد) بناءً على قواعد الـ Firestore الثابتة
      final salesRepQuery = await FirebaseFirestore.instance
          .collection('salesRep') 
          .where('uid', isEqualTo: user.uid)
          .limit(1)
          .get();

      if (salesRepQuery.docs.isNotEmpty) {
        userDocSnapshot = salesRepQuery.docs.first;
        userRole = 'sales_rep';
        matchedCollection = 'salesRep';
      }

      if (userDocSnapshot == null) {
        final managersQuery = await FirebaseFirestore.instance
            .collection('managers')
            .where('uid', isEqualTo: user.uid)
            .limit(1)
            .get();
        if (managersQuery.docs.isNotEmpty) {
          userDocSnapshot = managersQuery.docs.first;
          userRole = userDocSnapshot.get('role')?.toString();
          matchedCollection = 'managers';
        }
      }

      if (userDocSnapshot != null && userRole != null && matchedCollection != null) {
        final userDocData = userDocSnapshot.data() as Map<String, dynamic>;
        userDocData['docId'] = userDocSnapshot.id;

        if (userDocData['status'] == 'approved') {
          // ✅ مناداة تحديث الإشعارات مباشرة في الفايرستور بدلاً من دالة أمازون المحذوفة
          await _updateFcmTokenInFirestore(userDocSnapshot.id, matchedCollection);

          final prefs = await SharedPreferences.getInstance();
          // ✅ التخزين باستخدام الـ encoder لضمان عدم حدوث خطأ في الـ Timestamps
          await prefs.setString('userData', json.encode(userDocData, toEncodable: _encoder));
          await prefs.setString('userRole', userRole);

          if (mounted) {
            Navigator.of(context).pushReplacementNamed(
              userRole == 'sales_rep' ? '/rep_home' : '/admin_dashboard'
            );
          }
        } else {
          await FirebaseAuth.instance.signOut();
          _showError('❌ حسابك بانتظار تفعيل الإدارة.');
        }
      } else {
        await FirebaseAuth.instance.signOut();
        _showError('❌ بياناتك غير موجودة في سجلات مبيعات أكسب.');
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
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: kSecondaryColor, fontFamily: 'Cairo')),
                    const Text('منظومة المندوب الذكي', 
                        style: TextStyle(fontSize: 14, color: Colors.grey, fontFamily: 'Cairo')),
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
                            : const Text('دخول للفريق', style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                      ),
                    ),
                    if (_errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 15),
                        child: Text(_errorMessage!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w500, fontFamily: 'Cairo')),
                      ),
                    const SizedBox(height: 20),
                    TextButton(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const RegisterScreen())),
                      child: const Text('طلب انضمام لفريق المبيعات', style: TextStyle(color: kPrimaryColor, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
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
      style: const TextStyle(fontFamily: 'Cairo'),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontFamily: 'Cairo'),
        prefixIcon: Icon(icon, color: kPrimaryColor),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide(color: Colors.grey[300]!)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: kPrimaryColor, width: 2),
        ),
        filled: true,
        fillColor: Colors.grey[50],
      ),
      validator: (v) => (v == null || v.isEmpty) ? 'مطلوب' : null,
    );
  }
}