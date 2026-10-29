// lib/utils/firestore_helpers.dart
// Helpers to avoid Firestore whereIn crashes (empty list / >10 values).
// Read-only safe: pure Dart, no production writes.
List<List<T>> chunkList<T>(List<T> items, [int size = 10]) {
  if (items.isEmpty) return <List<T>>[];
  if (size <= 0) return <List<T>>[List<T>.from(items)];
  final out = <List<T>>[];
  for (var i = 0; i < items.length; i += size) {
    final end = (i + size > items.length) ? items.length : i + size;
    out.add(items.sublist(i, end));
  }
  return out;
}

bool isValidWhereIn<T>(List<T> items) => items.isNotEmpty && items.length <= 10;

/// Withdraw policy shared by sales flows. Client-side guard only;
/// Firestore Rules enforce the same bounds server-side.
const double kMinWithdrawAmount = 50;
const double kMaxWithdrawAmount = 100000;

/// Normalizes an Egyptian wallet number (strips spaces/dashes).
String normalizeEgyptianWallet(String raw) =>
    raw.trim().replaceAll(RegExp(r'[\s\-]'), '');

/// Egyptian mobile-wallet format: 11 digits, 010/011/012/015 prefix.
bool isValidEgyptianWallet(String raw) =>
    RegExp(r'^01[0125][0-9]{8}$').hasMatch(normalizeEgyptianWallet(raw));

/// Account validation shared by withdraw flows. Pure function for testing.
String? validateAccountNumber(String raw) {
  if (!isValidEgyptianWallet(raw)) {
    return 'أدخل رقم محفظة مصري صحيح (11 رقم يبدأ بـ 010/011/012/015)';
  }
  return null;
}

/// Amount validation shared by withdraw flows. Pure function for testing.
String? validateWithdrawAmount(String raw, double balance) {
  final amount = double.tryParse(raw.trim());
  if (amount == null || amount <= 0) return 'أدخل مبلغاً صحيحاً أكبر من صفر';
  if (amount < kMinWithdrawAmount) {
    return 'الحد الأدنى للسحب ${kMinWithdrawAmount.toStringAsFixed(0)} ج.م';
  }
  if (amount > kMaxWithdrawAmount) {
    return 'الحد الأقصى للسحب ${kMaxWithdrawAmount.toStringAsFixed(0)} ج.م';
  }
  if (amount > balance) return 'عذراً، الرصيد غير كافٍ';
  return null;
}

/// Blocks a new request while another one is still pending.
/// Pure function for testing the duplicate guard.
bool hasBlockingPendingRequest({required int pendingCount}) =>
    pendingCount > 0;

/// Role gating used by UI. Server Rules must still enforce this.
bool canEditTarget({required String? myRole, required String collection}) {
  if (myRole == 'sales_manager' && collection == 'managers') return true;
  if (myRole == 'sales_supervisor' && collection == 'salesRep') return true;
  return false;
}
