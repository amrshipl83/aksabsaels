// lib/services/akedly_login_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

// OTP login for approved sales accounts (sales_rep / sales_supervisor /
// sales_manager). Pattern mirrors the reference Akedly integration:
//   Step 1 — POST /send {phoneNumber, flow:'sales'} -> transactionReqID.
//   Step 2 — POST /mint {transactionReqID, otp} -> Firebase custom token,
//            then the caller signs in with FirebaseAuth.signInWithCustomToken.
// Never call any /verify endpoint before /mint: transactions are single-use
// and a prior verify would burn them, making every later /mint fail with 410.
//
// The server enforces the approval rule, not this client: unknown phones get
// 404 and pending accounts get 403 on both /send and /mint. This client maps
// statuses to messages and never decides roles itself.
class AkedlyLoginService {
  static const String _baseUrl =
      'https://us-central1-aksab-erp.cloudfunctions.net/akedly';

  /// Step 1 — ask the backend to send a login OTP to a KNOWN phone.
  /// Returns the transactionReqID. Throws [LoginException] carrying the
  /// backend status (400 invalid, 403 pending, 404 unknown, 429 limited,
  /// 5xx unavailable).
  Future<String> loginSend(String phoneNumber) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/send'),
      headers: {'Content-Type': 'application/json'},
      // flow:'sales' documents intent; the server currently only honors
      // 'driver' and falls back to 'main' — a sales flow must be enabled
      // server-side before sales numbers resolve (see report).
      body: jsonEncode({'phoneNumber': phoneNumber, 'flow': 'sales'}),
    );
    final resData = _decode(response.body);
    if (response.statusCode == 200) {
      final data = resData is Map ? resData['data'] : null;
      String? tx;
      if (data is Map && data['transactionReqID'] != null) {
        tx = data['transactionReqID'].toString();
      } else if (resData is Map && resData['transactionReqID'] != null) {
        tx = resData['transactionReqID'].toString();
      }
      if (tx != null && tx.isNotEmpty) return tx;
    }
    throw LoginException(response.statusCode, _serverMessage(resData));
  }

  /// Step 2 — the server verifies the OTP and mints a Firebase custom token.
  /// Returns the token. Throws [LoginException] carrying the backend status
  /// (400 wrong code, 403 pending, 404 unknown tx/user, 410 expired/used,
  /// 429 limited, 5xx unavailable).
  Future<String> loginMint({
    required String transactionReqID,
    required String otp,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/mint'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'transactionReqID': transactionReqID, 'otp': otp}),
    );
    final resData = _decode(response.body);
    if (response.statusCode == 200) {
      final token = resData is Map ? resData['customToken'] : null;
      if (token is String && token.isNotEmpty) return token;
    }
    throw LoginException(response.statusCode, _serverMessage(resData));
  }

  static dynamic _decode(String body) {
    if (body.isEmpty) return null;
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  static String _serverMessage(dynamic resData) {
    if (resData is Map && resData['message'] != null) {
      return resData['message'].toString();
    }
    return '';
  }

  /// Maps backend statuses to user-facing Arabic messages. Pure for testing.
  /// Callers should prefer the server message when non-empty (it is already
  /// user-facing), falling back to this map.
  static String loginErrorMessage(int statusCode) {
    switch (statusCode) {
      case 400:
        return '❌ كود التحقق غير صحيح.';
      case 403:
        return '⏳ حسابك بانتظار تفعيل الإدارة.';
      case 404:
        return '❌ هذا الرقم غير مسجل في فريق المبيعات.';
      case 410:
        return '❌ انتهت صلاحية الكود أو تم استخدامه. اطلب كودًا جديدًا.';
      case 429:
        return '⚠️ محاولات كثيرة. حاول لاحقًا.';
      default:
        return '⚠️ تعذّر إتمام العملية حاليًا. حاول لاحقًا.';
    }
  }

  /// OTP shape check for the dialog (Akedly SMS codes are 6 digits).
  static bool isValidOtp(String raw) => RegExp(r'^\d{6}$').hasMatch(raw.trim());

  /// Resend cooldown guard (60s) to avoid SMS cost and 429s. Pure for testing.
  static bool canResendOtp(DateTime? lastSentAt, DateTime now,
      {int cooldownSeconds = 60}) {
    if (lastSentAt == null) return true;
    return now.difference(lastSentAt).inSeconds >= cooldownSeconds;
  }

  static int resendCooldownRemaining(DateTime? lastSentAt, DateTime now,
      {int cooldownSeconds = 60}) {
    if (lastSentAt == null) return 0;
    final rest = cooldownSeconds - now.difference(lastSentAt).inSeconds;
    return rest > 0 ? rest : 0;
  }
}

/// Login failure carrying the backend status code for UI mapping.
class LoginException implements Exception {
  final int statusCode;
  final String message;
  LoginException(this.statusCode, this.message);
}
