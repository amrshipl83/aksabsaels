import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'register_screen.dart';

const Color kPrimaryColor = Color(0xFF43B97F);
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
  bool _isLoading = true; // نبدأ بـ true حتى ينتهي الفحص التلقائي

  @override
  void initState() {
    super.initState();
    _checkExistingLogin(); // فحص إذا كان المستخدم مسجلاً مسبقاً
  }

  // --- وظيفة الفحص التلقائي عند فتح التطبيق ---
  Future<void> _checkExistingLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final String? userRole = prefs.getString('userRole');
    final String? userData = prefs.getString('userData');

    if (userRole != null && userData != null) {
      // توجيه المستخدم فوراً بناءً على دوره المخزن
      if (mounted) {
        if (userRole == 'sales_rep') {
          Navigator.of(context).pushReplacementNamed('/rep_home');
        } else if (userRole == 'sales_supervisor' || userRole == 'sales_manager') {
          Navigator.of(context).pushReplacementNamed('/admin_dashboard');
        }
      }
    } else {
      setState(() => _isLoading = false); // إظهار واجهة الدخول إذا لم يوجد مستخدم
    }
  }

  dynamic _encoder(dynamic item) {
    if (item is Timestamp) return item.toDate().toIso8601String();
    return item;
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    String input = _phoneController.text.trim();
    String smartEmail = input.contains('@') ? input : "$input@aksab.com";
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

      // البحث في المناديب
      final salesRepQuery = await FirebaseFirestore.instance
          .collection('salesRep')
          .where('uid', isEqualTo: user.uid)
          .limit(1)
          .get();

      if (salesRepQuery.docs.isNotEmpty) {
        userDocSnapshot = salesRepQuery.docs.first;
        userRole = 'sales_rep';
      }

      // البحث في المدراء/المشرفين إذا لم يجد مندوب
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

        // 🛑 دمج التعديل المطلوب: تخزين معرف الوثيقة ونسيان الـ uid في التعاملات اللاحقة
        userDocData['docId'] = userDocSnapshot.id;

        if (userDocData['status'] == 'approved') {
          final prefs = await SharedPreferences.getInstance();
          // حفظ البيانات لفتح التطبيق تلقائياً المرة القادمة (مع الـ docId الجديد)
          await prefs.setString('userData', json.encode(userDocData, toEncodable: _encoder));
          await prefs.setString('userRole', userRole);

          if (mounted) {
            if (userRole == 'sales_rep') {
              Navigator.of(context).pushReplacementNamed('/rep_home');
            } else {
              Navigator.of(context).pushReplacementNamed('/admin_dashboard');
            }
          }
        } else {
          await FirebaseAuth.instance.signOut();
          _showError('❌ حسابك بانتظار تفعيل الإدارة.');
        }
      } else {
        await FirebaseAuth.instance.signOut();
        _showError('❌ بياناتك غير موجودة في الكشوف المعتمدة.');
      }
    } on FirebaseAuthException {
      _showError('❌ رقم الهاتف أو كلمة المرور غير صحيحة.');
    } catch (e) {
      _showError('❌ خطأ: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    if (mounted) setState(() => _errorMessage = message);
  }

  @override
  Widget build(BuildContext context) {
    // إذا كان جاري التحميل (أو الفحص التلقائي) تظهر شاشة بيضاء أو لوغو
    if (_isLoading && _phoneController.text.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: kPrimaryColor)));
    }

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
                boxShadow: [const BoxShadow(color: Colors.black12, blurRadius: 20)],
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_person, size: 60, color: kPrimaryColor),
                    const SizedBox(height: 10),
                    const Text('أكسب للمبيعات', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: kSecondaryColor)),
                    const SizedBox(height: 30),
                    _buildTextFormField(
                      controller: _phoneController,
                      label: 'رقم الهاتف',
                      icon: Icons.phone_android,
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 20),
                    _buildTextFormField(
                      controller: _passwordController,
                      label: 'كلمة المرور',
                      icon: Icons.lock_outline,
                      isPassword: true,
                    ),
                    const SizedBox(height: 30),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _login,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kPrimaryColor,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _isLoading
                            ? const CircularProgressIndicator(color: Colors.white)
                            : const Text('دخول', style: TextStyle(fontSize: 18, color: Colors.white)),
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
                        Navigator.push(context, MaterialPageRoute(builder: (context) => const RegisterScreen()));
                      },
                      child: const Text('ليس لديك حساب؟ سجل الآن', style: TextStyle(color: kPrimaryColor, fontWeight: FontWeight.bold)),
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

  Widget _buildTextFormField({required TextEditingController controller, required String label, required IconData icon, TextInputType keyboardType = TextInputType.text, bool isPassword = false}) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: isPassword,
      textAlign: TextAlign.right,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: kPrimaryColor),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      validator: (v) => (v == null || v.isEmpty) ? 'مطلوب' : null,
    );
  }
}

