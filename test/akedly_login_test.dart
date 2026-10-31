import 'package:flutter_test/flutter_test.dart';
import 'package:aksab_sales/services/akedly_login_service.dart';

// OTP login guards: status mapping, OTP shape, resend cooldown.
// Pure offline tests — no network, no Firebase, no real accounts.
void main() {
  group('loginErrorMessage', () {
    test('maps wrong code', () {
      expect(AkedlyLoginService.loginErrorMessage(400), contains('غير صحيح'));
    });
    test('maps pending approval', () {
      expect(
          AkedlyLoginService.loginErrorMessage(403), contains('تفعيل الإدارة'));
    });
    test('maps unknown number', () {
      expect(AkedlyLoginService.loginErrorMessage(404), contains('غير مسجل'));
    });
    test('maps expired/used code', () {
      expect(AkedlyLoginService.loginErrorMessage(410), contains('كودًا جديدًا'));
    });
    test('maps rate limiting', () {
      expect(AkedlyLoginService.loginErrorMessage(429), contains('لاحقًا'));
    });
    test('falls back to generic message otherwise', () {
      for (final code in [500, 502, 503, -1, 200]) {
        expect(AkedlyLoginService.loginErrorMessage(code), isNotEmpty);
      }
    });
  });

  group('isValidOtp', () {
    test('accepts 6 digits', () {
      expect(AkedlyLoginService.isValidOtp('123456'), isTrue);
      expect(AkedlyLoginService.isValidOtp(' 123456 '), isTrue);
    });
    test('rejects wrong shapes', () {
      expect(AkedlyLoginService.isValidOtp(''), isFalse);
      expect(AkedlyLoginService.isValidOtp('12345'), isFalse);
      expect(AkedlyLoginService.isValidOtp('1234567'), isFalse);
      expect(AkedlyLoginService.isValidOtp('12a456'), isFalse);
    });
  });

  group('resend cooldown', () {
    final now = DateTime(2026, 1, 1, 12, 0, 0);

    test('first request is always allowed', () {
      expect(AkedlyLoginService.canResendOtp(null, now), isTrue);
      expect(AkedlyLoginService.resendCooldownRemaining(null, now), 0);
    });
    test('blocks within 60s and reports remaining', () {
      final sent = now.subtract(const Duration(seconds: 10));
      expect(AkedlyLoginService.canResendOtp(sent, now), isFalse);
      expect(AkedlyLoginService.resendCooldownRemaining(sent, now), 50);
    });
    test('allows after cooldown passes', () {
      final sent = now.subtract(const Duration(seconds: 61));
      expect(AkedlyLoginService.canResendOtp(sent, now), isTrue);
      expect(AkedlyLoginService.resendCooldownRemaining(sent, now), 0);
    });
  });
}
