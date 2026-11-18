import 'package:aksab_sales/utils/visit_counts.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

// Single Source of Truth tests for the unified visit performance counter:
// `salesRep.visitsByMonth.{Cairo YYYY-MM}.total`, one value per repCode,
// teams summed across DISTINCT repCodes, Cairo wall-clock month/day keys,
// live snapshots() streams, chunked whereIn (no 10-team truncation).
void main() {
  const month = '2026-11';
  const day = '2026-11-17';

  Map<String, dynamic> repDoc(String code, int total, {int? dayTotal}) => {
        'repCode': code,
        'repType': 'permanent',
        'visitsByMonth': {
          month: {
            'total': total,
            if (dayTotal != null)
              'days': {day: dayTotal},
          },
        },
      };

  group('pure counter reads', () {
    test('repVisitMonthTotal reads total, 0 when absent or bad', () {
      expect(repVisitMonthTotal(repDoc('R1', 18), month), 18);
      expect(repVisitMonthTotal(const {}, month), 0);
      expect(repVisitMonthTotal(null, month), 0);
      expect(
        repVisitMonthTotal({
          'visitsByMonth': {
            month: {'total': 'bad'}
          }
        }, month),
        0,
      );
      expect(
        repVisitMonthTotal({
          'visitsByMonth': {
            '2026-10': {'total': 9}
          }
        }, month),
        0,
      );
      // monthlySales is never a substitute for visitsByMonth.
      expect(
        repVisitMonthTotal({'monthlySales': 42}, month),
        0,
      );
    });

    test('repVisitDayTotal reads the Cairo day entry', () {
      expect(repVisitDayTotal(repDoc('R1', 18, dayTotal: 4), month, day), 4);
      expect(repVisitDayTotal(repDoc('R1', 18), month, day), 0);
      expect(repVisitDayTotal(const {}, month, day), 0);
    });

    test('hasVisitMonthCounter gates display on a usable counter', () {
      expect(hasVisitMonthCounter(repDoc('R1', 1), month), isTrue);
      expect(hasVisitMonthCounter(const {}, month), isFalse);
      expect(hasVisitMonthCounter(null, month), isFalse);
    });

    test('team sums across distinct repCodes only (no double count)', () {
      expect(
        sumTeamVisitMonthTotal(
          repDataByCode: {
            'R1': repDoc('R1', 5),
            'R2': repDoc('R2', 7),
          },
          monthKey: month,
        ),
        12,
      );
    });
  });

  group('live counter streams (fake_cloud_firestore)', () {
    test('1. rep with a single doc reads its total and today', () async {
      final fake = FakeFirebaseFirestore();
      await fake.collection('salesRep').doc('r1').set(repDoc('R1', 18, dayTotal: 4));
      await expectLater(
        watchRepVisitMonthTotal(db: fake, repCode: 'R1', monthKey: month),
        emits(18),
      );
      await expectLater(
        watchRepVisitDayTotal(
            db: fake, repCode: 'R1', monthKey: month, dayKey: day),
        emits(4),
      );
    });

    test('2. rep with two docs sharing repCode is NOT doubled', () async {
      final fake = FakeFirebaseFirestore();
      await fake.collection('salesRep').doc('r1a').set(repDoc('R1', 5));
      await fake.collection('salesRep').doc('r1b').set(repDoc('R1', 5));
      await expectLater(
        watchTeamVisitMonthTotal(
            db: fake, repCodes: const ['R1'], monthKey: month),
        emits(5),
      );
      await expectLater(
        watchRepVisitMonthTotal(db: fake, repCode: 'R1', monthKey: month),
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
        'visitsByMonth': {
          month: {'total': 100}
        },
      });
      await expectLater(
        watchSupervisorVisitMonthTotal(
            db: fake, supervisorDocId: 's1', monthKey: month),
        emits(7),
      );
    });

    test('4. manager sums teams across supervisors without duplication', () async {
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
      await expectLater(
        watchManagerVisitMonthTotal(db: fake, managerDocId: 'm1', monthKey: month),
        emits(12),
      );
    });

    test('5. empty team and unknown rep read as 0 (natural empty state)', () async {
      final fake = FakeFirebaseFirestore();
      await expectLater(
        watchSupervisorVisitMonthTotal(
            db: fake, supervisorDocId: 'ghost', monthKey: month),
        emits(0),
      );
      await expectLater(
        watchRepVisitDayTotal(
            db: fake, repCode: 'RX', monthKey: month, dayKey: day),
        emits(0),
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
      await expectLater(
        watchSupervisorVisitMonthTotal(
            db: fake, supervisorDocId: 's1', monthKey: month),
        emitsThrough(expected),
      );
    });
  });
}
