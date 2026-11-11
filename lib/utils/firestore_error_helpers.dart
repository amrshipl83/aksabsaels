// lib/utils/firestore_error_helpers.dart
// Pure helpers to surface Firestore query errors (e.g. missing composite
// index) in the UI as copyable/openable text. No Firebase dependency.

/// True when [error] looks like a missing-composite-index failure.
bool isMissingIndexError(Object? error) {
  if (error == null) return false;
  final s = error.toString().toLowerCase();
  return s.contains('failed-precondition') || s.contains('requires an index');
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
