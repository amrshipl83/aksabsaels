import 'package:flutter_test/flutter_test.dart';
import 'package:aksab_sales/utils/geo_areas.dart';

// BUYER-parity decisions for the rep offers screen:
// deliveryZones first, deliveryAreas fallback; global always visible;
// no location hides zoned offers; unknown zones never match.
void main() {
  Map<String, List<List<AreaPoint>>> polygons() => {
        'Downtown': [
          [
            AreaPoint(lat: 30.0, lng: 31.0),
            AreaPoint(lat: 30.0, lng: 32.0),
            AreaPoint(lat: 31.0, lng: 32.0),
            AreaPoint(lat: 31.0, lng: 31.0),
            AreaPoint(lat: 30.0, lng: 31.0),
          ],
        ],
      };

  group('readOfferZones', () {
    test('prefers deliveryZones over deliveryAreas', () {
      expect(
        readOfferZones({
          'deliveryZones': ['A'],
          'deliveryAreas': ['B'],
        }),
        ['A'],
      );
    });
    test('falls back to deliveryAreas when zones are absent', () {
      expect(readOfferZones({'deliveryAreas': ['B']}), ['B']);
    });
    test('returns empty for zone-less offers (global)', () {
      expect(readOfferZones({}), isEmpty);
    });
    test('ignores non-string entries via whereType', () {
      expect(readOfferZones({'deliveryZones': ['A', 7]}), ['A']);
    });
  });

  group('isOfferVisibleByCoords', () {
    test('global offer is visible even without a location', () {
      expect(
        isOfferVisibleByCoords(
            offerData: {}, lat: null, lng: null, areaPolygons: polygons()),
        isTrue,
      );
    });
    test('zoned offer is hidden without a location', () {
      expect(
        isOfferVisibleByCoords(
          offerData: {'deliveryZones': ['Downtown']},
          lat: null,
          lng: null,
          areaPolygons: polygons(),
        ),
        isFalse,
      );
    });
    test('point inside the polygon matches', () {
      expect(
        isOfferVisibleByCoords(
          offerData: {'deliveryZones': ['Downtown']},
          lat: 30.5,
          lng: 31.5,
          areaPolygons: polygons(),
        ),
        isTrue,
      );
    });
    test('point outside every polygon does not match', () {
      expect(
        isOfferVisibleByCoords(
          offerData: {'deliveryZones': ['Downtown']},
          lat: 40.0,
          lng: 40.0,
          areaPolygons: polygons(),
        ),
        isFalse,
      );
    });
    test('deliveryAreas fallback is honored', () {
      expect(
        isOfferVisibleByCoords(
          offerData: {'deliveryAreas': ['Downtown']},
          lat: 30.5,
          lng: 31.5,
          areaPolygons: polygons(),
        ),
        isTrue,
      );
    });
    test('unknown area name never matches', () {
      expect(
        isOfferVisibleByCoords(
          offerData: {'deliveryZones': ['Nowhere']},
          lat: 30.5,
          lng: 31.5,
          areaPolygons: polygons(),
        ),
        isFalse,
      );
    });
    test('bbox prefilter keeps the same decision', () {
      final boxes = buildAreaBBoxes(polygons());
      expect(
        isOfferVisibleByCoords(
          offerData: {'deliveryZones': ['Downtown']},
          lat: 30.5,
          lng: 31.5,
          areaPolygons: polygons(),
          bboxes: boxes,
        ),
        isTrue,
      );
      expect(
        isOfferVisibleByCoords(
          offerData: {'deliveryZones': ['Downtown']},
          lat: 40.0,
          lng: 40.0,
          areaPolygons: polygons(),
          bboxes: boxes,
        ),
        isFalse,
      );
    });
  });

  group('buildAreaBBoxes', () {
    test('spans all rings of the area', () {
      final boxes = buildAreaBBoxes(polygons());
      final box = boxes['Downtown']!;
      expect(box.contains(30.5, 31.5), isTrue);
      expect(box.contains(40.0, 40.0), isFalse);
      expect(buildAreaBBoxes({}), isEmpty);
    });
  });

  group('isOfferActive', () {
    test('missing or empty status reads as active (legacy)', () {
      expect(isOfferActive({}), isTrue);
      expect(isOfferActive({'status': ''}), isTrue);
      expect(isOfferActive({'status': 'active'}), isTrue);
    });
    test('any other status hides the offer', () {
      expect(isOfferActive({'status': 'disabled'}), isFalse);
      expect(isOfferActive({'status': 'expired'}), isFalse);
    });
  });

  group('filterOfferDocsByCoords', () {
    test('keeps order and drops zoned-out offers', () {
      final docs = [
        {'sellerId': 's1', 'status': 'active'},
        {
          'sellerId': 's2',
          'status': 'active',
          'deliveryZones': ['Downtown']
        },
        {
          'sellerId': 's3',
          'status': 'active',
          'deliveryZones': ['Nowhere']
        },
      ];
      final out = filterOfferDocsByCoords(docs, 30.5, 31.5, polygons());
      expect(out.length, 2);
      expect(out.first['sellerId'], 's1');
    });
  });

  group('visibleOfferSellerIdsByCoords', () {
    test('collects sellers with a visible active offer (id only)', () {
      final ids = visibleOfferSellerIdsByCoords(
        offerDocs: [
          {'sellerId': 's1', 'status': 'active'},
          {
            'sellerId': 's2',
            'status': 'active',
            'deliveryZones': ['Downtown']
          },
          {
            'sellerId': 's3',
            'status': 'disabled',
            'deliveryZones': ['Downtown']
          },
          {'sellerId': '', 'status': 'active'},
        ],
        lat: 30.5,
        lng: 31.5,
        areaPolygons: polygons(),
      );
      expect(ids, {'s1', 's2'});
    });
    test('unknown location keeps globals only', () {
      final ids = visibleOfferSellerIdsByCoords(
        offerDocs: [
          {'sellerId': 's1', 'status': 'active'},
          {
            'sellerId': 's2',
            'status': 'active',
            'deliveryZones': ['Downtown']
          },
        ],
        lat: null,
        lng: null,
        areaPolygons: polygons(),
      );
      expect(ids, {'s1'});
    });
  });
}
