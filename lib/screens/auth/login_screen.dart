import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

// استيراد شاشة التسجيل لاستخدامها في الزر السفلي
import 'register_screen.dart'; 

const Color kPrimaryColor = Color(0xFF43B97F); // غيرناه للأخضر ليتماشى مع الهوية الجديدة
const Color kSecondaryColor = Color(0xFF1A2C3D);

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController(); // تم تغيير الاسم ليكون أوضح
  final _passwordController = TextEditingController();
  String? _errorMessage;
  bool _isLoading = false;

  dynamic _encoder(dynamic item) {
    if (item is Timestamp) {
      return item.toDate().toIso8601String();
    }
    return item;
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    // --- المنطق الذكي للتحويل ---
    String input = _phoneController.text.trim();
    String smartEmail;
    
    // إذا كان المدخل أرقام فقط (رقم هاتف)، نحوله للإيميل الذكي
    if (RegExp(r'^[0-9]+$').hasMatch(input)) {
      smartEmail = "$input@aksab.com";
    } else {
      smartEmail = input; // لو أدخل إيميل كامل يدوياً (للمدراء مثلاً)
    }
    
    final password = _passwordController.text.trim();

    try {
      // 1. تسجيل الدخول بالهوية المولدة
      final userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: smartEmail,
        password: password,
      );
      final user = userCredential.user;

      if (user == null) throw FirebaseAuthException(code: 'user-null');

      DocumentSnapshot? userDocSnapshot;
      String? userRole;

      // 2. البحث في المناديب المعتمدين (salesRep)
      final salesRepQuery = await FirebaseFirestore.instance
          .collection('salesRep')
          .where('uid', isEqualTo: user.uid)
          .limit(1)
          .get();

      if (salesRepQuery.docs.isNotEmpty) {
        userDocSnapshot = salesRepQuery.docs.first;
        userRole = (userDocSnapshot.data() as Map<String, dynamic>?)?['role']?.toString() ?? 'sales_rep';
      }

      // 3. البحث في المدراء المعتمدين (managers)
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

      // 4. التحقق من الحالة والحفظ
      if (userDocSnapshot != null && userRole != null) {
        final userDocData = userDocSnapshot.data() as Map<String, dynamic>;
        final status = userDocData['status']?.toString();

        if (status == 'approved') {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('userData', json.encode(userDocData, toEncodable: _encoder));
          await prefs.setString('userRole', userRole);

          if (mounted) {
            if (userRole == 'sales_rep') {
              Navigator.of(context).pushReplacementNamed('/rep_home');
            } else if (userRole == 'sales_supervisor' || userRole == 'sales_manager') {
              // حالياً نوجههم لنفس الصفحة أو صفحة مدير إذا كانت جاهزة
              _showError('✅ تم الدخول كمدير/مشرف، جاري تحويلك...');
            }
          }
        } else {
          await FirebaseAuth.instance.signOut();
          _showError('❌ حسابك بانتظار تفعيل الإدارة.');
        }
      } else {
        await FirebaseAuth.instance.signOut();
        _showError('❌ بياناتك لم تنقل بعد للكشوف المعتمدة.');
      }
    } on FirebaseAuthException catch (e) {
      _showError('❌ رقم الهاتف أو كلمة المرور غير صحيحة.');
    } catch (e) {
      _showError('❌ خطأ غير متوقع: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    if (mounted) setState(() => _errorMessage = message);
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
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 20)],
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

