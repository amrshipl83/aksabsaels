// lib/services/akedly_register_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

// F3 registration proxy for the sales app: OTP proof + identity creation run
// on the backend only. The client never creates Auth users, never chooses a
// collection, and never sets roles/status — the server binds role (sales_rep
// -> pendingReps, sales_supervisor/sales_manager -> pendingManagers) from its
// own map after OTP verification. No Akedly keys live in the client.
class AkedlyRegisterService {
  static const String _baseUrl =
      'https://us-central1-aksab-erp.cloudfunctions.net/akedly';

  /// Step 1 — backend OTP-proves an UNKNOWN phone for [role].
  /// Known numbers come back as failure (409 already registered).
  Future<RegisterSendResult> registerSend(
      String phoneNumber, String role) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phoneNumber': phoneNumber, 'role': role}),
      );
      final resData =
          response.body.isNotEmpty ? jsonDecode(response.body) : null;
      if (response.statusCode == 200) {
        final data = resData is Map ? resData['data'] : null;
        String? transactionReqID;
        if (data is Map && data['transactionReqID'] != null) {
          transactionReqID = data['transactionReqID'].toString();
        }
        return RegisterSendResult.success(data: transactionReqID ?? '');
      }
      String? message;
      if (resData is Map && resData['message'] != null) {
        message = resData['message'].toString();
      }
      return RegisterSendResult.failure(message: message ?? 'فشل بدء التسجيل');
    } catch (e) {
      return RegisterSendResult.failure(message: 'خطأ تقني في الاتصال: $e');
    }
  }

  /// Phase 1 of the new flow — create a pending request, no OTP.
  /// The server stores a `pending` doc for server-side admin review and
  /// sends the OTP only after approval, at first login. Returns the
  /// requestId (canonical 20-form phone). Throws [RegisterException]
  /// carrying the backend status (400 invalid, 409 already registered,
  /// 429 limited) for UI mapping.
  Future<String> registerRequest({
    required String phoneNumber,
    required String role,
    required Map<String, dynamic> profile,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/register-request'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'phoneNumber': phoneNumber,
        'role': role,
        'profile': profile,
      }),
    );
    final resData =
        response.body.isNotEmpty ? jsonDecode(response.body) : null;
    if (response.statusCode == 200) {
      final data = resData is Map ? resData['data'] : null;
      if (data is Map && data['requestId'] != null) {
        return data['requestId'].toString();
      }
    }
    String? message;
    if (resData is Map && resData['message'] != null) {
      message = resData['message'].toString();
    }
    throw RegisterException(response.statusCode, message ?? response.body);
  }

  /// Maps register-request failures to user-facing Arabic messages. Pure.
  static String registerErrorMessage(int statusCode) {
    switch (statusCode) {
      case 400:
        return '❌ بيانات التسجيل غير صالحة. راجع الحقول وحاول مجددًا.';
      case 409:
        return '❌ رقم الهاتف هذا مسجل بالفعل.';
      case 429:
        return '⚠️ محاولات كثيرة. حاول لاحقًا.';
      default:
        return '❌ تعذّر إتمام التسجيل حاليًا.';
    }
  }

  /// Step 2 — server verifies OTP then creates the passwordless identity.
  /// Throws [RegisterException] carrying the backend status
  /// (400/403/404/409/410/429) for UI mapping.
  Future<RegisterResult> registerVerify({
    required String transactionReqID,
    required String otp,
    required String phoneNumber,
    required Map<String, dynamic> profile,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/register-verify'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'transactionReqID': transactionReqID,
        'otp': otp,
        'phoneNumber': phoneNumber,
        'profile': profile,
      }),
    );
    if (response.statusCode == 200) {
      final resData =
          response.body.isNotEmpty ? jsonDecode(response.body) : null;
      if (resData is Map && resData['customToken'] is String) {
        return RegisterResult(
          customToken: resData['customToken'] as String,
          role: resData['role']?.toString() ?? '',
          collection: resData['collection']?.toString() ?? '',
          status: resData['status']?.toString() ?? '',
        );
      }
    }
    throw RegisterException(response.statusCode, response.body);
  }
}

class RegisterSendResult {
  final bool isSuccess;
  final String? message;
  final String? data;
  RegisterSendResult.success({this.data})
      : isSuccess = true,
        message = null;
  RegisterSendResult.failure({required this.message})
      : isSuccess = false,
        data = null;
}

/// Registration failure carrying the backend status code for UI mapping.
class RegisterException implements Exception {
  final int statusCode;
  final String body;
  RegisterException(this.statusCode, this.body);
}

/// Registration success — identity created server-side in [collection]
/// with [status] (pending = admin review before login).
class RegisterResult {
  final String customToken;
  final String role;
  final String collection;
  final String status;
  RegisterResult({
    required this.customToken,
    required this.role,
    required this.collection,
    required this.status,
  });
}
