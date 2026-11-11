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
String? extractFirestoreIndexUrl(Object? error) {
  if (error == null) return null;
  final match = RegExp(r'https://[^\s)"]+')
      .firstMatch(error.toString());
  return match?.group(0);
}
