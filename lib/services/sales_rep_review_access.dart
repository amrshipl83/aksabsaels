// lib/services/sales_rep_review_access.dart
// أرقام مراجعة Google Play لتطبيق مندوب المبيعات (Aksab Sales Rep).
//
// نفس مبدأ My Test App: مطابقة حرفية للرقم ← تجاوز /send ← حوار OTP
// المعتاد ← قبول 123456 محليًا ← دخول Firebase Auth حقيقي بهوية
// مُجهزة مسبقًا ← الدور من مستند Firestore عبر UID الحقيقي.
//
// منع التعارض مع My Test App (نفس مشروع Firebase `aksab-erp`):
// - My Test App تستخدم `<phone>@aksab.com` / `Rabia_<phone>`، بل وتنشئ
//   حسابات `<phone>@aksab.com` بكلمة `123456` للموظفين الفرعيين.
// - لذلك تستخدم هذه الآلية نطاقًا مختلفًا تمامًا للبريد وكلمة سر
//   باشتقاق مختلف، فلا تشترك مع أي هوية My Test App في نفس الحساب.
//   لا يُعاد استخدام حسابات My Test App ولا تُعدَّل.
//
// تحذير أمني: كلمة المرور مشتقة حتميًا من الرقم، أي أن أي شخص يقرأ
// هذا الملف (أو يفكك التطبيق) يستطيع حسابها. هذا مقبول فقط لأن:
// (1) الحسابات مخصصة للمراجعة ومعزولة عن بيانات العملاء،
// (2) لا توجد هنا أسرار إدارية أو Service Account credentials،
// (3) يُنصح بتدوير كلمات السر بعد انتهاء مراجعة Google Play.
// Pure Dart بلا اعتماد على Flutter ليسهل اختباره.
class SalesRepReviewAccess {
  /// معرّف خطوة المراجعة داخل حوار OTP (لا يُرسل لأي خدمة).
  static const String reviewStepId = 'REVIEW_LOCAL_SALES';

  /// الكود الثابت الوحيد المقبول لأرقام المراجعة.
  static const String reviewCode = '123456';

  /// الأرقام الثلاثة بصيغتها المحلية (11 رقمًا).
  static const List<String> reviewPhones = [
    '01021070462', // مندوب sales_rep
    '01021070461', // مشرف sales_supervisor
    '01021070463', // مدير sales_manager
  ];

  /// الدور المتوقع لكل رقم (للفحص والتوثيق؛ الدور الفعلي يُقرأ دائمًا
  /// من مستند Firestore بعد الدخول ولا يُمنح من التطبيق).
  static const Map<String, String> reviewRoles = {
    '01021070462': 'sales_rep',
    '01021070461': 'sales_supervisor',
    '01021070463': 'sales_manager',
  };

  /// تطبيع الرقم المصري إلى الصيغة المحلية 01xxxxxxxxx.
  /// يقبل الصيغة المحلية والدولية (20/+20/0020) مع تجاهل الفواصل.
  /// يرجع null عندما لا يمكن اشتقاق صيغة محلية صالحة.
  static String? normalize(String raw) {
    final digits = raw.trim().replaceAll(RegExp(r'\D'), '');
    if (RegExp(r'^01[0125]\d{8}$').hasMatch(digits)) return digits;
    if (RegExp(r'^201[0125]\d{8}$').hasMatch(digits)) {
      return '0${digits.substring(2)}';
    }
    if (digits.startsWith('0020')) {
      final rest = digits.substring(4);
      if (RegExp(r'^1[0125]\d{8}$').hasMatch(rest)) return '0$rest';
    }
    return null;
  }

  /// هل هذا الرقم أحد أرقام المراجعة الثلاثة؟ (بعد التطبيع)
  /// مطابقة حرفية على القائمة فقط — لا أنماط عامة.
  static bool isReviewNumber(String raw) {
    final normalized = normalize(raw);
    return normalized != null && reviewPhones.contains(normalized);
  }

  /// قبول الكود الثابت فقط، كاملًا وبالترتيب (المساواة تقتضي الترتيب).
  static bool isValidReviewCode(String code) => code.trim() == reviewCode;

  /// بريد الهوية الحقيقية المُجهزة مسبقًا في Firebase Console.
  /// نطاق مختلف عمدًا عن `<phone>@aksab.com` الخاص بـ My Test App
  /// حتى لا يحدث أي اشتراك في نفس حساب Auth.
  static String reviewEmail(String normalizedPhone) =>
      'review-$normalizedPhone@aksab-sales-review.com';

  /// كلمة سر الهوية المُجهزة. اشتقاق مختلف عمدًا عن `Rabia_<phone>`
  /// الخاص بـ My Test App. راجع التحذير الأمني أعلى الملف.
  static String reviewPassword(String normalizedPhone) =>
      'AksabSalesReview#$normalizedPhone';

  /// المجموعة المتوقعة لمستند الدور (للفحص والتوثيق فقط).
  static String expectedCollection(String role) =>
      role == 'sales_rep' ? 'salesRep' : 'managers';
}
