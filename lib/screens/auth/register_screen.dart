// lib/screens/auth/register_screen.dart
import 'package:flutter/material.dart';
import 'package:aksab_sales/services/akedly_register_service.dart';
import 'package:aksab_sales/utils/phone_normalize.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();

  String _selectedRole = 'sales_rep';
  final AkedlyRegisterService _regService = AkedlyRegisterService();
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

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _message = null;
    });

    final rawPhone = _phoneController.text.trim();
    final normalized = normalizeEgyptianPhoneToLocal(rawPhone);
    if (normalized == null) {
      _isLoading = false;
      setState(() {
        _isSuccess = false;
        _message = 'رقم الهاتف غير صحيح. ادخل رقما مصريا صحيحا (11 رقما يبدا بـ 010/011/012/015).';
      });
      return;
    }
    final phone = normalized;

    try {
      // New flow, phase 1: create a pending request only - the server sends
      // no OTP before admin approval. The OTP arrives at first login after
      // the administration approves the request.
      await _regService.registerRequest(
        phoneNumber: phone,
        role: _selectedRole,
        profile: {
          'fullname': _nameController.text.trim(),
          'address': _addressController.text.trim(),
        },
      );

      setState(() {
        _isSuccess = true;
        _message = '✅ تم إرسال طلبك بنجاح، في انتظار موافقة الإدارة.';
      });

      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) Navigator.pop(context);
      });
    } on RegisterException catch (e) {
      setState(() {
        _isSuccess = false;
        _message = AkedlyRegisterService.resolveRegisterMessage(e.statusCode, e.body);
      });
    } catch (e) {
      setState(() {
        _isSuccess = false;
        _message = '❌ حدث خطأ غير متوقع.';
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
        title: const Text(
          "إنضم لفريق أكسب مبيعات",
          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: aksabRed,
        centerTitle: true,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
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
                    _buildField(_addressController, "محل الإقامة / المنطقة", Icons.location_on),
                    const Divider(height: 30),
                    const Text(
                      "المسمى الوظيفي المطلوب:",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, fontFamily: 'Cairo'),
                    ),
                    const SizedBox(height: 10),
                    ..._roles.entries.map((entry) {
                      return RadioListTile<String>(
                        title: Text(entry.value, style: const TextStyle(fontFamily: 'Cairo')),
                        value: entry.key,
                        groupValue: _selectedRole,
                        activeColor: aksabRed,
                        onChanged: (val) => setState(() => _selectedRole = val!),
                      );
                    }).toList(),
                    if (_message != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        child: Text(
                          _message!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _isSuccess ? Colors.green : aksabRed,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo',
                          ),
                        ),
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
                            : const Text(
                                "إرسال طلب الانضمام",
                                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                              ),
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
        style: const TextStyle(fontFamily: 'Cairo'),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontFamily: 'Cairo'),
          prefixIcon: Icon(icon, color: aksabRed),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey[300]!)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey[200]!)),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: aksabRed, width: 2),
          ),
          filled: true,
          fillColor: Colors.grey[50],
        ),
        validator: (v) {
          if (v == null || v.isEmpty) return "هذا الحقل مطلوب";
          if (isPhone && v.length < 10) return "رقم هاتف غير صحيح";
          return null;
        },
      ),
    );
  }
}
