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

  // خريطة المسميات الوظيفية (تجاهلنا التحصيل برمجياً للتركيز على المبيعات)
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

    // المنطق الذكي: تحويل رقم الهاتف لإيميل للنظام
    String phone = _phoneController.text.trim();
    String smartEmail = "$phone@aksab.com";

    try {
      // 1. إنشاء الحساب في Firebase Auth باستخدام الإيميل المولد
      final userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: smartEmail,
        password: _passwordController.text,
      );

      final String uid = userCredential.user!.uid;

      // 2. تحديد الكولكشن (المناديب في pendingReps، والمدراء في pendingManagers)
      String collectionName = (_selectedRole == "sales_rep") 
          ? "pendingReps" 
          : "pendingManagers";

      // 3. حفظ البيانات في Firestore
      await FirebaseFirestore.instance.collection(collectionName).add({
        'fullname': _nameController.text.trim(),
        'email': smartEmail, // الإيميل الذكي
        'phone': phone,
        'address': _addressController.text.trim(),
        'role': _selectedRole,
        'status': "pending",
        'createdAt': FieldValue.serverTimestamp(),
        'uid': uid,
      });

      setState(() {
        _isSuccess = true;
        _message = "✅ تم التسجيل بنجاح كـ ${_roles[_selectedRole]}، في انتظار موافقة الإدارة.";
      });

      // العودة لصفحة الدخول بعد النجاح
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) Navigator.pop(context);
      });

    } on FirebaseAuthException catch (e) {
      setState(() {
        _isSuccess = false;
        if (e.code == 'email-already-in-use') {
          _message = "❌ رقم الهاتف هذا مسجل به حساب بالفعل.";
        } else if (e.code == 'weak-password') {
          _message = "❌ كلمة المرور ضعيفة جداً.";
        } else {
          _message = "❌ خطأ: ${e.message}";
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
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text("تسجيل حساب جديد"),
        backgroundColor: const Color(0xFF43B97F),
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(25),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 500),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 15)],
            ),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  const Icon(Icons.person_add, size: 50, color: Color(0xFF43B97F)),
                  const SizedBox(height: 20),
                  _buildField(_nameController, "الاسم الكامل", Icons.person),
                  _buildField(_phoneController, "رقم الهاتف (سيكون هو المعرف)", Icons.phone, isPhone: true),
                  _buildField(_passwordController, "كلمة المرور", Icons.lock, isPass: true),
                  _buildField(_addressController, "العنوان بالتفصيل", Icons.map),
                  
                  const SizedBox(height: 20),
                  const Text("اختر نوع الحساب:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 10),
                  
                  // اختيار الدور
                  ..._roles.entries.map((entry) {
                    return RadioListTile<String>(
                      title: Text(entry.value),
                      value: entry.key,
                      groupValue: _selectedRole,
                      activeColor: const Color(0xFF43B97F),
                      onChanged: (val) => setState(() => _selectedRole = val!),
                    );
                  }).toList(),

                  if (_message != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      child: Text(_message!, 
                        textAlign: TextAlign.center,
                        style: TextStyle(color: _isSuccess ? Colors.green : Colors.red, fontWeight: FontWeight.bold)),
                    ),

                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _register,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF43B97F),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _isLoading 
                        ? const CircularProgressIndicator(color: Colors.white) 
                        : const Text("إنشاء الحساب", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ),
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
          prefixIcon: Icon(icon, color: const Color(0xFF43B97F)),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: Colors.grey[50],
        ),
        validator: (v) {
          if (v == null || v.isEmpty) return "هذا الحقل مطلوب";
          if (isPhone && v.length < 11) return "رقم الهاتف غير صحيح";
          return null;
        },
      ),
    );
  }
}

