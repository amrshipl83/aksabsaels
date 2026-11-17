import 'package:aksab_sales/utils/rep_customer_count.dart';
import 'package:flutter_test/flutter_test.dart';

// Pins the rep-goal customer counting contract:
// - only rep-registered buyers (repCode match) with a recorded first login
//   at/after go-live AND created at/after go-live count, exactly once;
// - legacy, self-registered, and pre-login docs never count.
void main() {
  final goLive = DateTime.utc(2026, 11, 14);
  Map<String, dynamic> doc({
    String repCode = 'R1',
    DateTime? firstLoginAt,
    DateTime? createdAt,
    String? uid,
  }) =>
      {
        if (uid != null) 'uid': uid,
        'repCode': repCode,
        'firstLoginAt': firstLoginAt,
        'createdAt': createdAt,
      };

  group('repCustomerCountsTowardGoal', () {
    test('counts a rep buyer with first login after go-live', () {
      expect(
        repCustomerCountsTowardGoal(
          data: doc(
            firstLoginAt: DateTime.utc(2026, 11, 15),
            createdAt: DateTime.utc(2026, 11, 14, 1),
          ),
          repCode: 'R1',
          goLive: goLive,
        ),
        isTrue,
      );
    });

    test('exact go-live boundary counts (not before)', () {
      expect(
        repCustomerCountsTowardGoal(
          data: doc(firstLoginAt: goLive, createdAt: goLive),
          repCode: 'R1',
          goLive: goLive,
        ),
        isTrue,
      );
    });

    test('rep buyer before first login does not count', () {
      expect(
        repCustomerCountsTowardGoal(
          data: doc(
            firstLoginAt: null,
            createdAt: DateTime.utc(2026, 11, 15),
          ),
          repCode: 'R1',
          goLive: goLive,
        ),
        isFalse,
      );
    });

    test('self-registered buyer (no repCode) never counts', () {
      expect(
        repCustomerCountsTowardGoal(
          data: {
            'firstLoginAt': DateTime.utc(2026, 11, 15),
            'createdAt': DateTime.utc(2026, 11, 15),
          },
          repCode: 'R1',
          goLive: goLive,
        ),
        isFalse,
      );
      expect(
        repCustomerCountsTowardGoal(
          data: doc(
            repCode: 'R2',
            firstLoginAt: DateTime.utc(2026, 11, 15),
            createdAt: DateTime.utc(2026, 11, 15),
          ),
          repCode: 'R1',
          goLive: goLive,
        ),
        isFalse,
      );
    });

    test('legacy account (created before go-live) is not retroactive', () {
      expect(
        repCustomerCountsTowardGoal(
          data: doc(
            firstLoginAt: DateTime.utc(2026, 11, 20),
            createdAt: DateTime.utc(2026, 1, 5),
          ),
          repCode: 'R1',
          goLive: goLive,
        ),
        isFalse,
      );
    });

    test('missing createdAt fails closed', () {
      expect(
        repCustomerCountsTowardGoal(
          data: {
            'repCode': 'R1',
            'firstLoginAt': DateTime.utc(2026, 11, 15),
          },
          repCode: 'R1',
          goLive: goLive,
        ),
        isFalse,
      );
    });

    test('accepts epoch-millis numbers (Firestore Timestamp shape)', () {
      expect(
        repCustomerCountsTowardGoal(
          data: {
            'repCode': 'R1',
            'firstLoginAt': DateTime.utc(2026, 11, 15).millisecondsSinceEpoch,
            'createdAt': DateTime.utc(2026, 11, 15).millisecondsSinceEpoch,
          },
          repCode: 'R1',
          goLive: goLive,
        ),
        isTrue,
      );
    });
  });

  group('countRepGoalCustomers', () {
    test('counts each UID once even with duplicate docs', () {
      final docs = <String, Map<String, dynamic>>{
        'uidA': doc(
          uid: 'uidA',
          firstLoginAt: DateTime.utc(2026, 11, 15),
          createdAt: DateTime.utc(2026, 11, 15),
        ),
        'uidA-dup': doc(
          uid: 'uidA',
          firstLoginAt: DateTime.utc(2026, 11, 16),
          createdAt: DateTime.utc(2026, 11, 15),
        ),
        'uidB': doc(
          uid: 'uidB',
          firstLoginAt: DateTime.utc(2026, 11, 15),
          createdAt: DateTime.utc(2026, 11, 15),
        ),
        'uidC': doc(
          uid: 'uidC',
          firstLoginAt: null,
          createdAt: DateTime.utc(2026, 11, 15),
        ),
      };
      expect(
        countRepGoalCustomers(docsById: docs, repCode: 'R1', goLive: goLive),
        2,
      );
    });

    test('team variant scopes by rep set, still once per UID', () {
      final docs = <String, Map<String, dynamic>>{
        'a': doc(
          uid: 'a',
          repCode: 'R1',
          firstLoginAt: DateTime.utc(2026, 11, 15),
          createdAt: DateTime.utc(2026, 11, 15),
        ),
        'b': doc(
          uid: 'b',
          repCode: 'R2',
          firstLoginAt: DateTime.utc(2026, 11, 15),
          createdAt: DateTime.utc(2026, 11, 15),
        ),
        'c': doc(
          uid: 'c',
          repCode: 'R9',
          firstLoginAt: DateTime.utc(2026, 11, 15),
          createdAt: DateTime.utc(2026, 11, 15),
        ),
      };
      expect(
        countRepGoalCustomersForTeam(
          docsById: docs,
          repCodes: {'R1', 'R2'},
          goLive: goLive,
        ),
        2,
      );
      expect(
        countRepGoalCustomersForTeam(
          docsById: docs,
          repCodes: const {},
          goLive: goLive,
        ),
        0,
      );
    });
  });

  group('sumClientCountsTotal / hasClientCountsMonth', () {
    test('sums total across duplicate repCode docs', () {
      final docs = <Map<String, dynamic>>[
        {
          'repCode': 'R1',
          'clientCounts': {
            '2026-11': {'total': 3, 'days': {'2026-11-16': 3}},
          },
        },
        {
          'repCode': 'R1',
          'clientCounts': {
            '2026-11': {'total': 3, 'days': {'2026-11-16': 3}},
          },
        },
      ];
      expect(
        sumClientCountsTotal(repDocs: docs, monthKey: '2026-11'),
        6,
      );
      expect(
        hasClientCountsMonth(repDocs: docs, monthKey: '2026-11'),
        isTrue,
      );
    });

    test('missing month or maps contribute 0 and flag absence', () {
      final docs = <Map<String, dynamic>>[
        {'repCode': 'R1'},
        {'repCode': 'R1', 'clientCounts': {'2026-10': {'total': 9}}},
        {'repCode': 'R1', 'clientCounts': {'2026-11': {'total': 'bad'}}},
      ];
      expect(
        sumClientCountsTotal(repDocs: docs, monthKey: '2026-11'),
        0,
      );
      expect(
        hasClientCountsMonth(repDocs: docs, monthKey: '2026-11'),
        isFalse,
      );
      expect(
        hasClientCountsMonth(repDocs: docs, monthKey: '2026-10'),
        isTrue,
      );
    });
  });
}
