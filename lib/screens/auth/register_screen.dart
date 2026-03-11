import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();

  String _selectedRole = 'sales_rep';
  bool _isLoading = false;
  String? _message;
  bool _isSuccess = false;

  // ألوان هوية أكسب الجديدة
  final Color aksabRed = const Color(0xFFB21F2D);

  final Map<String, String> _roles = {
    'sales_rep': 'مندوب مبيعات',
    'sales_supervisor': 'مشرف مبيعات',
    'sales_manager': 'مدير مبيعات',
  };

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _message = null;
    });

    String phone = _phoneController.text.trim();
    // استخدام النطاق الجديد للفصل بين المنصات
    String smartEmail = "$phone@aksabsales.com";

    try {
      // 1. إنشاء الحساب في Firebase Auth
      final userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: smartEmail,
        password: _passwordController.text,
      );

      final String uid = userCredential.user!.uid;

      // 2. تحديد الكولكشن المناسب
      String collectionName = (_selectedRole == "sales_rep") ? "pendingReps" : "pendingManagers";

      // 3. حفظ البيانات في Firestore
      await FirebaseFirestore.instance.collection(collectionName).doc(uid).set({
        'fullname': _nameController.text.trim(),
        'email': smartEmail,
        'phone': phone,
        'address': _addressController.text.trim(),
        'role': _selectedRole,
        'status': "pending",
        'createdAt': FieldValue.serverTimestamp(),
        'uid': uid,
        'appType': 'sales', // لتمييز الطلب مستقبلاً
      });

      setState(() {
        _isSuccess = true;
        _message = "✅ تم التسجيل بنجاح كـ ${_roles[_selectedRole]}، في انتظار موافقة الإدارة.";
      });

      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) Navigator.pop(context);
      });
    } on FirebaseAuthException catch (e) {
      setState(() {
        _isSuccess = false;
        if (e.code == 'email-already-in-use') {
          _message = "❌ رقم الهاتف هذا مسجل به حساب مندوب بالفعل.";
        } else {
          _message = "❌ خطأ في التسجيل: ${e.message}";
        }
      });
    } catch (e) {
      setState(() {
        _isSuccess = false;
        _message = "❌ حدث خطأ غير متوقع: ${e.toString()}";
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text("إنضم لفريق أكسب مبيعات"),
        backgroundColor: aksabRed,
        centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15)],
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    Icon(Icons.person_add_rounded, size: 60, color: aksabRed),
                    const SizedBox(height: 20),
                    _buildField(_nameController, "الاسم بالكامل", Icons.person),
                    _buildField(_phoneController, "رقم الهاتف", Icons.phone, isPhone: true),
                    _buildField(_passwordController, "كلمة المرور", Icons.lock, isPass: true),
                    _buildField(_addressController, "محل الإقامة / المنطقة", Icons.location_on),
                    const Divider(height: 30),
                    const Text("المسمى الوظيفي المطلوب:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 10),
                    ..._roles.entries.map((entry) {
                      return RadioListTile<String>(
                        title: Text(entry.value),
                        value: entry.key,
                        groupValue: _selectedRole,
                        activeColor: aksabRed,
                        onChanged: (val) => setState(() => _selectedRole = val!),
                      );
                    }).toList(),
                    if (_message != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        child: Text(_message!,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: _isSuccess ? Colors.green : aksabRed, fontWeight: FontWeight.bold)),
                      ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _register,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: aksabRed,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _isLoading
                            ? const CircularProgressIndicator(color: Colors.white)
                            : const Text("إرسال طلب الانضمام", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField(TextEditingController controller, String label, IconData icon, {bool isPass = false, bool isPhone = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: TextFormField(
        controller: controller,
        obscureText: isPass,
        textAlign: TextAlign.right,
        keyboardType: isPhone ? TextInputType.phone : TextInputType.text,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: aksabRed),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey[300]!)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey[200]!)),
          filled: true,
          fillColor: Colors.grey[50],
        ),
        validator: (v) => (v == null || v.isEmpty) ? "هذا الحقل مطلوب" : null,
      ),
    );
  }
}

