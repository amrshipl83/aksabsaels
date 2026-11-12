import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

/// Backend target-distribution call (cashback_logic:distributeTarget).
///
/// Client-side Firestore transactions cannot write another user's target
/// doc (security rules allow self-only updates), so both distribution
/// dialogs save through this endpoint instead of a direct transaction.
/// The endpoint is injected at build time (filled after the function is
/// deployed — run `firebase deploy --only functions:cashback_logic:distributeTarget`):
///
///   flutter build ... --dart-define=TARGET_DISTRIBUTE_URL=https://<fn>-<hash>-uc.a.run.app
class TargetDistributeException implements Exception {
  final String message;
  const TargetDistributeException(this.message);
  @override
  String toString() => message;
}

Future<void> distributeTargetViaBackend({
  required String holderId,
  required String recipientId,
  required String kind, // 'manager_supervisor' | 'supervisor_rep'
  required String month,
  required Map<String, String> values,
}) async {
  const endpoint =
      String.fromEnvironment('TARGET_DISTRIBUTE_URL', defaultValue: '');
  if (endpoint.isEmpty) {
    throw const TargetDistributeException('لم تُضبط خدمة التوزيع بعد.');
  }
  final token = await FirebaseAuth.instance.currentUser?.getIdToken();
  if (token == null || token.isEmpty) {
    throw const TargetDistributeException('سجّل الدخول أولاً.');
  }
  late final http.Response res;
  try {
    res = await http
        .post(
          Uri.parse(endpoint),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'kind': kind,
            'holderId': holderId,
            'recipientId': recipientId,
            'month': month,
            'values': values,
          }),
        )
        .timeout(const Duration(seconds: 30));
  } on TimeoutException {
    throw const TargetDistributeException(
        'انتهت المهلة. تحقق من الاتصال وحاول مجددًا.');
  } catch (_) {
    throw const TargetDistributeException('تعذّر الاتصال بخدمة التوزيع.');
  }
  if (res.statusCode == 200) return;
  String message = 'تعذّر الحفظ.';
  try {
    final decoded = jsonDecode(res.body);
    if (decoded is Map) {
      message = decoded['message']?.toString() ?? message;
    }
  } catch (_) {}
  throw TargetDistributeException(message);
}
