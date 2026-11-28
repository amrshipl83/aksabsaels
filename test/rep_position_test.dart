import 'package:flutter_test/flutter_test.dart';
import 'package:aksab_sales/utils/rep_position.dart';

// Newest-visit-first (ordered by startTime by the caller), else day start.
// Never falls back to an older visit.
void main() {
  RepPoint pt(double lat, double lng, int ms) => RepPoint(
      lat: lat, lng: lng, time: DateTime.fromMillisecondsSinceEpoch(ms));

  group('isValidLatLng', () {
    test('accepts a normal Egyptian fix', () {
      expect(isValidLatLng(30.0444, 31.2357), isTrue);
    });
    test('rejects null, out-of-range, and infinite values', () {
      expect(isValidLatLng(null, 31.0), isFalse);
      expect(isValidLatLng(30.0, null), isFalse);
      expect(isValidLatLng(91.0, 31.0), isFalse);
      expect(isValidLatLng(30.0, 181.0), isFalse);
      expect(isValidLatLng(double.infinity, 31.0), isFalse);
    });
    test('rejects the (0, 0) placeholder', () {
      expect(isValidLatLng(0, 0), isFalse);
    });
  });

  group('resolveRepPosition', () {
    test('returns null when both sources are missing', () {
      expect(resolveRepPosition(), isNull);
    });
    test('day start alone is used', () {
      final r = resolveRepPosition(dayStart: pt(30.0, 31.0, 1000));
      expect(r?.lat, 30.0);
    });
    test('newest visit alone is used', () {
      final r = resolveRepPosition(newestVisit: pt(30.5, 31.5, 2000));
      expect(r?.lng, 31.5);
    });
    test('newest visit wins even when older than the day start', () {
      // Ordering by startTime happens upstream; here the visit is newest.
      final r = resolveRepPosition(
        dayStart: pt(30.0, 31.0, 3000),
        newestVisit: pt(30.5, 31.5, 2000),
      );
      expect(r?.lat, 30.5);
    });
    test('invalid newest visit falls back to the day start', () {
      final r = resolveRepPosition(
        dayStart: pt(30.0, 31.0, 1000),
        newestVisit: pt(0, 0, 2000),
      );
      expect(r?.lat, 30.0);
    });
    test('returns null when both sources are invalid', () {
      expect(
        resolveRepPosition(dayStart: pt(0, 0, 1000), newestVisit: pt(95.0, 31.0, 2000)),
        isNull,
      );
    });
  });
}
