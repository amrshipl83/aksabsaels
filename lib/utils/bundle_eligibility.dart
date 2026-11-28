// lib/utils/bundle_eligibility.dart
//
// Pure-Dart port of the sellable gate in my_test_app
// models/bundle_model.dart (sellableNow) with its fromFirestore defaults.
// Units a rep can show right now (holds excluded, never negative).

/// Remaining units for a sellerBundles document, mirroring BUYER's
/// fromFirestore defaults: explicit remainingCount wins; otherwise
/// derived for active bundles as bundleCount − sold (or consumed);
/// inactive bundles without an explicit count read as 0.
int _bundleRemaining(Map<String, dynamic> data) {
  final explicit = (data['remainingCount'] as num?)?.toInt();
  if (explicit != null) return explicit;
  if ((data['status'] as String?) == 'active') {
    final total = (data['bundleCount'] as num?)?.toInt() ?? 1;
    final sold = (data['soldCount'] as num?)?.toInt() ??
        ((data['consumedCount'] as num?)?.toInt() ?? 0);
    return total - sold;
  }
  return 0;
}

/// Sellable units right now (holds excluded, never negative).
/// Bundles with sellableNow <= 0 are hidden, as in BUYER's
/// loadActiveBundlesForBuyer. Verified source: the same shared
/// sellerBundles documents/fields BUYER reads — no new logic invented.
int bundleSellableNow(Map<String, dynamic> data) {
  final held = (data['heldCount'] as num?)?.toInt() ?? 0;
  final v = _bundleRemaining(data) - held;
  return v < 0 ? 0 : v;
}
