import 'package:aksab_sales/utils/offer_pricing.dart';
import 'package:flutter_test/flutter_test.dart';

// BUYER-parity port of buyer_unpriced_offer_hidden_test.dart (doc-level
// groups): only offers with a positive chargeable amount stay visible.
void main() {
  group('hasUsablePrice', () {
    test('accepts a positive base price without discount', () {
      expect(hasUsablePrice(basePrice: 100, offerPrice: null), isTrue);
      expect(hasUsablePrice(basePrice: 100.0, offerPrice: 0), isTrue);
    });

    test('accepts a root discount even when the base is zero', () {
      expect(hasUsablePrice(basePrice: 0, offerPrice: 80), isTrue);
    });

    test('rejects zero, null, negative and non-numeric prices', () {
      expect(hasUsablePrice(basePrice: 0, offerPrice: null), isFalse);
      expect(hasUsablePrice(basePrice: 0, offerPrice: 0), isFalse);
      expect(hasUsablePrice(basePrice: null, offerPrice: null), isFalse);
      expect(hasUsablePrice(basePrice: '?', offerPrice: null), isFalse);
      expect(hasUsablePrice(basePrice: '80', offerPrice: null), isFalse);
      expect(hasUsablePrice(basePrice: -5, offerPrice: null), isFalse);
      expect(hasUsablePrice(basePrice: 100, offerPrice: -10), isTrue);
    });
  });

  group('hasPricedOfferDoc', () {
    test('units: one priced unit keeps the document visible', () {
      expect(
        hasPricedOfferDoc({
          'units': [
            {'unitName': 'قطعة', 'price': 0},
            {'unitName': 'كرتونة', 'price': 120},
          ],
        }),
        isTrue,
      );
    });

    test('units: all-zero units hide the document', () {
      expect(
        hasPricedOfferDoc({
          'units': [
            {'unitName': 'قطعة', 'price': 0},
          ],
        }),
        isFalse,
      );
    });

    test('units: missing and "?" prices hide the document', () {
      expect(
        hasPricedOfferDoc({
          'units': [
            {'unitName': 'قطعة'},
            {'unitName': 'كرتونة', 'price': '?'},
          ],
        }),
        isFalse,
      );
    });

    test('units: a zero base with a root discount still counts as priced',
        () {
      expect(
        hasPricedOfferDoc({
          'offerPrice': 80,
          'units': [
            {'unitName': 'قطعة', 'price': 0},
          ],
        }),
        isTrue,
      );
    });

    test('root: priced root without units stays visible', () {
      expect(
        hasPricedOfferDoc({'price': 50, 'status': 'active'}),
        isTrue,
      );
    });

    test('root: empty units with no root price stay hidden', () {
      expect(hasPricedOfferDoc({'units': []}), isFalse);
      expect(hasPricedOfferDoc({'price': 0}), isFalse);
      expect(hasPricedOfferDoc({}), isFalse);
    });
  });
}
