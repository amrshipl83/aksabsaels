// lib/screens/rep/add_new_customer_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math';
import 'package:aksab_sales/utils/phone_normalize.dart';

// Rep-created buyer is server-owned: the app sends the profile + the rep's
// ID token, the backend validates, creates the passwordless Auth user and
// the users/ buyer doc, and binds repCode/repName from the approved rep
// record. The client never chooses repCode and never sets passwords.
// Function is deployed separately as cashback_logic:repBuyer.
const String kRepBuyerEndpoint =
    'https://us-central1-aksab-erp.cloudfunctions.net/repBuyer';

/// أسباب فشل قراءة الموقع — تُترجم لرسائل مناسبة مع الإبقاء على
/// القيمة السابقة دائمًا.
enum LocationFailure {
  permissionDenied,
  permissionDeniedForever,
  serviceDisabled,
  unavailable,
}

/// رسالة المستخدم لكل سبب فشل في قراءة الموقع (خالصة، قابلة للاختبار).
String locationErrorMessage(LocationFailure kind) {
  switch (kind) {
    case LocationFailure.permissionDenied:
      return '❌ تم رفض صلاحية الموقع. فعّلها من إعدادات التطبيق ثم حدّث الموقع.';
    case LocationFailure.permissionDeniedForever:
      return '❌ صلاحية الموقع مرفوضة نهائيًا. فعّلها من إعدادات الجهاز، والقيمة السابقة محفوظة.';
    case LocationFailure.serviceDisabled:
      return '❌ خدمة الموقع (GPS) متوقفة. فعّلها ثم حدّث الموقع، والقيمة السابقة محفوظة.';
    case LocationFailure.unavailable:
      return '⚠️ تعذر تحديد الموقع الحالي. تم الإبقاء على القيمة السابقة.';
  }
}

/// جسم طلب إنشاء العميل المُرسل للخادم (خالص، قابل للاختبار).
/// الإحداثيات هي المرجع الجغرافي الوحيد؛ `landmark` وصف نصي مساعد
/// يُرسل فقط عند كتابته، ولا يدخل أي حساب جغرافي.
Map<String, dynamic> buildRepBuyerPayload({
  required String fullname,
  required String ownerName,
  required String phoneNumber,
  required String requestId,
  required String address,
  required String landmark,
  required double lat,
  required double lng,
}) {
  return {
    'fullname': fullname,
    'ownerName': ownerName,
    'phoneNumber': phoneNumber,
    'requestId': requestId,
    'address': address,
    if (landmark.trim().isNotEmpty) 'landmark': landmark.trim(),
    'country': 'egypt',
    'location': {'lat': lat, 'lng': lng},
  };
}

class AddNewCustomerScreen extends StatefulWidget {
  const AddNewCustomerScreen({super.key});

  @override
  State<AddNewCustomerScreen> createState() => _AddNewCustomerScreenState();
}

class _AddNewCustomerScreenState extends State<AddNewCustomerScreen> {
  final _formKey = GlobalKey<FormState>();

  // الكنترولرز مطابقة للتطبيق الأساسي لضمان نفس بنية البيانات
  final _nameController = TextEditingController();      // سيتم تخزينه في fullname
  final _ownerNameController = TextEditingController(); // اسم صاحب النشاط
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _landmarkController = TextEditingController();  // علامة مميزة للموقع (اختياري)

  bool _isLoading = false;
  bool _isRefreshingLocation = false;
  Position? _currentPosition;
  // مفتاح عدم التكرار لعملية التسجيل الجارية: يبقى عبر الانقطاع/المهلة،
  // ويُمسح فقط عند نتيجة نهائية (انظر _registerCustomer).
  String _requestId = '';

  @override
  void initState() {
    super.initState();
    // جلب الموقع فوراً بصمت لاعتباره مأخوذ مسبقاً
    _refreshPosition(initial: true);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ownerNameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _landmarkController.dispose();
    super.dispose();
  }

  /// إعادة قراءة الموقع الحالي من الجهاز وتحديث قيمة الموقع فقط —
  /// لا يمس أي حقل آخر في النموذج. عند أي فشل تُبقى القيمة السابقة
  /// كما هي مع رسالة مناسبة.
  Future<void> _refreshPosition({bool initial = false}) async {
    if (!mounted) return;
    setState(() {
      if (initial) {
        _isLoading = true;
      } else {
        _isRefreshingLocation = true;
      }
    });
    try {
      // خدمة الموقع متوقفة: نُبقي القيمة السابقة.
      if (!await Geolocator.isLocationServiceEnabled()) {
        _showSnackBar(locationErrorMessage(LocationFailure.serviceDisabled));
        return;
      }
      // صلاحية الموقع: طلبها عند الرفض المؤقت، ورسالة توجيه للإعدادات
      // عند الرفض النهائي — دون مساس بالقيمة السابقة في الحالتين.
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        _showSnackBar(locationErrorMessage(LocationFailure.permissionDenied));
        return;
      }
      if (permission == LocationPermission.deniedForever) {
        _showSnackBar(
            locationErrorMessage(LocationFailure.permissionDeniedForever));
        return;
      }
      // جلب الإحداثيات مباشرة
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // تحويل الإحداثيات لعنوان نصي لملء حقل العنوان تلقائياً
      List<Placemark> placemarks = await placemarkFromCoordinates(position.latitude, position.longitude);
      String address = "موقع غير محدد";
      if (placemarks.isNotEmpty) {
        Placemark p = placemarks.first;
        address = "${p.street}, ${p.locality}, ${p.subAdministrativeArea}";
      }

      if (!mounted) return;
      setState(() {
        _currentPosition = position;
        _addressController.text = address;
      });
    } catch (e) {
      _showSnackBar(
          "${locationErrorMessage(LocationFailure.unavailable)} ($e)");
    } finally {
      if (mounted) {
        setState(() {
          if (initial) {
            _isLoading = false;
          } else {
            _isRefreshingLocation = false;
          }
        });
      }
    }
  }

  void _showSnackBar(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg, style: const TextStyle(fontFamily: 'Cairo')))
      );
    }
  }

  /// Egyptian mobile in 0-format (010/011/012/015 + 8 digits), as the server expects.
  /// Delegates to the shared canonical rule (see lib/utils/phone_normalize.dart):
  /// local 01…, international 20…/+20…/0020… — all collapse to the same local
  /// form, so one number can never produce two different accounts.
  String? _normalizePhone(String raw) => normalizeEgyptianPhoneToLocal(raw);

  /// ينشئ مفتاح العملية مرة واحدة ويعيد استخدامه عند إعادة المحاولة،
  /// فيربط السيرفر المحاولات المتكررة بنفس التسجيل دون عميل مكرر.
  String _ensureRequestId() {
    if (_requestId.isEmpty) {
      final r = Random.secure();
      final bytes = List<int>.generate(16, (_) => r.nextInt(256));
      _requestId = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    }
    return _requestId;
  }

  String _duplicateMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map &&
          decoded['message'] is String &&
          (decoded['message'] as String).contains('different data')) {
        return '❌ هذه العملية استُخدمت ببيانات مختلفة. ابدأ تسجيلًا جديدًا.';
      }
    } catch (_) {}
    return '❌ هذا الرقم مسجل بالفعل.';
  }

  Future<void> _registerCustomer() async {
    // التأكد من ملء البيانات ووجود إحداثيات (اللقطة الجغرافية)
    if (!_formKey.currentState!.validate() || _currentPosition == null) {
      _showSnackBar("❌ يرجى التأكد من البيانات ولقطة الموقع");
      return;
    }

    final cleanPhone = _normalizePhone(_phoneController.text.trim());
    if (cleanPhone == null) {
      _showSnackBar("❌ رقم هاتف مصري غير صحيح (11 رقم يبدأ بـ 010/011/012/015)");
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showSnackBar("❌ انتهت الجلسة. أعد تسجيل الدخول.");
      return;
    }

    setState(() => _isLoading = true);
    try {
      final idToken = await user.getIdToken();
      final response = await http.post(
        Uri.parse(kRepBuyerEndpoint),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode(buildRepBuyerPayload(
          fullname: _nameController.text.trim(),
          ownerName: _ownerNameController.text.trim(),
          phoneNumber: cleanPhone,
          requestId: _ensureRequestId(),
          address: _addressController.text.trim(),
          landmark: _landmarkController.text,
          lat: _currentPosition!.latitude,
          lng: _currentPosition!.longitude,
        )),
      );

      if (response.statusCode == 200) {
        _requestId = '';
        if (mounted) _showSuccessDialog();
        return;
      }
      if (response.statusCode == 503 ||
          (response.statusCode >= 500 && response.statusCode <= 599)) {
        // خطأ عابر: نُبقي نفس المفتاح لتُعيد المحاولة نفس العملية دون تكرار.
        if (mounted) {
          _showSnackBar("❌ تعذر التسجيل مؤقتًا، أعد المحاولة بنفس العملية.");
        }
        return;
      }
      _requestId = '';
      if (mounted) {
        final msg = switch (response.statusCode) {
          409 => _duplicateMessage(response.body),
          400 => "❌ بيانات غير صالحة. راجع الاسم ورقم الهاتف.",
          401 || 403 => "❌ الجلسة غير مخولة. أعد تسجيل الدخول.",
          _ => "❌ تعذر التسجيل حالياً (${response.statusCode}). حاول لاحقاً.",
        };
        _showSnackBar(msg);
      }
    } catch (e) {
      _showSnackBar("❌ خطأ في الاتصال: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Text("تم التسجيل ✅", style: TextStyle(fontFamily: 'Cairo'), textAlign: TextAlign.center),
        content: const Text(
          "تم إنشاء حساب العميل من الخادم وربطه بك.\nيمكن للعميل الآن تحميل التطبيق وتسجيل الدخول المباشر برقم هاتفه وكود الـ OTP فوراً.",
          style: TextStyle(fontFamily: 'Cairo'),
          textAlign: TextAlign.center,
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2D9E68)),
              onPressed: () {
                Navigator.pop(context); // إغلاق التنبيه
                Navigator.pop(context); // العودة للقائمة الرئيسية
              },
              child: const Text("موافق", style: TextStyle(color: Colors.white, fontFamily: 'Cairo'))
            ),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("تسجيل عميل ميداني جديد", style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: const Color(0xFF2D9E68),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading && _currentPosition == null
        ? const Center(child: CircularProgressIndicator(color: Color(0xFF2D9E68)))
        : SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  const Icon(Icons.person_add_alt_1_rounded, size: 80, color: Color(0xFF2D9E68)),
                  const SizedBox(height: 20),
                  _buildInput(_nameController, "اسم المحل / السوبر ماركت *", Icons.store),
                  const SizedBox(height: 15),
                  _buildInput(_ownerNameController, "اسم صاحب النشاط (اختياري)", Icons.person_pin),
                  const SizedBox(height: 15),
                  _buildInput(_phoneController, "رقم هاتف العميل *", Icons.phone_iphone, keyboard: TextInputType.phone),
                  const SizedBox(height: 15),
                  _buildLocationRow(),
                  const SizedBox(height: 15),
                  _buildInput(
                    _landmarkController,
                    "علامة مميزة للموقع (اختياري)",
                    Icons.place_outlined,
                    hint: "بجوار مسجد كذا، أمام الصيدلية",
                  ),
                  const SizedBox(height: 30),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _registerCustomer,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2D9E68),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text("حفظ وتأمين الحساب فوراً",
                            style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }

  /// صف الموقع الحالي مع زر التحديث: نفس حقل العنوان للقراءة فقط
  /// وسلوكه كما هو، وبجانبه زر يطلب الموقع الحالي ويحدّث القيمة فقط.
  Widget _buildLocationRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _buildInput(_addressController,
              "عنوان الموقع (تلقائي من الـ GPS)", Icons.map_outlined,
              readOnly: true),
        ),
        const SizedBox(width: 8),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF2D9E68).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: const Color(0xFF2D9E68).withValues(alpha: 0.4)),
            ),
            child: IconButton(
              tooltip: 'تحديث الموقع الحالي',
              onPressed: _isRefreshingLocation || _isLoading
                  ? null
                  : () => _refreshPosition(),
              icon: _isRefreshingLocation
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF2D9E68),
                      ),
                    )
                  : const Icon(Icons.refresh,
                      color: Color(0xFF2D9E68)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInput(TextEditingController controller, String label, IconData icon,
      {bool readOnly = false, TextInputType keyboard = TextInputType.text, String? hint}) {
    return TextFormField(
      controller: controller,
      readOnly: readOnly,
      keyboardType: keyboard,
      style: const TextStyle(fontFamily: 'Cairo'),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.grey, fontFamily: 'Cairo'),
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.grey, fontFamily: 'Cairo'),
        prefixIcon: Icon(icon, color: const Color(0xFF2D9E68)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF2D9E68), width: 2),
        ),
        filled: readOnly,
        fillColor: readOnly ? Colors.grey[100] : Colors.white,
      ),
      validator: (v) {
        if (label.contains('*') && (v == null || v.isEmpty)) return "هذا الحقل مطلوب";
        if (label.contains('الهاتف') && _normalizePhone(v ?? '') == null) return "رقم هاتف مصري غير صحيح";
        return null;
      },
    );
  }
}
