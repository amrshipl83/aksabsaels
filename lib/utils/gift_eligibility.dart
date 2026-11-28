// lib/utils/gift_eligibility.dart
//
// Pure-Dart port of the eligibility rules in my_test_app
// services/gift_eligibility_service.dart (parse/isLive/remaining/
// triggerLines). No Firestore here: screens fetch the documents and
// these functions decide. Fail-closed everywhere, mirroring BUYER.

/// Accepts Timestamp (as dynamic — Firestore Timestamp, DateTime, or
/// ISO-8601 String). Anything else → null (unparseable ⇒ not live).
DateTime? parseGiftExpiry(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is String && value.trim().isNotEmpty) {
    return DateTime.tryParse(value.trim());
  }
  // Firestore Timestamp exposes toDate(); matched structurally to keep
  // this file free of the cloud_firestore import.
  try {
    final dynamic d = (value as dynamic).toDate();
    if (d is DateTime) return d;
  } catch (_) {}
  return null;
}

/// Remaining budget: maxQuantity - usedQuantity. Missing/non-positive
/// maxQuantity ⇒ 0 (not eligible — no reserved stock).
int giftPromoRemaining(Map<String, dynamic> promo) {
  final maxQ = (promo['maxQuantity'] as num?)?.toInt() ?? 0;
  final usedQ = (promo['usedQuantity'] as num?)?.toInt() ?? 0;
  if (maxQ <= 0) return 0;
  final remaining = maxQ - usedQ;
  return remaining < 0 ? 0 : remaining;
}

/// Is the promo live: status active + not expired + budget remaining.
/// An unparseable expiry closes the gate (fail-closed), mirroring BUYER.
bool isGiftPromoLive(Map<String, dynamic> promo, DateTime now) {
  if ((promo['status']?.toString() ?? '') != 'active') return false;
  if (!promo.containsKey('expiryDate') || promo['expiryDate'] == null) {
    return giftPromoRemaining(promo) > 0;
  }
  final exp = parseGiftExpiry(promo['expiryDate']);
  if (exp == null) return false;
  if (!exp.isAfter(now)) return false;
  return giftPromoRemaining(promo) > 0;
}

/// Purchase lines: `triggers` first (AND), then singular `trigger` for
/// backward compatibility. Only `specific_item` lines count.
List<Map<String, dynamic>> giftTriggerLines(Map<String, dynamic> promo) {
  final raw = promo['triggers'];
  if (raw is List && raw.isNotEmpty) {
    final lines = raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((e) => e['type'] == 'specific_item')
        .toList();
    if (lines.isNotEmpty) return lines;
  }
  final single = promo['trigger'];
  if (single is Map<String, dynamic> && single['type'] == 'specific_item') {
    return [single];
  }
  if (single is Map) {
    final m = Map<String, dynamic>.from(single);
    if (m['type'] == 'specific_item') return [m];
  }
  return const [];
}
