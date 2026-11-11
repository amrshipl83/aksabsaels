import 'package:aksab_sales/utils/target_distribution.dart';
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

  group('summarizeTargetEntry', () {
    test('missing month reports hasTarget false', () {
      final summary = summarizeTargetEntry(null, '2026-11');
      expect(summary['hasTarget'], isFalse);
    });
  });
}
