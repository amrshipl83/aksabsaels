import 'package:flutter_test/flutter_test.dart';
import 'package:aksab_sales/utils/geo_areas.dart';

// Regression tests for the delivery-area chain:
// decode (Polygon/MultiPolygon) → boundary → point test → offer match.
void main() {
  Map<String, dynamic> feature(
      String? name, String? type, dynamic coordinates) {
    return {
      'properties': {'name': name},
      'geometry': {'type': type, 'coordinates': coordinates},
    };
  }

  const square = [
    [31.0, 30.0],
    [32.0, 30.0],
    [32.0, 31.0],
    [31.0, 31.0],
    [31.0, 30.0],
  ];
  const square2 = [
    [40.0, 40.0],
    [41.0, 40.0],
    [41.0, 41.0],
    [40.0, 41.0],
    [40.0, 40.0],
  ];

  group('parseAreaPolygons', () {
    test('decodes a Polygon ring (lng/lat order)', () {
      final areas = parseAreaPolygons({
        'features': [feature('X', 'Polygon', [square])]
      });
      expect(areas.keys, ['X']);
      expect(areas['X']!.length, 1);
      expect(areas['X']!.first.length, 5);
      expect(areas['X']!.first.first.lat, 30.0);
      expect(areas['X']!.first.first.lng, 31.0);
    });
    test('decodes MultiPolygon into several rings', () {
      final areas = parseAreaPolygons({
        'features': [
          feature('M', 'MultiPolygon', [
            [square],
            [square2]
          ])
        ]
      });
      expect(areas['M']!.length, 2);
    });
    test('skips invalid features without throwing', () {
      final areas = parseAreaPolygons({
        'features': [
          feature(null, 'Polygon', [square]),
          feature('', 'Polygon', [square]),
          feature('NoGeom', 'Polygon', null),
          feature('Point', 'Point', [31.0, 30.0]),
          feature('Short', 'Polygon', [
            [
              [31.0, 30.0],
              [32.0, 30.0]
            ]
          ]),
          feature('BadNums', 'Polygon', [
            [
              ['a', 'b'],
              [32.0, 30.0],
              [32.0, 31.0]
            ]
          ]),
          'not-a-map',
        ]
      });
      expect(areas, isEmpty);
    });
    test('accepts int coordinates and never throws on garbage', () {
      final areas = parseAreaPolygons({
        'features': [
          feature('I', 'Polygon', [
            [
              [31, 30],
              [32, 30],
              [32, 31],
              [31, 31],
              [31, 30]
            ]
          ])
        ]
      });
      expect(areas['I']!.first.first.lat, 30.0);
      expect(parseAreaPolygons(null), isEmpty);
      expect(parseAreaPolygons('garbage'), isEmpty);
      expect(parseAreaPolygons({'features': 'nope'}), isEmpty);
    });
  });

  group('isPointInRing / areaCoversPoint', () {
    final ring = parseAreaPolygons({
      'features': [feature('X', 'Polygon', [square])]
    })['X']!.first;
    test('inside vs outside', () {
      expect(isPointInRing(30.5, 31.5, ring), isTrue);
      expect(isPointInRing(35.0, 35.0, ring), isFalse);
    });
    test('degenerate or missing polygons never match', () {
      expect(isPointInRing(30.5, 31.5, []), isFalse);
      expect(isPointInRing(30.5, 31.5, ring.sublist(0, 2)), isFalse);
      expect(areaCoversPoint(null, 30.5, 31.5), isFalse);
      expect(areaCoversPoint([], 30.5, 31.5), isFalse);
    });
  });

  group('offerCoversLocation', () {
    final polygons = parseAreaPolygons({
      'features': [feature('X', 'Polygon', [square])]
    });
    test('empty areas visible everywhere', () {
      expect(
        offerCoversLocation(
            deliveryAreas: null, lat: 0, lng: 0, areaPolygons: polygons),
        isTrue,
      );
      expect(
        offerCoversLocation(
            deliveryAreas: [], lat: null, lng: null, areaPolygons: polygons),
        isTrue,
      );
    });
    test('inside matches despite surrounding spaces', () {
      expect(
        offerCoversLocation(
            deliveryAreas: ['  X '],
            lat: 30.5,
            lng: 31.5,
            areaPolygons: polygons),
        isTrue,
      );
    });
    test('outside or unknown area does not match', () {
      expect(
        offerCoversLocation(
            deliveryAreas: ['X'],
            lat: 35.0,
            lng: 35.0,
            areaPolygons: polygons),
        isFalse,
      );
      expect(
        offerCoversLocation(
            deliveryAreas: ['Nope'],
            lat: 30.5,
            lng: 31.5,
            areaPolygons: polygons),
        isFalse,
      );
    });
    test('missing location follows the flag', () {
      expect(
        offerCoversLocation(
            deliveryAreas: ['X'],
            lat: null,
            lng: null,
            areaPolygons: polygons),
        isFalse,
      );
      expect(
        offerCoversLocation(
            deliveryAreas: ['X'],
            lat: null,
            lng: null,
            areaPolygons: polygons,
            showWhenLocationUnknown: true),
        isTrue,
      );
    });
  });
}
