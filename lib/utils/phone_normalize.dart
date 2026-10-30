// lib/utils/phone_normalize.dart
// Pure-Dart Egyptian mobile normalization for the sales-rep client.
// Canonical rule — mirrors backend akedly.js normalizePhone output forms
// and rep_buyer.js normalizeEgyptianMobile:
//   1. strip non-digits (spaces, dashes, '+', …);
//   2. strip ONE leading '00' (0020… → 20…);
//   3. '01[0125]xxxxxxxx' (11 digits) is the local form, returned as-is;
//   4. '201[0125]xxxxxxxx' (12 digits) → local '0' + substring(2).
// Returns null when no valid local form can be derived — the caller must
// reject the input (no account, no OTP, no lookup).
// Pure Dart, no Flutter dependency — unit-testable.
String? normalizeEgyptianPhoneToLocal(String raw) {
  final digits = raw.trim().replaceAll(RegExp(r'\D'), '');
  final canonical = digits.startsWith('00') ? digits.substring(2) : digits;
  if (RegExp(r'^01[0125]\d{8}$').hasMatch(canonical)) return canonical;
  if (RegExp(r'^201[0125]\d{8}$').hasMatch(canonical)) {
    return '0${canonical.substring(2)}';
  }
  return null;
}
