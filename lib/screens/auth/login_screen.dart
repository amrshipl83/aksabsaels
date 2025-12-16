import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

// ----------------------------------------------------------------------
// تعريف الألوان والثوابت
// ----------------------------------------------------------------------
const Color kPrimaryColor = Color(0xFFF57C00); // اللون البرتقالي
const Color kSecondaryColor = Color(0xFF1A2C3D); // لون النص الداكن

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _errorMessage;
  bool _isLoading = false;

  // دالة مساعدة لمعالجة كائنات Timestamp قبل التشفير للحفظ في SharedPreferences
  dynamic _encoder(dynamic item) {
    if (item is Timestamp) {
      return item.toDate().toIso8601String();
    }
    return item;
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    try {
      // 1. تسجيل الدخول عبر Firebase Auth
      final userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = userCredential.user;

      if (user == null) {
        throw FirebaseAuthException(code: 'user-null');
      }

      DocumentSnapshot? userDocSnapshot;
      String? userRole;

      // 2. البحث في مجموعة المناديب (salesRep)
      final salesRepQuery = await FirebaseFirestore.instance
          .collection('salesRep')
          .where('uid', isEqualTo: user.uid)
          .limit(1)
          .get();
      
      if (salesRepQuery.docs.isNotEmpty) {
        userDocSnapshot = salesRepQuery.docs.first;
        userRole = (userDocSnapshot.data() as Map<String, dynamic>?)?['role']?.toString() ?? 'sales_rep';
      }

      // 3. البحث في مجموعة المدراء (managers) إذا لم يوجد في المناديب
      if (userDocSnapshot == null) {
        final managersQuery = await FirebaseFirestore.instance
            .collection('managers')
            .where('uid', isEqualTo: user.uid)
            .limit(1)
            .get();

        if (managersQuery.docs.isNotEmpty) {
          userDocSnapshot = managersQuery.docs.first;
          userRole = (userDocSnapshot.data() as Map<String, dynamic>?)?['role']?.toString();
        }
      }

      // 4. التحقق من وجود البيانات ومن حالة الحساب
      if (userDocSnapshot != null && userRole != null) {
        final userDocData = userDocSnapshot.data() as Map<String, dynamic>;
        final status = userDocData['status']?.toString();
        
        if (status == 'approved') {
          // حفظ البيانات محلياً
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('userData', json.encode(userDocData, toEncodable: _encoder));
          await prefs.setString('userRole', userRole);

          if (mounted) {
            // التوجيه بناءً على الدور
            if (userRole == 'sales_rep') {
              // التوجه لشاشة المندوب الرئيسية (المسار المعرف في main.dart)
              Navigator.of(context).pushReplacementNamed('/rep_home');
            } else if (userRole == 'sales_supervisor' || userRole == 'sales_manager') {
              // TODO: توجيه لشاشة المدير عند الانتهاء منها
              _showError('✅ تم الدخول كمدير، شاشة الإدارة قيد التطوير.');
            } else {
              await FirebaseAuth.instance.signOut();
              _showError('❌ دور المستخدم غير مدعوم حالياً.');
            }
          }
        } else {
          await FirebaseAuth.instance.signOut();
          _showError('❌ حسابك بانتظار تفعيل الإدارة.');
        }
      } else {
        await FirebaseAuth.instance.signOut();
        _showError('❌ بيانات المستخدم غير موجودة في قاعدة بيانات المبيعات.');
      }
    } on FirebaseAuthException catch (e) {
      String message;
      if (e.code == 'wrong-password' || e.code == 'user-not-found' || e.code == 'invalid-credential') {
        message = 'البريد الإلكتروني أو كلمة المرور غير صحيحة.';
      } else if (e.code == 'invalid-email') {
        message = 'صيغة البريد الإلكتروني غير صالحة.';
      } else {
        message = 'حدث خطأ أثناء تسجيل الدخول. حاول مجدداً.';
      }
      _showError('❌ $message');
    } catch (e) {
      _showError('❌ خطأ غير متوقع: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showError(String message) {
    if (mounted) {
      setState(() => _errorMessage = message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFF5F7FA), Color(0xFFC3CFE2)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
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
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.login, color: kSecondaryColor),
                        const SizedBox(width: 8),
                        Text(
                          'تسجيل الدخول',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: kSecondaryColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 30),
                    _buildTextFormField(
                      controller: _emailController,
                      label: 'البريد الإلكتروني',
                      icon: Icons.email,
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 20),
                    _buildTextFormField(
                      controller: _passwordController,
                      label: 'كلمة المرور',
                      icon: Icons.lock,
                      isPassword: true,
                    ),
                    const SizedBox(height: 30),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _login,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kPrimaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 5,
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                height: 20, width: 20,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                              )
                            : const Text('تسجيل الدخول', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    if (_errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 15),
                        child: Text(_errorMessage!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
                      ),
                    const SizedBox(height: 20),
                    TextButton(
                      onPressed: () {
                        // TODO: Navigator.pushNamed(context, '/register');
                      },
                      child: const Text('تسجيل حساب جديد', style: TextStyle(color: kPrimaryColor, fontWeight: FontWeight.bold)),
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

  Widget _buildTextFormField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    bool isPassword = false,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: isPassword,
      textAlign: TextAlign.right,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: kPrimaryColor),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      ),
      validator: (value) => (value == null || value.isEmpty) ? 'يجب إدخال $label' : null,
    );
  }
}
