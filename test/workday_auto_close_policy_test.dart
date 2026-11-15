// اختبارات سياسة الإغلاق التلقائي ليوم العمل.
// Pure offline: بلا شبكة وبلا Firebase — تختبر قرار السياسة فقط.
import 'package:flutter_test/flutter_test.dart';

import 'package:aksab_sales/services/workday_auto_close_policy.dart';

void main() {
  final day = DateTime(2026, 1, 1, 10, 0, 0);
  final dayMs = day.millisecondsSinceEpoch;

  VisitStartRef visitAt(int h, int m, {bool open = true, String id = 'v'}) =>
      VisitStartRef(
        id: id,
        startTime: DateTime(2026, 1, 1, h, m, 0),
        isOpen: open,
      );

  group('السيناريو الأول: يوم بلا زيارات', () {
    test('قبل انتهاء الساعة: إعادة جدولة عند 11:00', () {
      final d = decideWorkdayAutoClose(
        workdayOpen: true,
        workdayStart: day,
        visits: const [],
        taskBasisMs: dayMs,
        now: DateTime(2026, 1, 1, 10, 30, 0),
      );
      expect(d.action, WorkdayAutoCloseAction.reschedule);
      expect(d.nextCheckAt, DateTime(2026, 1, 1, 11, 0, 0));
      expect(d.nextBasisMs, dayMs);
    });

    test('عند 11:00: إغلاق اليوم بسبب أول ساعة بلا زيارة', () {
      final d = decideWorkdayAutoClose(
        workdayOpen: true,
        workdayStart: day,
        visits: const [],
        taskBasisMs: dayMs,
        now: DateTime(2026, 1, 1, 11, 0, 0),
      );
      expect(d.action, WorkdayAutoCloseAction.closeWorkday);
      expect(d.reason, WorkdayAutoCloseReasons.noVisitFirstHour);
    });
  });

  group('السيناريو الثاني: زيارة أثناء الساعة الأولى', () {
    test('مهمة 11:00 تجد زيارة 10:40: لا إغلاق وفحص جديد 11:40', () {
      final d = decideWorkdayAutoClose(
        workdayOpen: true,
        workdayStart: day,
        visits: [visitAt(10, 40, id: 'v1')],
        taskBasisMs: dayMs,
        now: DateTime(2026, 1, 1, 11, 0, 0),
      );
      expect(d.action, WorkdayAutoCloseAction.reschedule);
      expect(d.nextCheckAt, DateTime(2026, 1, 1, 11, 40, 0));
    });
  });

  group('السيناريو الثالث: الزيارة انتهت يدويًا ولم تبدأ جديدة', () {
    test('مهمة 11:40 ولا زيارة أحدث من 10:40: إغلاق اليوم فقط', () {
      final d = decideWorkdayAutoClose(
        workdayOpen: true,
        workdayStart: day,
        visits: [visitAt(10, 40, open: false, id: 'v1')],
        taskBasisMs: DateTime(2026, 1, 1, 10, 40, 0).millisecondsSinceEpoch,
        now: DateTime(2026, 1, 1, 11, 40, 0),
      );
      expect(d.action, WorkdayAutoCloseAction.closeWorkday);
      expect(d.reason, WorkdayAutoCloseReasons.visitInactive1h);
      expect(d.visitIdToClose, isNull);
    });
  });

  group('السيناريو الرابع: زيارة أحدث تُبطل المهمة القديمة', () {
    test('مهمة قديمة بأساس 10:00 تجد زيارة 10:55: لا إغلاق وفحص 11:55', () {
      final d = decideWorkdayAutoClose(
        workdayOpen: true,
        workdayStart: day,
        visits: [
          visitAt(10, 40, open: false, id: 'v1'),
          visitAt(10, 55, id: 'v2'),
        ],
        taskBasisMs: dayMs,
        now: DateTime(2026, 1, 1, 11, 0, 0),
      );
      expect(d.action, WorkdayAutoCloseAction.reschedule);
      expect(d.nextCheckAt, DateTime(2026, 1, 1, 11, 55, 0));
    });

    test('كل زيارة جديدة تدفع الموعد: زيارة 12:30 تُجدول 13:30', () {
      final d = decideWorkdayAutoClose(
        workdayOpen: true,
        workdayStart: day,
        visits: [
          visitAt(10, 40, open: false, id: 'v1'),
          VisitStartRef(
            id: 'v3',
            startTime: DateTime(2026, 1, 1, 12, 30, 0),
            isOpen: true,
          ),
        ],
        taskBasisMs: DateTime(2026, 1, 1, 10, 55, 0).millisecondsSinceEpoch,
        now: DateTime(2026, 1, 1, 12, 0, 0),
      );
      expect(d.action, WorkdayAutoCloseAction.reschedule);
      expect(d.nextCheckAt, DateTime(2026, 1, 1, 13, 30, 0));
    });
  });

  group('السيناريو الخامس: الزيارة ما زالت مفتوحة', () {
    test('عند 11:40 بلا أحدث من 10:40 المفتوحة: إغلاق الزيارة ثم اليوم', () {
      final d = decideWorkdayAutoClose(
        workdayOpen: true,
        workdayStart: day,
        visits: [visitAt(10, 40, id: 'v1')],
        taskBasisMs: DateTime(2026, 1, 1, 10, 40, 0).millisecondsSinceEpoch,
        now: DateTime(2026, 1, 1, 11, 40, 0),
      );
      expect(d.action, WorkdayAutoCloseAction.closeVisitAndWorkday);
      expect(d.visitIdToClose, 'v1');
      expect(d.reason, WorkdayAutoCloseReasons.visitInactive1h);
    });
  });

  group('سلامة المهام القديمة والحالات المتزامنة', () {
    test('يوم مغلق بالفعل: أي مهمة متأخرة لا تفعل شيئًا', () {
      final d = decideWorkdayAutoClose(
        workdayOpen: false,
        workdayStart: day,
        visits: const [],
        taskBasisMs: dayMs,
        now: DateTime(2026, 1, 1, 15, 0, 0),
      );
      expect(d.action, WorkdayAutoCloseAction.noop);
    });

    test('زيارة بدأت في نفس لحظة التنفيذ تُعتبر أحدث: لا إغلاق', () {
      final at = DateTime(2026, 1, 1, 11, 0, 0);
      final d = decideWorkdayAutoClose(
        workdayOpen: true,
        workdayStart: day,
        visits: [
          VisitStartRef(id: 'v-new', startTime: at, isOpen: true),
        ],
        taskBasisMs: dayMs,
        now: at,
      );
      expect(d.action, WorkdayAutoCloseAction.reschedule);
      expect(d.nextCheckAt, DateTime(2026, 1, 1, 12, 0, 0));
    });

    test('زيارة مستقبلية عن لحظة التنفيذ: إعادة جدولة لا إغلاق', () {
      final d = decideWorkdayAutoClose(
        workdayOpen: true,
        workdayStart: day,
        visits: [visitAt(10, 40, id: 'v-late')],
        taskBasisMs: dayMs,
        now: DateTime(2026, 1, 1, 10, 20, 0),
      );
      expect(d.action, WorkdayAutoCloseAction.reschedule);
      expect(d.nextCheckAt, DateTime(2026, 1, 1, 11, 40, 0));
    });

    test('قبل الموعد بدقيقة: لا إغلاق مبكر', () {
      final d = decideWorkdayAutoClose(
        workdayOpen: true,
        workdayStart: day,
        visits: [visitAt(10, 40, id: 'v1')],
        taskBasisMs: DateTime(2026, 1, 1, 10, 40, 0).millisecondsSinceEpoch,
        now: DateTime(2026, 1, 1, 11, 39, 0),
      );
      expect(d.action, WorkdayAutoCloseAction.reschedule);
    });

    test('أحدث زيارة هي الأساس نفسه: تُطبق المهلة لا تُبطل', () {
      final basis = DateTime(2026, 1, 1, 10, 40, 0).millisecondsSinceEpoch;
      final d = decideWorkdayAutoClose(
        workdayOpen: true,
        workdayStart: day,
        visits: [visitAt(10, 40, id: 'v1')],
        taskBasisMs: basis,
        now: DateTime(2026, 1, 1, 11, 0, 0),
      );
      expect(d.action, WorkdayAutoCloseAction.reschedule);
      expect(d.nextCheckAt, DateTime(2026, 1, 1, 11, 40, 0));
    });
  });
}
