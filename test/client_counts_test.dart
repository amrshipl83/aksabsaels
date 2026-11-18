import 'package:aksab_sales/utils/client_counts.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

// Single Source of Truth tests for the unified qualified-clients counter:
// `salesRep.clientCounts.{Cairo YYYY-MM}.total`, one value per repCode,
// teams summed across DISTINCT repCodes, Cairo wall-clock month/day keys,
// live snapshots() streams, chunked whereIn (no 10-team truncation).
void main() {
  const month = '2026-11';
  const day = '2026-11-17';

  Map<String, dynamic> repDoc(String code, int total, {int? dayTotal}) => {
        'repCode': code,
        'repType': 'permanent',
        'clientCounts': {
          month: {
            'total': total,
            if (dayTotal != null)
              'days': {day: dayTotal},
          },
        },
      };

  group('Cairo wall-clock keys', () {
    test('standard time is UTC+2 (January)', () {
      expect(
        clientCountMonthKey(nowUtc: DateTime.utc(2026, 1, 15, 12)),
        '2026-01',
      );
      expect(
        clientCountDayKey(nowUtc: DateTime.utc(2026, 1, 15, 12)),
        '2026-01-15',
      );
    });

    test('DST is UTC+3 (July)', () {
      // 00:30Z -> 03:30 Cairo, same day.
      expect(
        clientCountDayKey(nowUtc: DateTime.utc(2026, 7, 1, 0, 30)),
        '2026-07-01',
      );
      expect(
        clientCountMonthKey(nowUtc: DateTime.utc(2026, 7, 1, 0, 30)),
        '2026-07',
      );
    });

    test('device timezone never leaks into the key', () {
      // 2026-10-31 22:30Z is still October in UTC but 00:30 +2 in Cairo
      // on Nov 1 (DST ended Oct 29 2026): Cairo month must be November.
      expect(
        clientCountMonthKey(nowUtc: DateTime.utc(2026, 10, 31, 22, 30)),
        '2026-11',
      );
      expect(
        clientCountDayKey(nowUtc: DateTime.utc(2026, 10, 31, 22, 30)),
        '2026-11-01',
      );
    });

    test('DST start boundary (last Friday of April)', () {
      // Start = Apr 23 2026 22:00Z. One minute before -> +2, at -> +3.
      expect(
        clientCountDayKey(nowUtc: DateTime.utc(2026, 4, 23, 21, 59)),
        '2026-04-23', // 23:59 Cairo (+2)
      );
      expect(
        clientCountDayKey(nowUtc: DateTime.utc(2026, 4, 23, 22, 0)),
        '2026-04-24', // 01:00 Cairo (+3)
      );
    });

    test('DST end boundary (last Thursday of October)', () {
      // End = Oct 29 2026 21:00Z. Before -> +3, at -> +2.
      expect(
        clientCountDayKey(nowUtc: DateTime.utc(2026, 10, 29, 20, 59)),
        '2026-10-29', // 23:59 Cairo (+3)
      );
      expect(
        clientCountDayKey(nowUtc: DateTime.utc(2026, 10, 29, 21, 0)),
        '2026-10-29', // 23:00 Cairo (+2)
      );
    });

    test('month transition picks the new month key', () {
      expect(
        clientCountMonthKey(nowUtc: DateTime.utc(2026, 11, 30, 21, 59)),
        '2026-11', // 23:59 Cairo (+2)
      );
      expect(
        clientCountMonthKey(nowUtc: DateTime.utc(2026, 11, 30, 22, 0)),
        '2026-12', // 00:00 Cairo (+2) Dec 1
      );
    });
  });

  group('pure counter reads', () {
    test('repMonthTotal reads total, 0 when absent or bad', () {
      expect(repMonthTotal(repDoc('R1', 18), month), 18);
      expect(repMonthTotal(const {}, month), 0);
      expect(repMonthTotal(null, month), 0);
      expect(
        repMonthTotal({
          'clientCounts': {
            month: {'total': 'bad'}
          }
        }, month),
        0,
      );
      expect(
        repMonthTotal({
          'clientCounts': {
            '2026-10': {'total': 9}
          }
        }, month),
        0,
      );
    });

    test('repDayTotal reads the Cairo day entry', () {
      expect(repDayTotal(repDoc('R1', 18, dayTotal: 4), month, day), 4);
      expect(repDayTotal(repDoc('R1', 18), month, day), 0);
      expect(repDayTotal(const {}, month, day), 0);
    });

    test('dedupeRepDocsByCode keeps first doc per repCode', () {
      final byCode = dedupeRepDocsByCode([
        repDoc('R1', 5),
        repDoc('R1', 5),
        repDoc(' R2 ', 7),
        {'noCode': true},
        {'repCode': '   '},
      ]);
      expect(byCode.keys.toSet(), {'R1', 'R2'});
      expect(sumTeamMonthTotal(repDataByCode: byCode, monthKey: month), 12);
    });

    test('distinctRepCodes trims, drops empties, keeps order', () {
      expect(
        distinctRepCodes(['R1', ' R1 ', '', '  ', null, 'R2', 'R1']),
        ['R1', 'R2'],
      );
    });
  });

  group('live counter streams (fake_cloud_firestore)', () {
    test('1. rep with a single doc reads its total', () async {
      final fake = FakeFirebaseFirestore();
      await fake.collection('salesRep').doc('r1').set(repDoc('R1', 18));
      await expectLater(
        watchRepMonthTotal(db: fake, repCode: 'R1', monthKey: month),
        emits(18),
      );
    });

    test('2/5. rep with two docs sharing repCode is NOT doubled', () async {
      final fake = FakeFirebaseFirestore();
      await fake.collection('salesRep').doc('r1a').set(repDoc('R1', 5));
      await fake.collection('salesRep').doc('r1b').set(repDoc('R1', 5));
      await expectLater(
        watchTeamMonthTotal(db: fake, repCodes: const ['R1'], monthKey: month),
        emits(5),
      );
      await expectLater(
        watchRepMonthTotal(db: fake, repCode: 'R1', monthKey: month),
        emits(5),
      );
    });

    test('3. supervisor sums distinct reps of the team', () async {
      final fake = FakeFirebaseFirestore();
      await fake.collection('salesRep').doc('r1').set({
        ...repDoc('R1', 3),
        'supervisorId': 's1',
      });
      await fake.collection('salesRep').doc('r2').set({
        ...repDoc('R2', 4),
        'supervisorId': 's1',
      });
      await fake.collection('salesRep').doc('f1').set({
        'repCode': 'RF',
        'repType': 'freelance',
        'supervisorId': 's1',
        'clientCounts': {
          month: {'total': 100}
        },
      });
      await expectLater(
        watchSupervisorMonthTotal(
            db: fake, supervisorDocId: 's1', monthKey: month),
        emits(7),
      );
    });

    test('4. manager sums teams across supervisors', () async {
      final fake = FakeFirebaseFirestore();
      for (final s in ['s1', 's2']) {
        await fake.collection('managers').doc(s).set({
          'role': 'sales_supervisor',
          'managerId': 'm1',
        });
      }
      await fake.collection('managers').doc('s9').set({
        'role': 'sales_supervisor',
        'managerId': 'other',
      });
      await fake.collection('salesRep').doc('r1').set({
        ...repDoc('R1', 3),
        'supervisorId': 's1',
      });
      await fake.collection('salesRep').doc('r2').set({
        ...repDoc('R2', 4),
        'supervisorId': 's2',
      });
      await fake.collection('salesRep').doc('r3').set({
        ...repDoc('R3', 5),
        'supervisorId': 's2',
      });
      await fake.collection('salesRep').doc('r3dup').set({
        ...repDoc('R3', 5),
        'supervisorId': 's2',
      });
      await fake.collection('salesRep').doc('rx').set({
        ...repDoc('RX', 50),
        'supervisorId': 's9',
      });
      await expectLater(
        watchManagerMonthTotal(db: fake, managerDocId: 'm1', monthKey: month),
        emits(12),
      );
    });

    test('6. team larger than 10 reps is fully summed (chunked)', () async {
      final fake = FakeFirebaseFirestore();
      var expected = 0;
      for (var i = 0; i < 12; i++) {
        final code = 'R$i';
        expected += i + 1;
        await fake.collection('salesRep').doc('d$i').set({
          ...repDoc(code, i + 1),
          'supervisorId': 's1',
        });
      }
      // Chunked streams emit per-chunk as snapshots arrive (55 then 78):
      // the live total settles at the full sum without truncation.
      await expectLater(
        watchSupervisorMonthTotal(
            db: fake, supervisorDocId: 's1', monthKey: month),
        emitsThrough(expected),
      );
      await expectLater(
        watchTeamMonthTotal(
          db: fake,
          repCodes: [for (var i = 0; i < 12; i++) 'R$i'],
          monthKey: month,
        ),
        emitsThrough(expected),
      );
    });

    test('8. month transition: each key reads its own total', () async {
      final fake = FakeFirebaseFirestore();
      await fake.collection('salesRep').doc('r1').set({
        'repCode': 'R1',
        'clientCounts': {
          '2026-10': {'total': 9},
          '2026-11': {'total': 18},
        },
      });
      await expectLater(
        watchRepMonthTotal(db: fake, repCode: 'R1', monthKey: '2026-10'),
        emits(9),
      );
      await expectLater(
        watchRepMonthTotal(db: fake, repCode: 'R1', monthKey: '2026-11'),
        emits(18),
      );
    });

    test('9. missing counter for the month reads 0', () async {
      final fake = FakeFirebaseFirestore();
      await fake.collection('salesRep').doc('r1').set({
        'repCode': 'R1',
        'clientCounts': {
          '2026-10': {'total': 9}
        },
      });
      await fake.collection('salesRep').doc('r2').set({'repCode': 'R2'});
      await expectLater(
        watchRepMonthTotal(db: fake, repCode: 'R1', monthKey: month),
        emits(0),
      );
      await expectLater(
        watchRepMonthTotal(db: fake, repCode: 'R2', monthKey: month),
        emits(0),
      );
      await expectLater(
        watchRepMonthTotal(db: fake, repCode: 'RX', monthKey: month),
        emits(0),
      );
      await expectLater(
        watchSupervisorMonthTotal(
            db: fake, supervisorDocId: 'nobody', monthKey: month),
        emits(0),
      );
    });

    test('10. counter update while listening emits the new total', () async {
      final fake = FakeFirebaseFirestore();
      await fake.collection('salesRep').doc('r1').set(repDoc('R1', 5));
      final stream = watchRepMonthTotal(
        db: fake,
        repCode: 'R1',
        monthKey: month,
      );
      final expectation = expectLater(stream, emitsInOrder([5, 8]));
      await fake.collection('salesRep').doc('r1').update({
        'clientCounts': {
          month: {'total': 8}
        },
      });
      await expectation;
    });

    test('rep day counter reads days entry and updates live', () async {
      final fake = FakeFirebaseFirestore();
      await fake
          .collection('salesRep')
          .doc('r1')
          .set(repDoc('R1', 18, dayTotal: 4));
      final stream = watchRepDayTotal(
        db: fake,
        repCode: 'R1',
        monthKey: month,
        dayKey: day,
      );
      final expectation = expectLater(stream, emitsInOrder([4, 6]));
      await fake.collection('salesRep').doc('r1').update({
        'clientCounts': {
          month: {
            'total': 20,
            'days': {day: 6},
          },
        },
      });
      await expectation;
    });
  });
}
