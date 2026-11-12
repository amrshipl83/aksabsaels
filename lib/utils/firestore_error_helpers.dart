// lib/utils/firestore_error_helpers.dart
// Pure helpers to surface Firestore query errors (e.g. missing composite
// index) in the UI as copyable/openable text. No Firebase dependency.

/// True when [error] looks like a missing-composite-index failure.
bool isMissingIndexError(Object? error) {
  if (error == null) return false;
  final s = error.toString().toLowerCase();
  return s.contains('failed-precondition') || s.contains('requires an index');
}

/// True when [error] looks like a security-rules rejection
/// (client is signed in but the rules deny the read).
bool isPermissionDeniedError(Object? error) {
  if (error == null) return false;
  final s = error.toString().toLowerCase();
  return s.contains('permission-denied') ||
      s.contains('permission denied') ||
      s.contains('missing or insufficient permissions');
}

/// Short Arabic description of a query/stream failure for the admin
/// screens: tells the viewer whether the read needs a missing composite
/// index (فهرس) or is blocked by the security rules (حماية), instead of
/// a generic message. Never throws.
String describeQueryErrorAr(Object? error) {
  if (isMissingIndexError(error)) {
    return 'الاستعلام يحتاج فهرس (index) غير موجود. أنشئ الفهرس من رابط وحدة التحكم ثم أعد فتح الصفحة.';
  }
  if (isPermissionDeniedError(error)) {
    return 'لا توجد صلاحية لقراءة هذه البيانات (قواعد الحماية). راجع قواعد Firestore أو صلاحية الحساب.';
  }
  return 'تعذّر جلب البيانات: ${error ?? 'خطأ غير معروف'}';
}

/// Extracts the first https:// console link from a Firestore error message
/// (the "create index" URL), or null when there is none.
/// Message for a product whose active offers all fall outside the rep's
/// current geo coverage (or location is unavailable). Pure for testing.
String geoHiddenMessage({required int totalOffers, required bool hasLocation}) {
  if (!hasLocation) {
    return 'يوجد $totalOffers عروض نشطة — فعّل الموقع لعرض المتاح منها في منطقتك';
  }
  return 'يوجد $totalOffers عروض نشطة لكن كلها خارج نطاق موقعك الحالي';
}

String? extractFirestoreIndexUrl(Object? error) {
  if (error == null) return null;
  final match = RegExp(r'https://[^\s)"]+')
      .firstMatch(error.toString());
  return match?.group(0);
}
