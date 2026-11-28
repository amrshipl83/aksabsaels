// lib/utils/geo_areas.dart
// Shared decode → boundary → point-test → match chain for delivery-area
// filtering. Pure Dart (no plugins), never throws on malformed input:
// invalid features are skipped, not fatal.
//
// BUYER-parity ports live here: GeoBBox pre-filtering, zone reading
// (deliveryZones first), offer visibility, and seller-id collection —
// same decisions as my_test_app offer_geo_filter.dart + seller_geo.dart,
// with the rep's coordinates passed in place of the buyer's.
import 'package:flutter/foundation.dart';

/// A geographic point (lat/lng in decimal degrees).
class AreaPoint {
  final double lat;
  final double lng;
  const AreaPoint({required this.lat, required this.lng});
}

/// Normalizes an area name for matching (trims surrounding/extra spaces).
String normalizeAreaName(String raw) =>
    raw.trim().replaceAll(RegExp(r'\s+'), ' ');

double? _asDouble(dynamic v) => (v is num) ? v.toDouble() : null;

/// Parses one linear ring ([lng, lat] pairs) or returns null when unusable.
List<AreaPoint>? _parseRing(dynamic ring) {
  if (ring is! List) return null;
  final pts = <AreaPoint>[];
  for (final p in ring) {
    if (p is! List || p.length < 2) continue;
    final lng = _asDouble(p[0]);
    final lat = _asDouble(p[1]);
    if (lng == null || lat == null) continue;
    pts.add(AreaPoint(lat: lat, lng: lng));
  }
  if (pts.length < 3) return null;
  return pts;
}

/// Decodes a GeoJSON FeatureCollection into area-name → list of rings.
/// Handles Polygon and MultiPolygon; skips nameless/invalid features.
Map<String, List<List<AreaPoint>>> parseAreaPolygons(dynamic geoJson) {
  final out = <String, List<List<AreaPoint>>>{};
  try {
    final features = (geoJson is Map) ? geoJson['features'] : null;
    if (features is! List) return out;
    for (final f in features) {
      if (f is! Map) continue;
      final props = f['properties'];
      final key = normalizeAreaName(
        (props is Map ? props['name']?.toString() : null) ?? '',
      );
      if (key.isEmpty) continue;
      final geom = f['geometry'];
      if (geom is! Map) continue;
      final type = geom['type']?.toString();
      final coords = geom['coordinates'];
      if (coords is! List) continue;
      final rings = <List<AreaPoint>>[];
      if (type == 'MultiPolygon') {
        for (final poly in coords) {
          if (poly is! List) continue;
          for (final ring in poly) {
            final r = _parseRing(ring);
            if (r != null) rings.add(r);
          }
        }
      } else if (type == 'Polygon') {
        for (final ring in coords) {
          final r = _parseRing(ring);
          if (r != null) rings.add(r);
        }
      } else {
        continue;
      }
      if (rings.isEmpty) continue;
      out.putIfAbsent(key, () => []).addAll(rings);
    }
  } catch (_) {
    // Malformed input degrades to "no coverage", never a crash.
  }
  return out;
}

/// Ray-casting point-in-ring test. Degenerate rings (<3 points) → false.
bool isPointInRing(double lat, double lng, List<AreaPoint> ring) {
  if (ring.length < 3) return false;
  bool inside = false;
  int j = ring.length - 1;
  for (int i = 0; i < ring.length; j = i++) {
    final xi = ring[i].lng;
    final yi = ring[i].lat;
    final xj = ring[j].lng;
    final yj = ring[j].lat;
    if (((yi > lat) != (yj > lat)) &&
        (lng < (xj - xi) * (lat - yi) / (yj - yi) + xi)) {
      inside = !inside;
    }
  }
  return inside;
}

/// True when the point falls inside ANY ring of the area.
bool areaCoversPoint(
    List<List<AreaPoint>>? polygons, double lat, double lng) {
  if (polygons == null || polygons.isEmpty) return false;
  return polygons.any((ring) => isPointInRing(lat, lng, ring));
}

/// Bounding box for one area: fast pre-filter before ray casting.
/// Never changes the decision, only skips ray-casting when the box
/// cannot contain the point. Port of my_test_app GeoBBox.
class GeoBBox {
  final double minLat;
  final double maxLat;
  final double minLng;
  final double maxLng;
  const GeoBBox(
      {required this.minLat,
      required this.maxLat,
      required this.minLng,
      required this.maxLng});

  bool contains(double lat, double lng) {
    return lat >= minLat && lat <= maxLat && lng >= minLng && lng <= maxLng;
  }
}

/// Builds one bounding box per area from a ready polygons map (all rings).
/// Port of my_test_app buildAreaBBoxes (adapted to multi-ring areas).
Map<String, GeoBBox> buildAreaBBoxes(
    Map<String, List<List<AreaPoint>>> areaPolygons) {
  final Map<String, GeoBBox> result = {};
  areaPolygons.forEach((areaName, rings) {
    var seeded = false;
    var minLat = 0.0;
    var maxLat = 0.0;
    var minLng = 0.0;
    var maxLng = 0.0;
    for (final ring in rings) {
      for (final p in ring) {
        if (!seeded) {
          minLat = maxLat = p.lat;
          minLng = maxLng = p.lng;
          seeded = true;
        } else {
          if (p.lat < minLat) minLat = p.lat;
          if (p.lat > maxLat) maxLat = p.lat;
          if (p.lng < minLng) minLng = p.lng;
          if (p.lng > maxLng) maxLng = p.lng;
        }
      }
    }
    if (seeded) {
      result[areaName] =
          GeoBBox(minLat: minLat, maxLat: maxLat, minLng: minLng, maxLng: maxLng);
    }
  });
  return result;
}

/// Full match rule shared by the store screens:
/// - no areas listed → visible everywhere (true);
/// - no location → [showWhenLocationUnknown];
/// - unknown area name → false.
bool offerCoversLocation({
  required dynamic deliveryAreas,
  required double? lat,
  required double? lng,
  required Map<String, List<List<AreaPoint>>> areaPolygons,
  bool showWhenLocationUnknown = false,
}) {
  final areas = (deliveryAreas is List) ? deliveryAreas : const [];
  if (areas.isEmpty) return true;
  if (lat == null || lng == null) return showWhenLocationUnknown;
  return areas.any((a) {
    final key = normalizeAreaName(a?.toString() ?? '');
    if (key.isEmpty) return false;
    return areaCoversPoint(areaPolygons[key], lat, lng);
  });
}

/// Reads an offer/bundle document's coverage zones with a safe fallback:
/// `deliveryZones` first, then `deliveryAreas`. No migration, read-only.
/// Mirrors my_test_app `readOfferZones` (BUYER reference path).
List<String> readOfferZones(Map<String, dynamic> offerData) {
  final dynamic zones = offerData['deliveryZones'];
  if (zones is List && zones.isNotEmpty) {
    return zones.whereType<String>().toList();
  }
  final dynamic areas = offerData['deliveryAreas'];
  if (areas is List && areas.isNotEmpty) {
    return areas.whereType<String>().toList();
  }
  return const [];
}

/// Single-offer visibility for the rep screens (BUYER productOffers
/// context, rep coordinates instead of buyer coordinates):
/// - no zones listed → global, visible to everyone (true);
/// - no rep location → hidden (false), global offers handled by the same
///   zones-empty rule above, so callers show globals only;
/// - unknown area name → skipped with a diagnostic (false), never a match.
/// Mirrors my_test_app `SellerGeo.isOfferVisibleByCoords` decision table,
/// including the GeoBBox pre-filter (same decision, less ray casting).
bool isOfferVisibleByCoords({
  required Map<String, dynamic> offerData,
  required double? lat,
  required double? lng,
  required Map<String, List<List<AreaPoint>>> areaPolygons,
  Map<String, GeoBBox>? bboxes,
}) {
  final zones = readOfferZones(offerData)
      .map(normalizeAreaName)
      .where((e) => e.isNotEmpty)
      .toList();
  if (zones.isEmpty) return true;
  if (lat == null || lng == null) return false;
  for (final key in zones) {
    final poly = areaPolygons[key];
    if (poly == null || poly.isEmpty) {
      debugPrint('GeoAreas: no polygon for "$key" — skipped.');
      continue;
    }
    final box = bboxes?[key];
    if (box != null && !box.contains(lat, lng)) continue;
    if (areaCoversPoint(poly, lat, lng)) return true;
  }
  return false;
}

/// Whether an offer counts as active: missing/empty status reads as active
/// (backward compatibility with legacy offers); any other value hides it.
/// Port of my_test_app `isOfferActive`.
bool isOfferActive(Map<String, dynamic> offerData) {
  final dynamic raw = offerData['status'];
  if (raw == null) return true;
  final String s = raw.toString().trim().toLowerCase();
  return s.isEmpty || s == 'active';
}

/// Filters raw offer documents, preserving the original order.
/// Port of my_test_app `filterOfferDocsByCoords` (rep coords in place of
/// buyer coords; productOffers context).
List<Map<String, dynamic>> filterOfferDocsByCoords(
  List<Map<String, dynamic>> docs,
  double? lat,
  double? lng,
  Map<String, List<List<AreaPoint>>> areaPolygons, {
  Map<String, GeoBBox>? bboxes,
}) {
  return docs
      .where((doc) => isOfferVisibleByCoords(
            offerData: doc,
            lat: lat,
            lng: lng,
            areaPolygons: areaPolygons,
            bboxes: bboxes,
          ))
      .toList();
}

/// Ids of sellers with at least one active, visible offer (productOffers
/// context). Port of my_test_app `visibleOfferSellerIdsByCoords`.
/// Never uses sellerName: identity is `sellerId` only.
Set<String> visibleOfferSellerIdsByCoords({
  required Iterable<Map<String, dynamic>> offerDocs,
  required double? lat,
  required double? lng,
  required Map<String, List<List<AreaPoint>>> areaPolygons,
  Map<String, GeoBBox>? bboxes,
}) {
  final ids = <String>{};
  for (final data in offerDocs) {
    final sellerId = data['sellerId']?.toString();
    if (sellerId == null || sellerId.isEmpty || ids.contains(sellerId)) {
      continue;
    }
    if (!isOfferActive(data)) continue;
    if (isOfferVisibleByCoords(
      offerData: data,
      lat: lat,
      lng: lng,
      areaPolygons: areaPolygons,
      bboxes: bboxes,
    )) {
      ids.add(sellerId);
    }
  }
  return ids;
}
