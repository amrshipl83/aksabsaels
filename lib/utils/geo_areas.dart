// lib/utils/geo_areas.dart
// Shared decode → boundary → point-test → match chain for delivery-area
// filtering. Pure Dart (no plugins), never throws on malformed input:
// invalid features are skipped, not fatal.

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
