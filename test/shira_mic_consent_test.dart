import 'package:flutter_test/flutter_test.dart';
import 'package:aksab_sales/services/shira_mic_consent.dart';

void main() {
  group('ShiraMicConsent.shouldShowDisclosure', () {
    test('first run (null) shows the disclosure', () {
      expect(ShiraMicConsent.shouldShowDisclosure(null), isTrue);
    });

    test('explicitly declined shows the disclosure again', () {
      expect(ShiraMicConsent.shouldShowDisclosure(false), isTrue);
    });

    test('accepted once never shows it again', () {
      expect(ShiraMicConsent.shouldShowDisclosure(true), isFalse);
    });
  });

  test('prefs key is stable (existing consents keep working)', () {
    expect(ShiraMicConsent.prefsKey, 'shira_mic_disclosure_accepted_v1');
  });
}
