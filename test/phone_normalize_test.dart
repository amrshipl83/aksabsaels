import 'package:flutter_test/flutter_test.dart';
import 'package:aksab_sales/utils/phone_normalize.dart';

// Phase 3: client-side canonical rule — every accepted spelling of one
// Egyptian mobile number must collapse to the SAME local 0-form, so the
// sales app can never create two accounts (or miss one) for one number.
// Mirrors backend akedly.js normalizePhone output forms and
// rep_buyer.js normalizeEgyptianMobile.
void main() {
  group('normalizeEgyptianPhoneToLocal', () {
    const cases = <List<String>>[
      // [input, expectedLocal]
      ['01021070462', '01021070462'],
      ['201021070462', '01021070462'],
      ['+201021070462', '01021070462'],
      ['00201021070462', '01021070462'],
      ['010 2107 0462', '01021070462'],
      ['010-2107-0462', '01021070462'],
      ['01112345678', '01112345678'],
      ['201112345678', '01112345678'],
      ['+201112345678', '01112345678'],
      ['00201112345678', '01112345678'],
      ['01278287168', '01278287168'],
      ['201278287168', '01278287168'],
      ['00201278287168', '01278287168'],
      ['01551445210', '01551445210'],
      ['201551445210', '01551445210'],
      ['+201551445210', '01551445210'],
      ['00201551445210', '01551445210'],
    ];

    for (final c in cases) {
      test('normalizes "${c[0]}" to "${c[1]}"', () {
        expect(normalizeEgyptianPhoneToLocal(c[0]), c[1]);
      });
    }

    test('rejects invalid input with null (no account, no OTP, no lookup)', () {
      for (final bad in [
        '',
        'abc',
        '123',
        '0102107046',
        '010210704621',
        '0212345678', // landline
        '01912345678', // invalid mobile prefix
        '201912345678',
      ]) {
        expect(normalizeEgyptianPhoneToLocal(bad), isNull,
            reason: 'input: $bad');
      }
    });

    test('201-form uses substring(2), never the old substring(3) garbage', () {
      // Regression: substring(3) produced '0021070462' for 201021070462.
      final out = normalizeEgyptianPhoneToLocal('201021070462')!;
      expect(out.length, 11);
      expect(out.startsWith('010'), isTrue);
    });
  });
}
