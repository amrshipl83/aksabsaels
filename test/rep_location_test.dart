import 'package:aksab_sales/utils/rep_location.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

// Ordering rule: newest visit by startTime wins (open or closed).
// endTime is never a ranking criterion; no fallback to older visits.
void main() {
  Timestamp ts(int minutes) => Timestamp.fromDate(
      DateTime(2026, 1, 1).add(Duration(minutes: minutes)));

  Map<String, dynamic> visitDoc(int startMinute,
      {double lat = 30.0, double lng = 31.0, Timestamp? end}) =>
      {
        'repCode': 'R1',
        'startTime': ts(startMinute),
        if (end != null) 'endTime': end,
        'location': {'lat': lat, 'lng': lng},
      };

  group('pickNewestVisitByStartTime', () {
    test('newest by startTime wins among 60 docs even when last', () {
      final docs = List.generate(60, (i) => visitDoc(i)).reversed.toList();
      final newest = pickNewestVisitByStartTime(docs)!;
      expect((newest['startTime'] as Timestamp).toDate(), ts(59).toDate());
    });

    test('docs without a valid startTime are skipped', () {
      final docs = [
        {'repCode': 'R1', 'location': {'lat': 30.0, 'lng': 31.0}},
        {'repCode': 'R1', 'startTime': 'not-a-timestamp'},
        visitDoc(5),
      ];
      final newest = pickNewestVisitByStartTime(docs)!;
      expect((newest['startTime'] as Timestamp).toDate(), ts(5).toDate());
    });

    test('endTime never outranks startTime', () {
      final docs = [
        visitDoc(10, end: ts(100)),
        visitDoc(20),
      ];
      final newest = pickNewestVisitByStartTime(docs)!;
      expect((newest['startTime'] as Timestamp).toDate(), ts(20).toDate());
    });

    test('empty input returns null', () {
      expect(pickNewestVisitByStartTime(const []), isNull);
    });
  });

  group('fetchUnifiedRepPoint (fake_cloud_firestore)', () {
    test('newest of 60 visits wins', () async {
      final fake = FakeFirebaseFirestore();
      for (var i = 0; i < 60; i++) {
        await fake.collection('visits').add({
          'repCode': 'R1',
          'startTime': ts(i),
          'location': {'lat': 30.0 + i / 1000.0, 'lng': 31.0},
        });
      }
      final point = await fetchUnifiedRepPoint(fake, 'R1');
      expect(point, isNotNull);
      expect(point!.lat, closeTo(30.059, 1e-9));
      expect(point.lng, 31.0);
    });

    test('falls back to day start when no visits exist', () async {
      final fake = FakeFirebaseFirestore();
      await fake.collection('daily_logs').add({
        'repCode': 'R1',
        'status': 'open',
        'startLocation': {'lat': 29.9, 'lng': 31.2},
        'startTime': ts(0),
      });
      final point = await fetchUnifiedRepPoint(fake, 'R1');
      expect(point, isNotNull);
      expect(point!.lat, 29.9);
      expect(point.lng, 31.2);
    });

    test('invalid newest visit falls back to day start, not older visit',
        () async {
      final fake = FakeFirebaseFirestore();
      await fake.collection('visits').add({
        'repCode': 'R1',
        'startTime': ts(10),
        'location': {'lat': 30.1, 'lng': 31.1},
      });
      await fake.collection('visits').add({
        'repCode': 'R1',
        'startTime': ts(20),
        // Invalid fix: must be ignored, must NOT fall back to the older visit.
        'location': {'lat': 0, 'lng': 0},
      });
      await fake.collection('daily_logs').add({
        'repCode': 'R1',
        'status': 'open',
        'startLocation': {'lat': 29.9, 'lng': 31.2},
        'startTime': ts(0),
      });
      final point = await fetchUnifiedRepPoint(fake, 'R1');
      expect(point, isNotNull);
      expect(point!.lat, 29.9);
      expect(point.lng, 31.2);
    });
  });
}
