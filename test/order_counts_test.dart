import 'package:aksab_sales/utils/order_counts.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

// Single Source of Truth tests for the NESTED order performance counters,
// mirroring cashback/orders_performance_counter (counter.js `bucketPaths`):
// `salesRep.ordersByMonth.{YYYY-MM}.{new,delivered,cancelled}.total`,
// per-bucket `days.{day}`, and money ONLY as `delivered.value` /
// `delivered.valueByDay.{day}`. No flat month-level total or deliveredValue.
void main() {
  const month = '2026-11';
  const day = '2026-11-17';

  // Builds one rep doc with the REAL nested backend shape.
  Map<String, dynamic> repDoc(
    String code, {
    int fresh = 0,
    int delivered = 0,
    int cancelled = 0,
    double deliveredValue = 0,
    Map<String, int>? newDays,
    Map<String, int>? deliveredDays,
    Map<String, int>? cancelledDays,
    Map<String, double>? valueByDay,
  }) {
    Map<String, dynamic> bucket(int total,
        {Map<String, int>? days, double? value, Map<String, double>? byDay}) {
      final m = <String, dynamic>{'total': total};
      if (days != null) m['days'] = days;
      if (value != null) m['value'] = value;
      if (byDay != null) m['valueByDay'] = byDay;
      return m;
    }

    return {
      'repCode': code,
      'repType': 'permanent',
      'ordersByMonth': {
        month: {
          'new': bucket(fresh, days: newDays),
          'delivered': bucket(delivered,
              days: deliveredDays, value: deliveredValue, byDay: valueByDay),
          'cancelled': bucket(cancelled, days: cancelledDays),
        },
      },
    };
  }

  group('status mapping (exactly three states)', () {
    test('new-order and new both map to new', () {
      expect(normalizeOrderStatus('new-order'), 'new');
      expect(normalizeOrderStatus('new'), 'new');
    });

    test('delivered and cancelled map to themselves', () {
      expect(normalizeOrderStatus('delivered'), 'delivered');
      expect(normalizeOrderStatus('cancelled'), 'cancelled');
    });

    test('shipped and processing are not performance states', () {
      expect(normalizeOrderStatus('shipped'), isNull);
      expect(normalizeOrderStatus('processing'), isNull);
      expect(normalizeOrderStatus(''), isNull);
      expect(normalizeOrderStatus(null), isNull);
    });
  });

  group('pure counter reads (nested buckets)', () {
    test('month summary derives total and value from buckets', () {
      final doc = repDoc('R1',
          fresh: 4, delivered: 5, cancelled: 1, deliveredValue: 250.5);
      final s = repOrderMonthSummary(doc, month);
      expect(s.total, 10);
      expect(s.fresh, 4);
      expect(s.delivered, 5);
      expect(s.cancelled, 1);
      expect(s.deliveredValue, 250.5);

      expect(repOrderMonthSummary(const {}, month),
          const OrderMonthSummary());
      expect(repOrderMonthSummary(null, month), const OrderMonthSummary());
      // A different month reads as 0 (no fallback).
      expect(repOrderMonthSummary(doc, '2026-10'),
          const OrderMonthSummary());
    });

    test('flat month-level fields are ignored (schema has none)', () {
      // A doc carrying the OLD flat assumption must read as empty:
      // backend never writes these paths.
      final flat = {
        'repCode': 'R1',
        'ordersByMonth': {
          month: {
            'total': 99,
            'new': 10,
            'delivered': 20,
            'cancelled': 5,
            'deliveredValue': 777.0,
          },
        },
      };
      expect(repOrderMonthSummary(flat, month), const OrderMonthSummary());
    });

    test('non-numeric and missing buckets read as 0', () {
      expect(
        repOrderMonthSummary({
          'ordersByMonth': {
            month: {
              'new': {'total': 'bad'},
              'delivered': {'total': 2, 'value': 'bad'},
            }
          }
        }, month),
        const OrderMonthSummary(fresh: 0, delivered: 2, total: 2),
      );
    });

    test('delivered.value is the ONLY money source', () {
      final doc = {
        'repCode': 'R1',
        'ordersByMonth': {
          month: {
            'new': {'total': 2},
            'delivered': {'total': 2, 'value': 400},
            'cancelled': {'total': 1},
          },
        },
      };
      expect(repOrderMonthDeliveredValue(doc, month), 400);
      expect(repOrderMonthTotal(doc, month), 5);
      // avgDelivered guards division by zero.
      expect(repOrderMonthSummary(doc, month).avgDelivered, 200);
      expect(const OrderMonthSummary().avgDelivered, 0);
    });

    test('day summary sums per-bucket day entries', () {
      final doc = repDoc('R1',
          fresh: 10,
          delivered: 10,
          cancelled: 10,
          deliveredValue: 500,
          newDays: {day: 3},
          deliveredDays: {day: 2},
          cancelledDays: {day: 1});
      final d = repOrderDaySummary(doc, month, day);
      expect(d.total, 6);
      expect(d.fresh, 3);
      expect(d.delivered, 2);
      expect(d.cancelled, 1);
      // Day entries carry no money in the backend.
      expect(d.deliveredValue, 0);
      expect(repOrderDaySummary(doc, month, '2026-11-18'),
          const OrderMonthSummary());
    });

    test('sum of day totals matches month total (consistent fixture)', () {
      final doc = repDoc('R1',
          fresh: 2,
          delivered: 2,
          cancelled: 1,
          deliveredValue: 700,
          newDays: {'2026-11-01': 1, '2026-11-02': 1},
          deliveredDays: {'2026-11-01': 1, '2026-11-02': 1},
          cancelledDays: {'2026-11-02': 1},
          valueByDay: {'2026-11-01': 300, '2026-11-02': 400});
      final m = repOrderMonthSummary(doc, month);
      var dayTotal = 0;
      for (final k in ['2026-11-01', '2026-11-02']) {
        dayTotal += repOrderDayTotal(doc, month, k);
      }
      expect(dayTotal, m.total);
      // valueByDay reconciles with delivered.value.
      final daily = orderDailyDeliveredValues(doc, month);
      expect(daily.values.fold<double>(0, (a, b) => a + b),
          m.deliveredValue);
    });

    test('team sums across distinct repCodes only (no double count)', () {
      final sum = sumTeamOrderMonthSummary(
        repDataByCode: {
          'R1': repDoc('R1', delivered: 5, deliveredValue: 100),
          'R2': repDoc('R2', fresh: 7, deliveredValue: 0),
        },
        monthKey: month,
      );
      expect(sum.total, 12);
      expect(sum.deliveredValue, 100);
    });

    test('all-time rollup sums every month (aggregate-only)', () {
      final doc = {
        'repCode': 'R1',
        'ordersByMonth': {
          '2026-10': {
            'new': {'total': 1},
            'delivered': {'total': 2, 'value': 300},
            'cancelled': {'total': 0},
          },
          month: {
            'new': {'total': 0},
            'delivered': {'total': 1, 'value': 150},
            'cancelled': {'total': 1},
          },
        },
      };
      final all = sumAllTimeOrderSummary(doc);
      expect(all.total, 5);
      expect(all.deliveredValue, 450);
      expect(sumAllTimeOrderSummary(const {}), const OrderMonthSummary());
    });

    test('hasOrderMonthCounter gates display on a usable counter', () {
      expect(hasOrderMonthCounter(repDoc('R1', delivered: 1), month), isTrue);
      expect(hasOrderMonthCounter(const {}, month), isFalse);
      expect(hasOrderMonthCounter(null, month), isFalse);
      // Flat leftovers do not count as a counter.
      expect(
          hasOrderMonthCounter({
            'ordersByMonth': {
              month: {'total': 5}
            }
          }, month),
          isFalse);
    });

    test('daily delivered values come from valueByDay', () {
      final doc = repDoc('R1',
          delivered: 3,
          deliveredValue: 500,
          valueByDay: {'2026-11-01': 200, '2026-11-03': 300});
      final daily = orderDailyDeliveredValues(doc, month);
      expect(daily[1], 200);
      expect(daily[3], 300);
      expect(daily.containsKey(2), isFalse);
    });
  });

  group('live counter streams (fake_cloud_firestore)', () {
    test('rep with a single doc reads its summary and today', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('salesRep').add(repDoc('R1',
          fresh: 3,
          delivered: 5,
          cancelled: 1,
          deliveredValue: 450,
          newDays: {day: 1},
          deliveredDays: {day: 1},
          cancelledDays: {day: 0}));
      final m = await watchRepOrderMonthSummary(
              db: db, repCode: 'R1', monthKey: month)
          .first;
      expect(m.total, 9);
      expect(m.deliveredValue, 450);
      final d = await watchRepOrderDaySummary(
              db: db, repCode: 'R1', monthKey: month, dayKey: day)
          .first;
      expect(d.total, 2);
    });

    test('duplicate docs for one repCode are read once (first wins)', () async {
      final db = FakeFirebaseFirestore();
      await db
          .collection('salesRep')
          .add(repDoc('R1', delivered: 4, deliveredValue: 100));
      await db
          .collection('salesRep')
          .add(repDoc('R1', delivered: 4, deliveredValue: 100));
      final m = await watchRepOrderMonthSummary(
              db: db, repCode: 'R1', monthKey: month)
          .first;
      expect(m.total, 4);
    });

    test('supervisor team sums distinct reps, excludes supervisor self',
        () async {
      final db = FakeFirebaseFirestore();
      const supId = 'sup1';
      await db.collection('salesRep').add({
        ...repDoc('R1', delivered: 5, deliveredValue: 100),
        'supervisorId': supId,
      });
      await db.collection('salesRep').add({
        ...repDoc('R2', fresh: 7, deliveredValue: 0),
        'supervisorId': supId,
      });
      final m = await watchSupervisorOrderMonthSummary(
              db: db, supervisorDocId: supId, monthKey: month)
          .first;
      expect(m.total, 12);
      expect(m.deliveredValue, 100);
    });

    test('manager hierarchy dedupes reps under two supervisors', () async {
      final db = FakeFirebaseFirestore();
      const mgrId = 'mgr1';
      final supA = await db.collection('managers').add({
        'managerId': mgrId,
        'role': 'sales_supervisor',
      });
      final supB = await db.collection('managers').add({
        'managerId': mgrId,
        'role': 'sales_supervisor',
      });
      await db.collection('salesRep').add({
        ...repDoc('R1', delivered: 5, deliveredValue: 100),
        'supervisorId': supA.id,
      });
      // Same repCode under the second supervisor holds the same counter:
      // it must count once.
      await db.collection('salesRep').add({
        ...repDoc('R1', delivered: 5, deliveredValue: 100),
        'supervisorId': supB.id,
      });
      await db.collection('salesRep').add({
        ...repDoc('R2', fresh: 7),
        'supervisorId': supB.id,
      });
      final m = await watchManagerOrderMonthSummary(
              db: db, managerDocId: mgrId, monthKey: month)
          .first;
      expect(m.total, 12);
      expect(m.deliveredValue, 100);
    });

    test('missing month emits 0 (no throw, no fake data)', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('salesRep').add(repDoc('R1', delivered: 9));
      final m = await watchRepOrderMonthSummary(
              db: db, repCode: 'R1', monthKey: '2030-01')
          .first;
      expect(m, const OrderMonthSummary());
    });

    test('stream updates when the salesRep doc changes', () async {
      final db = FakeFirebaseFirestore();
      final ref = await db
          .collection('salesRep')
          .add(repDoc('R1', delivered: 1, deliveredValue: 50));
      final stream = watchRepOrderMonthSummary(
          db: db, repCode: 'R1', monthKey: month);
      await expectLater(stream, emits(const OrderMonthSummary(
          total: 1, delivered: 1, deliveredValue: 50)));
      await ref.update({
        'ordersByMonth': {
          month: {
            'new': {'total': 1},
            'delivered': {'total': 2, 'value': 120},
            'cancelled': {'total': 0},
          },
        },
      });
      await expectLater(stream, emits(const OrderMonthSummary(
          total: 3, fresh: 1, delivered: 2, deliveredValue: 120)));
    });
  });
}
