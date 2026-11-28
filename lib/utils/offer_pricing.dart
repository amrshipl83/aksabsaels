// lib/utils/offer_pricing.dart
//
// Price-eligibility port of my_test_app utils/price_display.dart
// (payablePrice / hasUsablePrice / hasPricedOfferDoc).
// A rep must never see an offer the buyer could not pay for: an offer doc
// counts as priced only when at least one unit (or the document root)
// yields a positive chargeable amount. Missing ('?'/null), zero and
// negative prices stay hidden. Pure Dart, no Firestore.

/// Price the buyer actually pays: discount first, then base price.
double payablePrice({
  required dynamic basePrice,
  required dynamic offerPrice,
}) {
  if (offerPrice is num && (offerPrice as num) > 0) {
    return (offerPrice as num).toDouble();
  }
  if (basePrice is num) return (basePrice as num).toDouble();
  return 0.0;
}

/// True when the buyer would pay a positive amount for this unit.
bool hasUsablePrice({
  required dynamic basePrice,
  required dynamic offerPrice,
}) {
  return payablePrice(basePrice: basePrice, offerPrice: offerPrice) > 0;
}

/// True when a raw productOffers document carries at least one priced unit.
///
/// Units are checked first (unit offerPrice, then the document root
/// offerPrice, then the unit base price). Documents without a units list
/// fall back to the root price/offerPrice. Empty-units documents with no
/// root price are unpriced and must stay hidden from the rep store.
bool hasPricedOfferDoc(Map<String, dynamic> data) {
  final dynamic units = data['units'];
  if (units is List && units.isNotEmpty) {
    for (final unit in units) {
      if (unit is Map) {
        final dynamic base = unit['price'];
        final dynamic offer = unit['offerPrice'] ?? data['offerPrice'];
        if (hasUsablePrice(basePrice: base, offerPrice: offer)) return true;
      }
    }
    return false;
  }
  return hasUsablePrice(
    basePrice: data['price'],
    offerPrice: data['offerPrice'],
  );
}
