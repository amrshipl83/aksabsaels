import 'package:aksab_sales/utils/target_distribution.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

// Phase-2 distribution math (pure, no Firestore): month keys, sums,
// remaining, caps, entry building with audit history.
void main() {
  Map<String, double> vals({
    double financial = 0,
    double hours = 0,
    double invoices = 0,
    double clients = 0,
    double visits = 0,
  }) =>
      {
        'financialTarget': financial,
        'hoursTarget': hours,
        'invoicesTarget': invoices,
        'clientsTarget': clients,
        'visitsTarget': visits,
      };

  group('targetMonthKey', () {
    test('formats yyyy-MM', () {
      expect(targetMonthKey(DateTime(2026, 11, 2)), '2026-11');
      expect(isValidTargetMonthKey('2026-11'), isTrue);
      expect(isValidTargetMonthKey('2026-13'), isFalse);
    });
  });

  group('sumAllocations / remainingTargets', () {
    test('sums per indicator and computes remaining', () {
      final sum = sumAllocations([
        vals(financial: 1000, visits: 10),
        vals(financial: 500, visits: 5),
      ]);
      expect(sum['financialTarget'], 1500);
      expect(sum['visitsTarget'], 15);
      expect(sum['hoursTarget'], 0);

      final remaining = remainingTargets(
        received: vals(financial: 2000, visits: 20),
        distributed: sum,
      );
      expect(remaining['financialTarget'], 500);
      expect(remaining['visitsTarget'], 5);
    });
  });

  group('validateDistribution', () {
    test('accepts within-cap proposals', () {
      expect(
        validateDistribution(
          received: vals(financial: 1000),
          othersSum: vals(financial: 400),
          proposed: vals(financial: 600),
        ),
        isNull,
      );
    });

    test('rejects exceeding any single indicator with Arabic message', () {
      final error = validateDistribution(
        received: vals(financial: 1000, visits: 20),
        othersSum: vals(financial: 400),
        proposed: vals(financial: 601),
      );
      expect(error, isNotNull);
      expect(error, contains('الهدف المالي'));
      expect(error, contains('600'));
    });

    test('edit path: own previous share is excluded via othersSum', () {
      // Supervisor had 400, wants 500; others hold 400; received 1000.
      // othersSum excludes the edited supervisor, so 400 + 500 <= 1000 ok.
      expect(
        validateDistribution(
          received: vals(financial: 1000),
          othersSum: vals(financial: 400),
          proposed: vals(financial: 500),
        ),
        isNull,
      );
    });
  });

  group('buildSupervisorTargetEntry', () {
    test('merges over legacy entries and preserves unrelated keys', () {
      final entry = buildSupervisorTargetEntry(
        existingEntry: {
          'financialTarget': 300,
          'visitsTarget': 5,
          'locked': true,
          'customNote': 'keep-me',
        },
        values: {'financialTarget': 500, 'visitsTarget': 8},
        setByUid: 'mgr1',
        now: DateTime(2026, 11, 11),
      );
      expect(entry['financialTarget'], 500);
      expect(entry['visitsTarget'], 8);
      expect(entry['customNote'], 'keep-me');
      expect(entry['setByRole'], 'sales_manager');
      expect((entry['history'] as List), hasLength(1));
    });

    test('edits append history instead of erasing it', () {
      final first = buildSupervisorTargetEntry(
        existingEntry: null,
        values: {'financialTarget': 100},
        setByUid: 'mgr1',
        now: DateTime(2026, 11, 11),
      );
      final second = buildSupervisorTargetEntry(
        existingEntry: first,
        values: {'financialTarget': 200},
        setByUid: 'mgr1',
        now: DateTime(2026, 11, 12),
      );
      expect((second['history'] as List), hasLength(2));
      expect(second['financialTarget'], 200);
    });
  });

  group('applyDistributionToManager', () {
    test('keeps received values, refreshes distributed, logs audit', () {
      final updated = applyDistributionToManager(
        managerEntry: {
          'financialTarget': 1000,
          'visitsTarget': 20,
          'setByUid': 'admin',
          'history': [
            {'note': 'set'}
          ],
        },
        distributed: vals(financial: 600, visits: 12),
        setByUid: 'mgr1',
        supervisorId: 's1',
        now: DateTime(2026, 11, 11),
      );
      expect(updated['financialTarget'], 1000);
      expect((updated['distributed'] as Map)['financialTarget'], 600);
      expect(updated['status'], kTargetStatusPartial);
      expect((updated['history'] as List), hasLength(2));
      expect(
          ((updated['history'] as List).last as Map)['note'], 'distribute');
    });

    test('marks fully distributed when totals reach received', () {
      final updated = applyDistributionToManager(
        managerEntry: {'financialTarget': 1000},
        distributed: vals(financial: 1000),
        setByUid: 'mgr1',
        supervisorId: 's1',
        now: DateTime(2026, 11, 11),
      );
      expect(updated['status'], kTargetStatusFull);
    });
  });

  group('distributeRepTarget (supervisor → rep)', () {
    const month = '2026-11';

    Future<FakeFirebaseFirestore> seed() async {
      final fake = FakeFirebaseFirestore();
      await fake.collection('managers').doc('s1').set({
        'role': 'sales_supervisor',
        'targets': {
          month: {
            'financialTarget': 5000,
            'hoursTarget': 100,
            'invoicesTarget': 50,
            'clientsTarget': 20,
            'visitsTarget': 30,
            'setByUid': 'm1',
            'history': [
              {'note': 'set'}
            ],
          },
        },
      });
      await fake.collection('salesRep').doc('p1').set({
        'fullname': 'مندوب أول',
        'repCode': 'R1',
        'repType': 'permanent',
        'supervisorId': 's1',
      });
      await fake.collection('salesRep').doc('p2').set({
        'fullname': 'مندوب ثان',
        'repCode': 'R2',
        'repType': 'permanent',
        'supervisorId': 's1',
      });
      return fake;
    }

    test('saves rep entry and updates holder totals + audit', () async {
      final fake = await seed();
      await distributeRepTarget(
        db: fake,
        supervisorId: 's1',
        repId: 'p1',
        allRepIds: const ['p1', 'p2'],
        month: month,
        values: {'financialTarget': 2000, 'visitsTarget': 10},
        setByUid: 's1',
        now: DateTime(2026, 11, 11),
      );
      final rep = await fake.collection('salesRep').doc('p1').get();
      final entry = (rep.data()!['targets'] as Map)[month] as Map;
      expect(entry['financialTarget'], 2000);
      expect(entry['visitsTarget'], 10);
      expect(entry['setByRole'], 'sales_supervisor');
      expect((entry['history'] as List), hasLength(1));

      final sup = await fake.collection('managers').doc('s1').get();
      final sEntry = (sup.data()!['targets'] as Map)[month] as Map;
      expect((sEntry['distributed'] as Map)['financialTarget'], 2000);
      expect(sEntry['financialTarget'], 5000); // received untouched
      final history = sEntry['history'] as List;
      expect(history, hasLength(2));
      expect((history.last as Map)['note'], 'distribute');
      expect(
          ((history.last as Map)['changes'] as Map)['repId'], 'p1');
    });

    test('overlapping second share fails inside the transaction', () async {
      final fake = await seed();
      await distributeRepTarget(
        db: fake,
        supervisorId: 's1',
        repId: 'p1',
        allRepIds: const ['p1', 'p2'],
        month: month,
        values: {'financialTarget': 3000},
        setByUid: 's1',
        now: DateTime(2026, 11, 11),
      );
      await expectLater(
        distributeRepTarget(
          db: fake,
          supervisorId: 's1',
          repId: 'p2',
          allRepIds: const ['p1', 'p2'],
          month: month,
          values: {'financialTarget': 2500},
          setByUid: 's1',
          now: DateTime(2026, 11, 11),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('merge preserves legacy keys on the rep doc', () async {
      final fake = await seed();
      await fake.collection('salesRep').doc('p1').update({
        'targets': {
          month: {'financialTarget': 300, 'visitsTarget': 5, 'locked': true},
        },
      });
      await distributeRepTarget(
        db: fake,
        supervisorId: 's1',
        repId: 'p1',
        allRepIds: const ['p1', 'p2'],
        month: month,
        values: {'financialTarget': 500, 'visitsTarget': 8},
        setByUid: 's1',
        now: DateTime(2026, 11, 11),
      );
      final rep = await fake.collection('salesRep').doc('p1').get();
      final entry = (rep.data()!['targets'] as Map)[month] as Map;
      expect(entry['financialTarget'], 500);
      expect(entry['locked'], isTrue);
    });
  });

  group('summarizeTargetEntry', () {
    test('missing month reports hasTarget false', () {
      final summary = summarizeTargetEntry(null, '2026-11');
      expect(summary['hasTarget'], isFalse);
    });
  });

  group('monthProgress', () {
    test('current month reports partial progress', () {
      final p = monthProgress(
          now: DateTime(2026, 11, 11), year: 2026, month: 11);
      expect(p['daysInMonth'], 30);
      expect(p['elapsedDays'], 11);
      expect(p['remainingDays'], 19);
      expect((p['percent'] as double).toStringAsFixed(1), '36.7');
    });

    test('past month reports 100% with nothing remaining', () {
      final p = monthProgress(
          now: DateTime(2026, 11, 11), year: 2026, month: 10);
      expect(p['percent'], 100);
      expect(p['remainingDays'], 0);
    });

    test('future month reports 0% with all days remaining', () {
      final p = monthProgress(
          now: DateTime(2026, 11, 11), year: 2026, month: 12);
      expect(p['percent'], 0);
      expect(p['elapsedDays'], 0);
      expect(p['remainingDays'], 31);
    });
  });
}
