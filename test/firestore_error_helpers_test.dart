import 'package:flutter_test/flutter_test.dart';
import 'package:aksab_sales/utils/firestore_error_helpers.dart';

// Regression: Firestore "missing index" errors must be detected and the
// console "create index" link extracted so the products screen can show it.
void main() {
  group('isMissingIndexError', () {
    test('detects failed-precondition index error', () {
      expect(
        isMissingIndexError(
            '[cloud_firestore/failed-precondition] The query requires an index. '
            'You can create it here: https://console.firebase.google.com/x'),
        isTrue,
      );
    });
    test('rejects unrelated errors and null', () {
      expect(isMissingIndexError('permission-denied'), isFalse);
      expect(isMissingIndexError(null), isFalse);
    });
  });

  group('geoHiddenMessage', () {
    test('asks to enable location when fix is missing', () {
      expect(
        geoHiddenMessage(totalOffers: 3, hasLocation: false),
        contains('فعّل الموقع'),
      );
    });
    test('says offers are out of range when located', () {
      expect(
        geoHiddenMessage(totalOffers: 2, hasLocation: true),
        contains('خارج نطاق موقعك'),
      );
    });
  });

  group('isPermissionDeniedError', () {
    test('detects permission-denied variants', () {
      expect(
        isPermissionDeniedError(
            '[cloud_firestore/permission-denied] Missing or insufficient permissions.'),
        isTrue,
      );
      expect(isPermissionDeniedError('permission-denied'), isTrue);
    });
    test('rejects index errors, unrelated text and null', () {
      expect(isPermissionDeniedError('requires an index'), isFalse);
      expect(isPermissionDeniedError('boom'), isFalse);
      expect(isPermissionDeniedError(null), isFalse);
    });
  });

  group('describeQueryErrorAr', () {
    test('points to the missing index for index errors', () {
      expect(
        describeQueryErrorAr(
            '[cloud_firestore/failed-precondition] requires an index'),
        contains('فهرس'),
      );
    });
    test('points to protection rules for permission errors', () {
      expect(
        describeQueryErrorAr('permission-denied'),
        contains('صلاحية'),
      );
    });
    test('falls back to the raw message otherwise', () {
      expect(describeQueryErrorAr('boom'), contains('boom'));
      expect(describeQueryErrorAr(null), contains('خطأ غير معروف'));
    });
  });

  group('extractFirestoreIndexUrl', () {
    test('extracts console link', () {
      const msg =
          'requires an index. You can create it here: https://console.firebase.google.com/v1/r/project/x/firestore/indexes?create_composite=abc';
      expect(extractFirestoreIndexUrl(msg), startsWith('https://console.firebase.google.com'));
    });
    test('returns null when no link', () {
      expect(extractFirestoreIndexUrl('permission-denied'), isNull);
      expect(extractFirestoreIndexUrl(null), isNull);
    });
  });
}
