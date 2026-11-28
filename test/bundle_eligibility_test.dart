import 'package:flutter_test/flutter_test.dart';
import 'package:aksab_sales/utils/bundle_eligibility.dart';

// sellableNow = remaining − held, never negative (BUYER port).
void main() {
  group('bundleSellableNow', () {
    test('explicit remaining minus held', () {
      expect(
        bundleSellableNow({'remainingCount': 5, 'heldCount': 2}),
        3,
      );
    });
    test('derives remaining for active bundles without explicit count', () {
      expect(
        bundleSellableNow({'status': 'active', 'bundleCount': 10, 'soldCount': 4}),
        6,
      );
      expect(
        bundleSellableNow(
            {'status': 'active', 'bundleCount': 10, 'consumedCount': 9}),
        1,
      );
    });
    test('inactive bundles without explicit count read as zero', () {
      expect(bundleSellableNow({'status': 'disabled', 'bundleCount': 10}), 0);
    });
    test('never negative', () {
      expect(
        bundleSellableNow({'remainingCount': 1, 'heldCount': 9}),
        0,
      );
    });
    test('missing heldCount defaults to zero', () {
      expect(bundleSellableNow({'remainingCount': 4}), 4);
    });
  });
}
