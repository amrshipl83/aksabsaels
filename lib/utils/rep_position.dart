// lib/utils/rep_position.dart
// Resolves the rep's latest confirmed position for the offers screen.
//
// Sources (both already recorded by the app, no new writes):
// - open workday: `daily_logs/{id}.startLocation{lat,lng}` + `startTime`.
// - newest visit by `startTime` (open or closed): `visits/{id}.location`
//   used as-is; close time is never a ranking criterion.
//
// Rule: the newest visit (by `startTime`, open or closed) wins when its
// coordinates are VALID; otherwise fall back to the workday start —
// never to an older visit. Validity: non-null, finite, in range, and
// not the (0, 0) placeholder. A closed visit's stored location is used
// as-is (the app's last recorded visit position). No order history,
// no buyer location, no sellers.location.

/// A confirmed presence point with its server timestamp.
class RepPoint {
  final double lat;
  final double lng;
  final DateTime time;

  const RepPoint({required this.lat, required this.lng, required this.time});
}

/// Validity gate for a coordinate pair. Pure, unit-testable.
bool isValidLatLng(double? lat, double? lng) {
  if (lat == null || lng == null) return false;
  if (!lat.isFinite || !lng.isFinite) return false;
  if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return false;
  // (0, 0) is the Gulf of Guinea placeholder, never a real Egyptian fix.
  if (lat == 0 && lng == 0) return false;
  return true;
}

/// Picks the rep position: the newest visit (by `startTime`, already
/// ordered by the caller) when its coordinates are valid, otherwise the
/// open workday start. Never falls back to an older visit. Returns null
/// when neither source yields valid coordinates — callers then show
/// global-only offers (never guesses).
RepPoint? resolveRepPosition({RepPoint? dayStart, RepPoint? newestVisit}) {
  if (newestVisit != null &&
      isValidLatLng(newestVisit.lat, newestVisit.lng)) {
    return newestVisit;
  }
  if (dayStart != null && isValidLatLng(dayStart.lat, dayStart.lng)) {
    return dayStart;
  }
  return null;
}
