import 'package:flutter_test/flutter_test.dart';
import 'package:aksab_sales/services/akedly_register_service.dart';

// Register-request guards for the approval-first flow (request now, OTP at
// first login after admin approval): status mapping only.
// Pure offline tests — no network, no Firebase, no real accounts.
void main() {
  group('registerErrorMessage', () {
    test('maps already-registered number', () {
      expect(AkedlyRegisterService.registerErrorMessage(409),
          contains('مسجل بالفعل'));
    });
    test('maps invalid data', () {
      expect(AkedlyRegisterService.registerErrorMessage(400),
          contains('غير صالحة'));
    });
    test('maps rate limiting', () {
      expect(
          AkedlyRegisterService.registerErrorMessage(429), contains('لاحقًا'));
    });
    test('falls back to generic message otherwise', () {
      for (final code in [500, 502, 503, -1, 200]) {
        expect(AkedlyRegisterService.registerErrorMessage(code), isNotEmpty);
      }
    });
    test('never echoes the raw status code', () {
      for (final code in [400, 409, 429, 500]) {
        expect(AkedlyRegisterService.registerErrorMessage(code),
            isNot(contains('$code')));
      }
    });
  });
}
