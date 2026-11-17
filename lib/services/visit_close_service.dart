// منطق الإغلاق اليدوي الموثوق للزيارات (visit close reliability).
//
// القاعدة: الإغلاق اليدوي عملية ذرية واحدة — إعادة قراءة الحالة داخل
// Transaction والتأكد أنها `in_progress`، ثم كتابة الحالة النهائية و
// `endTime` والملاحظات معًا. أي فشل يُبقي الحالة المحلية كما هي ويسمح
// بإعادة المحاولة دون إنشاء زيارة مكررة (إعادة التنفيذ آمنة لأن الـ
// Transaction تعيد التحقق في كل مرة).
//
// الكتابة على زيارة مغلقة مسبقًا ممنوعة تمامًا: لا نغيّر حالتها ولا نمحو
// ملاحظاتها ولا نستبدل وقت إغلاقها — نكتفي بإسقاط المعرف المحلي القديم،
// وبدء زيارة جديدة يكون دائمًا بمستند ومعرّف جديدين.
library;

import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';

/// الحالات النهائية المسموح بها للإغلاق اليدوي — نفس قيم القائمة في
/// شاشة الزيارة (sold / followup / busy / rejected).
const Set<String> manualVisitCloseStatuses = <String>{
  'sold',
  'followup',
  'busy',
  'rejected',
};

/// قرار الإغلاق بعد قراءة المستند من السيرفر.
enum CloseTargetDecision {
  /// المستند موجود وحالته `in_progress` — يجوز الإغلاق.
  proceed,

  /// المستند موجود لكن حالته ليست `in_progress` — مغلق مسبقًا، ممنوع الكتابة.
  alreadyClosed,

  /// المستند غير موجود.
  missing,
}

/// نتيجة محاولة الإغلاق الموثوق.
enum VisitCloseOutcome {
  /// أُغلق وتم التحقق من الحالة النهائية.
  closed,

  /// كان مغلقًا مسبقًا — لم يُكتب شيء.
  alreadyClosed,

  /// المستند غير موجود — لم يُكتب شيء.
  missing,

  /// فشل قبل التأكد من الحفظ — الحالة المحلية محفوظة ويجوز إعادة المحاولة.
  failed,
}

class VisitCloseResult {
  final VisitCloseOutcome outcome;

  /// الحالة الفعلية على السيرفر عند الاكتشاف (لـ alreadyClosed فقط).
  final String? actualStatus;

  /// هل إعادة المحاولة مجدية؟ (لـ failed فقط).
  final bool retryable;

  const VisitCloseResult._(this.outcome, {this.actualStatus, this.retryable = false});

  const VisitCloseResult.closed() : this._(VisitCloseOutcome.closed);

  const VisitCloseResult.alreadyClosed(String? actualStatus)
      : this._(VisitCloseOutcome.alreadyClosed, actualStatus: actualStatus);

  const VisitCloseResult.missing() : this._(VisitCloseOutcome.missing);

  const VisitCloseResult.failed({required bool retryable})
      : this._(VisitCloseOutcome.failed, retryable: retryable);
}

/// تصنيف مستند الزيارة لغرض الإغلاق — خالص وقابل للاختبار دون شبكة.
/// يقبل `null` للمستند غير الموجود.
CloseTargetDecision classifyCloseTarget(Map<String, dynamic>? data) {
  if (data == null) return CloseTargetDecision.missing;
  if (data['status'] == 'in_progress') return CloseTargetDecision.proceed;
  return CloseTargetDecision.alreadyClosed;
}

/// هل يجوز اعتبار الزيارة نشطة عند الاستئناف من المعرف المحلي؟
/// أي حالة غير `in_progress` (أو غياب المستند) تعني: لا تستأنف.
bool shouldResumeVisit(Map<String, dynamic>? data) {
  return data != null && data['status'] == 'in_progress';
}

/// حمولة كتابة الإغلاق — الحالة النهائية و`endTime` والملاحظات معًا في
/// عملية واحدة (لا كتابة متفرقة أبدًا).
///
/// `serverTimestamp` حقنة اختبار فقط: الإنتاج يمرّر nothing فيُستخدم
/// `FieldValue.serverTimestamp()` الحقيقي، والاختبارات تمرّر طابعًا ثابتًا
/// لأن نسخة `fake_cloud_firestore` المقفلة لا تقبل كائنات FieldValue من
/// إصدار `cloud_firestore` الأحدث (انحراف نسخ في بيئة الاختبار فقط، ولا
/// علاقة له بسلوك الإنتاج).
Map<String, Object?> buildCloseUpdate({
  required String status,
  required String notes,
  Map<String, double>? location,
  Object? Function()? serverTimestamp,
}) {
  return <String, Object?>{
    'status': status,
    'notes': notes,
    'endTime': serverTimestamp != null
        ? serverTimestamp()
        : FieldValue.serverTimestamp(),
    'location': location == null
        ? null
        : <String, double>{'lat': location['lat']!, 'lng': location['lng']!},
  };
}

/// تصنيف خطأ الإغلاق إلى (قابل لإعادة المحاولة أم لا).
/// الافتراض الآمن: أي خطأ غير مفهوم = قابل لإعادة المحاولة، لأن إعادة
/// المحاولة نفسها آمنة (الـ Transaction تعيد التحقق وتمنع التكرار).
/// الاستثناء الوحيد: رفض الصلاحيات — إعادة المحاولة لن تنجح.
({bool retryable, String code}) classifyCloseError(Object error) {
  if (error is FirebaseException) {
    if (error.code == 'permission-denied') {
      return (retryable: false, code: 'permission-denied');
    }
    return (retryable: true, code: 'transient:${error.code}');
  }
  if (error is SocketException || error is TimeoutException) {
    return (retryable: true, code: 'network');
  }
  return (retryable: true, code: 'unknown');
}

/// رسالة عربية للحالة — خالصة وقابلة للاختبار.
String visitCloseMessage(VisitCloseResult result) {
  switch (result.outcome) {
    case VisitCloseOutcome.closed:
      return '✅ تم إغلاق الزيارة وحفظها بنجاح';
    case VisitCloseOutcome.alreadyClosed:
      return 'ℹ️ هذه الزيارة مغلقة مسبقًا (${result.actualStatus ?? 'بحالة نهائية'}) — لم يتم تغيير أي بيانات. يمكنك بدء زيارة جديدة.';
    case VisitCloseOutcome.missing:
      return '⚠️ تعذّر العثور على الزيارة على السيرفر — قد تكون حُذفت. يمكنك بدء زيارة جديدة.';
    case VisitCloseOutcome.failed:
      return result.retryable
          ? '⚠️ تعذر حفظ الإغلاق (انقطاع أو مهلة شبكة). بيانات الزيارة محفوظة — أعد المحاولة دون خوف من التكرار.'
          : '⛔ تعذر الحفظ بسبب الصلاحيات. تواصل مع الإدارة ولا تعيد المحاولة.';
  }
}

/// الأثر على الجلسة المحلية — خالص وقابل للاختبار.
/// القاعدة: لا يُمسح المعرف المحلي إلا بعد نجاح مؤكد أو ثبوت أن السيرفر
/// لم يعد يعتبر الزيارة مفتوحة. عند الفشل يُحتفظ بكل شيء.
({bool clearLocal, bool canRetry}) effectForResult(VisitCloseResult result) {
  switch (result.outcome) {
    case VisitCloseOutcome.closed:
    case VisitCloseOutcome.alreadyClosed:
    case VisitCloseOutcome.missing:
      return (clearLocal: true, canRetry: false);
    case VisitCloseOutcome.failed:
      return (clearLocal: false, canRetry: true);
  }
}

/// إغلاق يدوي موثوق لزيارة واحدة.
///
/// 1. داخل Transaction: إعادة قراءة المستند والتحقق أن حالته `in_progress`.
/// 2. عندها فقط: كتابة الحالة النهائية و`endTime` والملاحظات معًا.
/// 3. بعد الـ commit: إعادة قراءة تحقق — لا نجاح إلا إذا طابقت الحالة.
/// 4. الزيارة المغلقة مسبقًا أو الغائبة: لا كتابة إطلاقًا (حماية الملاحظات
///    ووقت الإغلاق الأصليين).
/// 5. أي استثناء: فشل مع الحفاظ على كل شيء — والدالة نفسها لا تمس
///    `SharedPreferences` إطلاقًا (قرار المسح للواجهة عبر [effectForResult]).
Future<VisitCloseResult> closeVisitReliably({
  required FirebaseFirestore db,
  required String visitId,
  required String status,
  required String notes,
  Map<String, double>? location,

  /// حقنة اختبار فقط — تُمرَّر إلى [buildCloseUpdate] (انظر توثيقها).
  /// الإنتاج لا يمرّرها أبدًا فيُستخدم ختم الخادم الحقيقي.
  Object? Function()? serverTimestamp,
}) async {
  assert(
    manualVisitCloseStatuses.contains(status),
    'status must be a manual close status: $status',
  );
  try {
    final decision = await db.runTransaction<CloseTargetDecision>((tx) async {
      final ref = db.collection('visits').doc(visitId);
      final snap = await tx.get(ref);
      if (!snap.exists) return CloseTargetDecision.missing;
      if (snap.data()?['status'] != 'in_progress') {
        return CloseTargetDecision.alreadyClosed;
      }
      tx.update(
        ref,
        buildCloseUpdate(
          status: status,
          notes: notes,
          location: location,
          serverTimestamp: serverTimestamp,
        ),
      );
      return CloseTargetDecision.proceed;
    });

    if (decision == CloseTargetDecision.missing) {
      return const VisitCloseResult.missing();
    }
    if (decision == CloseTargetDecision.alreadyClosed) {
      final current = await db.collection('visits').doc(visitId).get();
      return VisitCloseResult.alreadyClosed(
        current.data()?['status']?.toString(),
      );
    }

    // تحقق لاحق: لا نعلن النجاح إلا إذا طابقت الحالة النهائية المطلوبة.
    final verify = await db.collection('visits').doc(visitId).get();
    if (verify.data()?['status'] == status) {
      return const VisitCloseResult.closed();
    }
    final failure = classifyCloseError(StateError('verification-mismatch'));
    return VisitCloseResult.failed(retryable: failure.retryable);
  } catch (e) {
    final failure = classifyCloseError(e);
    return VisitCloseResult.failed(retryable: failure.retryable);
  }
}

/// أحدث زيارة `in_progress` للمندوب على السيرفر (لمنع إنشاء زيارة مكررة
/// عند بدء زيارة جديدة، وللتحقق قبل الاستئناف من المعرف المحلي).
/// يعيد `null` عند غياب أي زيارة مفتوحة.
Future<String?> findOpenVisitId({
  required FirebaseFirestore db,
  required String repCode,
}) async {
  final snap = await db
      .collection('visits')
      .where('repCode', isEqualTo: repCode)
      .where('status', isEqualTo: 'in_progress')
      .limit(1)
      .get();
  if (snap.docs.isEmpty) return null;
  return snap.docs.first.id;
}
