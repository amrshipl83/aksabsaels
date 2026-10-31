// lib/screens/auth/login_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:convert';
import 'register_screen.dart';
import 'package:aksab_sales/services/session_service.dart';
import 'package:aksab_sales/services/akedly_login_service.dart';
import 'package:aksab_sales/services/sales_rep_review_access.dart';

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
  final AkedlyLoginService _loginService = AkedlyLoginService();

  // Last OTP send time for the 60s resend cooldown.
  DateTime? _lastOtpSentAt;

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
    if (FirebaseAuth.instance.currentUser == null) {
      final p = await SharedPreferences.getInstance();
      await p.remove('userRole');
      await p.remove('userData');
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    if (!await SessionService.isSessionValid()) {
      await SessionService.clearSession();
      if (mounted) setState(() => _isLoading = false);
      return;
    }
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

  // دخول OTP للحسابات المعتمدة فقط. لا يوجد مسار بريد/باسورد: الهويات
  // المنشأة عبر التسجيل بلا كلمة مرور مضبوطة، والخادم هو من يقرر
  // (404 غير مسجل، 403 معلّق) وليس الواجهة.
  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    final phone = _phoneController.text.trim();

    // أرقام مراجعة Google Play: تجاوز /send بالكامل (لا SMS ولا
    // transaction ولا cooldown إرسال)، ثم حوار OTP المعتاد كما هو.
    if (SalesRepReviewAccess.isReviewNumber(phone)) {
      final normalized = SalesRepReviewAccess.normalize(phone) ?? phone;
      if (mounted) setState(() => _isLoading = false);
      final code = await _promptOtpDialog(normalized);
      if (code == null || code.isEmpty) return;
      await _reviewSignIn(normalized, code);
      return;
    }

    // Cooldown 60s: يمنع تكلفة SMS المتكررة وحظر 429.
    final remaining = AkedlyLoginService.resendCooldownRemaining(
        _lastOtpSentAt, DateTime.now());
    if (remaining > 0) {
      _showError(
          'تم إرسال كود التحقق. يرجى الانتظار $remaining ثانية قبل طلب كود جديد.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Step 1: الخادم يتحقق من التسجيل والحالة قبل إنفاق أي SMS.
      final txID = await _loginService.loginSend(phone);
      _lastOtpSentAt = DateTime.now();
      if (!mounted) return;
      setState(() => _isLoading = false);

      final code = await _promptOtpDialog(phone);
      if (code == null || code.isEmpty) return;
      await _verifyOtpCode(txID, code);
    } on LoginException catch (e) {
      _showError(e.message.isNotEmpty
          ? e.message
          : AkedlyLoginService.loginErrorMessage(e.statusCode));
    } catch (_) {
      _showError('⚠️ تعذّر إتمام العملية حاليًا. حاول لاحقًا.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<String?> _promptOtpDialog(String phone) {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('تأكيد الهوية',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Cairo')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('أدخل الكود المرسل للرقم\n$phone',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontFamily: 'Cairo')),
              const SizedBox(height: 20),
              TextField(
                controller: ctrl,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 6,
                style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 10),
                decoration: const InputDecoration(
                  counterText: '',
                  hintText: '000000',
                ),
              ),
            ],
          ),
          actions: [
            Center(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimaryColor,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 40, vertical: 12),
                ),
                onPressed: () {
                  final code = ctrl.text.trim();
                  if (AkedlyLoginService.isValidOtp(code)) {
                    Navigator.of(ctx).pop(code);
                  }
                },
                child: const Text('دخول للنظام',
                    style: TextStyle(color: Colors.white, fontFamily: 'Cairo')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // دخول حسابات مراجعة Google Play: الكود الثابت فقط (123456 كاملًا
  // وبالترتيب)، ثم دخول Firebase Auth حقيقي بالهوية المُجهزة مسبقًا —
  // لا جلسة محلية وهمية ولا Anonymous Auth. لا تُستدعى هذه الدالة إلا
  // بعد مطابقة الرقم لقائمة المراجعة، فالكود غير صالح لأي رقم آخر.
  Future<void> _reviewSignIn(String normalizedPhone, String code) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      if (!SalesRepReviewAccess.isValidReviewCode(code)) {
        _showError('❌ كود التحقق غير صحيح.');
        return;
      }
      final credential =
          await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: SalesRepReviewAccess.reviewEmail(normalizedPhone),
        password: SalesRepReviewAccess.reviewPassword(normalizedPhone),
      );
      // الدور والصلاحيات من Firestore عبر UID الحقيقي، بنفس منطق الدخول العادي.
      await _completeSignIn(credential.user);
    } on FirebaseAuthException {
      await FirebaseAuth.instance.signOut();
      _showError('❌ تعذّر دخول حساب المراجعة. تأكد من تجهيزه في Firebase Console.');
    } catch (e) {
      _showError('❌ خطأ في النظام: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// إكمال الجلسة المشترك لكلا مساري الدخول (أكدلي والمراجعة):
  /// البحث عن مستند المستخدم في salesRep ثم managers عبر UID الحقيقي،
  /// واشتراط approved، وحفظ الجلسة، والتوجيه حسب الدور.
  /// الحساب المعلق يُطرد، والمجهول يُطرد — بنفس القواعد للجميع.
  Future<void> _completeSignIn(User? user) async {
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

    if (userDocSnapshot != null &&
        userRole != null &&
        matchedCollection != null) {
      final userDocData = userDocSnapshot.data() as Map<String, dynamic>;
      userDocData['docId'] = userDocSnapshot.id;

      if (userDocData['status'] == 'approved') {
        // ✅ مناداة تحديث الإشعارات مباشرة في الفايرستور بدلاً من دالة أمازون المحذوفة
        await _updateFcmTokenInFirestore(userDocSnapshot.id, matchedCollection);

        final prefs = await SharedPreferences.getInstance();
        // ✅ التخزين باستخدام الـ encoder لضمان عدم حدوث خطأ في الـ Timestamps
        await prefs.setString(
            'userData', json.encode(userDocData, toEncodable: _encoder));
        await prefs.setString('userRole', userRole);

        if (mounted) {
          Navigator.of(context).pushReplacementNamed(
              userRole == 'sales_rep' ? '/rep_home' : '/admin_dashboard');
        }
      } else {
        await FirebaseAuth.instance.signOut();
        _showError('❌ حسابك بانتظار تفعيل الإدارة.');
      }
    } else {
      await FirebaseAuth.instance.signOut();
      _showError('❌ بياناتك غير موجودة في سجلات مبيعات أكسب.');
    }
  }

  Future<void> _verifyOtpCode(String txID, String code) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      // لا يُستدعى /verify هنا أبدًا: العملية أحادية الاستخدام، وتحقق مسبق
      // يحرقها فيفشل /mint بـ410 على كود صحيح.
      final token = await _loginService.loginMint(
          transactionReqID: txID, otp: code);
      final userCredential =
          await FirebaseAuth.instance.signInWithCustomToken(token);

      // الدور والجلسة من Firestore عبر UID الحقيقي — نفس المنطق لكلا المسارين.
      await _completeSignIn(userCredential.user);
    } on LoginException catch (e) {
      // العملية المحترقة (410) لا تصلح لإعادة المحاولة: يلزم كود جديد
      // (المستخدم يطلب كودًا جديدًا بزر الدخول بعد انتهاء الـ cooldown).
      _showError(e.message.isNotEmpty
          ? e.message
          : AkedlyLoginService.loginErrorMessage(e.statusCode));
    } on FirebaseAuthException {
      await FirebaseAuth.instance.signOut();
      _showError('❌ تعذّر إتمام الدخول. حاول لاحقًا.');
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
                            : const Text('إرسال كود الدخول', style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
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
