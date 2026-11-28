import 'package:flutter_test/flutter_test.dart';
import 'package:aksab_sales/utils/gift_eligibility.dart';

// BUYER-parity ports: status/expiry/budget liveness (fail-closed),
// trigger-line extraction. Firestore reads stay in the screens.
void main() {
  Map<String, dynamic> promo(Map<String, dynamic> m) => m;

  group('parseGiftExpiry', () {
    test('accepts DateTime and ISO strings', () {
      final d = DateTime(2026, 5, 1);
      expect(parseGiftExpiry(d), d);
      expect(parseGiftExpiry('2026-05-01T00:00:00.000'), isNotNull);
    });
    test('rejects blank and garbage', () {
      expect(parseGiftExpiry(null), isNull);
      expect(parseGiftExpiry(''), isNull);
      expect(parseGiftExpiry('not-a-date'), isNull);
      expect(parseGiftExpiry(12345), isNull);
    });
  });

  group('giftPromoRemaining', () {
    test('max minus used', () {
      expect(giftPromoRemaining({'maxQuantity': 10, 'usedQuantity': 3}), 7);
    });
    test('missing or non-positive max means zero (not unlimited)', () {
      expect(giftPromoRemaining({}), 0);
      expect(giftPromoRemaining({'maxQuantity': 0, 'usedQuantity': 0}), 0);
      expect(giftPromoRemaining({'maxQuantity': -2}), 0);
    });
    test('never negative', () {
      expect(giftPromoRemaining({'maxQuantity': 2, 'usedQuantity': 9}), 0);
    });
  });

  group('isGiftPromoLive', () {
    final now = DateTime(2026, 1, 1);
    test('live promo passes', () {
      expect(
        isGiftPromoLive(
          promo({
            'status': 'active',
            'expiryDate': '2027-01-01T00:00:00.000',
            'maxQuantity': 5,
            'usedQuantity': 1,
          }),
          now,
        ),
        isTrue,
      );
    });
    test('non-active status fails', () {
      expect(
        isGiftPromoLive(
            promo({'status': 'disabled', 'maxQuantity': 5}), now),
        isFalse,
      );
    });
    test('expired promo fails', () {
      expect(
        isGiftPromoLive(
          promo({
            'status': 'active',
            'expiryDate': '2025-01-01T00:00:00.000',
            'maxQuantity': 5,
          }),
          now,
        ),
        isFalse,
      );
    });
    test('unparseable expiry fails closed', () {
      expect(
        isGiftPromoLive(
          promo({
            'status': 'active',
            'expiryDate': 'soon-ish',
            'maxQuantity': 5,
          }),
          now,
        ),
        isFalse,
      );
    });
    test('exhausted budget fails even without expiry', () {
      expect(
        isGiftPromoLive(
          promo({'status': 'active', 'maxQuantity': 4, 'usedQuantity': 4}),
          now,
        ),
        isFalse,
      );
    });
  });

  group('giftTriggerLines', () {
    test('prefers triggers list, specific_item only', () {
      final lines = giftTriggerLines({
        'triggers': [
          {'type': 'min_order', 'value': 100},
          {'type': 'specific_item', 'offerId': 'o1'},
        ],
      });
      expect(lines.length, 1);
      expect(lines.first['offerId'], 'o1');
    });
    test('falls back to singular trigger', () {
      final lines = giftTriggerLines({
        'trigger': {'type': 'specific_item', 'offerId': 'o9'},
      });
      expect(lines.length, 1);
    });
    test('empty when no specific_item lines', () {
      expect(giftTriggerLines({'trigger': {'type': 'min_order'}}), isEmpty);
      expect(giftTriggerLines({}), isEmpty);
    });
  });
}
