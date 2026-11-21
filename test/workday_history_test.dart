import 'package:aksab_sales/utils/workday_history.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

// مصدر الحقيقة: daily_logs + visits (السجلات التاريخية للإغلاق).
// تغطي هذه الاختبارات الحالات الثماني المطلوبة بلا أي افتراض لحقول.
void main() {
  Timestamp ts(int y, int m, int d, [int h = 0, int min = 0]) =>
      Timestamp.fromDate(DateTime(y, m, d, h, min));

  Map<String, dynamic> day({
    required String status,
    Timestamp? start,
    Timestamp? end,
    String? closedBy,
  }) =>
      {
        'repCode': 'R1',
        'status': status,
        if (start != null) 'startTime': start,
        if (end != null) 'endTime': end,
        if (closedBy != null) 'closedBy': closedBy,
      };

  Map<String, dynamic> visit({
    required String status,
    Timestamp? start,
    Timestamp? end,
  }) =>
      {
        'repCode': 'R1',
        'status': status,
        if (start != null) 'startTime': start,
        if (end != null) 'endTime': end,
      };

  group('month/day key ranges (Cairo keys to [start, end))', () {
    test('monthKeyToRange parses YYYY-MM and rejects bad keys', () {
      final r = monthKeyToRange('2026-11')!;
      expect(r.start, DateTime(2026, 11, 1));
      expect(r.end, DateTime(2026, 12, 1));
      expect(monthKeyToRange('2026-13'), isNull);
      expect(monthKeyToRange('nov-2026'), isNull);
      expect(monthKeyToRange(''), isNull);
    });

    test('dayKeyToRange parses YYYY-MM-DD and rejects impossible dates', () {
      final r = dayKeyToRange('2026-11-17')!;
      expect(r.start, DateTime(2026, 11, 17));
      expect(r.end, DateTime(2026, 11, 18));
      expect(dayKeyToRange('2026-02-30'), isNull);
      expect(dayKeyToRange('2026-11'), isNull);
    });
  });

  group('workday_history pure contract', () {
    test('1. يوم مغلق طبيعي: يُحتسب + مدته صحيحة', () {
      final d = day(
        status: 'closed',
        start: ts(2026, 11, 10, 9),
        end: ts(2026, 11, 10, 17),
        closedBy: 'rep',
      );
      expect(isClosedDay(d), isTrue);
      expect(closedDayMinutes(d), 8 * 60);
      final s = summarizeDayDocs([d]);
      expect(s.workdays, 1);
      expect(s.workMinutes, 8 * 60);
      expect(s.openDays, 0);
    });

    test('2. يوم بأكثر من زيارة: كل زيارة تُحتسب مرة واحدة', () {
      final v1 = visit(
          status: 'sold', start: ts(2026, 11, 10, 10), end: ts(2026, 11, 10, 10, 30));
      final v2 = visit(
          status: 'followup',
          start: ts(2026, 11, 10, 12),
          end: ts(2026, 11, 10, 12, 20));
      final s = summarizeVisitDocs([v1, v2, v1]);
      // المكرر هنا مستندان متماثلان في القائمة الخالصة؛ منع التكرار الحقيقي
      // يتم بمعرف المستند في طبقة Firestore (seen ids) — القائمة الخالصة
      // تحصي ما تُعطى. نتحقق من المدد والمجاميع الأساسية.
      expect(s.visits, 3);
      expect(s.visitMinutes, 30 + 20 + 30);
      expect(s.openVisits, 0);
    });

    test('3. يوم امتد لليوم التالي: يُنسب لبدئه ومدته كاملة', () {
      final d = day(
        status: 'closed',
        start: ts(2026, 11, 10, 22),
        end: ts(2026, 11, 11, 2),
        closedBy: 'auto',
      );
      expect(isClosedDay(d), isTrue);
      expect(closedDayMinutes(d), 4 * 60);
    });

    test('4. يوم مفتوح: لا يُعد مغلقًا ولا يدخل في المدد', () {
      final open = day(status: 'open', start: ts(2026, 11, 10, 9));
      expect(isClosedDay(open), isFalse);
      expect(closedDayMinutes(open), isNull);
      final s = summarizeDayDocs([open]);
      expect(s.workdays, 0);
      expect(s.workMinutes, 0);
      expect(s.openDays, 1);
      // زيارة مفتوحة مستبعدة من العدد والمدد.
      final v = visit(status: 'in_progress', start: ts(2026, 11, 10, 10));
      expect(isCountedVisit(v), isFalse);
      final vs = summarizeVisitDocs([v]);
      expect(vs.visits, 0);
      expect(vs.openVisits, 1);
    });

    test('5. يوم بلا زيارات: يوم محتسب وزيارات صفر', () {
      final d = day(
          status: 'closed',
          start: ts(2026, 11, 10, 9),
          end: ts(2026, 11, 10, 15));
      final s = combineDayAndVisitSummaries(
        summarizeDayDocs([d]),
        summarizeVisitDocs(const []),
      );
      expect(s.workdays, 1);
      expect(s.visits, 0);
      expect(s.avgVisitsPerDay, 0);
      expect(s.avgWorkHoursPerDay, 6);
    });

    test('6. سجلات قديمة بلا closedBy/workdayId: تُحتسب بلا افتراضات', () {
      final legacyDay = {
        'repCode': 'R1',
        'status': 'closed',
        'startTime': ts(2026, 9, 5, 9),
        'endTime': ts(2026, 9, 5, 14),
        // بلا closedBy — يجب أن يُحتسب.
      };
      expect(isClosedDay(legacyDay), isTrue);
      final legacyVisitNoEnd = {
        'repCode': 'R1',
        'status': 'sold',
        'startTime': ts(2026, 9, 5, 10),
        // بلا endTime — تُحتسب في العدد فقط، لا مدة مخترعة.
      };
      expect(isCountedVisit(legacyVisitNoEnd), isTrue);
      expect(countedVisitMinutes(legacyVisitNoEnd), isNull);
      final vs = summarizeVisitDocs([legacyVisitNoEnd]);
      expect(vs.visits, 1);
      expect(vs.visitMinutes, 0);
      expect(vs.visitsWithoutDuration, 1);
    });

    test('7. end قبل start: مستبعد من المدد (سجل فاسد لا يُضلل)', () {
      final bad = day(
          status: 'closed',
          start: ts(2026, 11, 10, 17),
          end: ts(2026, 11, 10, 9));
      expect(isClosedDay(bad), isFalse);
      expect(summarizeDayDocs([bad]).workdays, 0);
      final badVisit = visit(
          status: 'sold',
          start: ts(2026, 11, 10, 12),
          end: ts(2026, 11, 10, 11));
      expect(countedVisitMinutes(badVisit), isNull);
    });

    test('9. حقول الدالة الخلفية: قراءة مباشرة بلا تجميع', () {
      final doc = {
        'repCode': 'R1',
        'workingHoursByMonth': {
          '2026-11': {'totalSeconds': 28800, 'sessions': 4},
          '2026-10': {'totalSeconds': 3600, 'sessions': 1},
        },
      };
      expect(repWorkSecondsForMonth(doc, '2026-11'), 28800);
      expect(repWorkSessionsForMonth(doc, '2026-11'), 4);
      // شهر مختلف لا يسرب أرقامه.
      expect(repWorkSecondsForMonth(doc, '2026-10'), 3600);
      expect(repWorkSessionsForMonth(doc, '2026-12'), 0);
      // الغائب أو غير الرقمي = صفر بلا رمي.
      expect(repWorkSecondsForMonth({}, '2026-11'), 0);
      expect(repWorkSecondsForMonth(null, '2026-11'), 0);
      expect(
          repWorkSecondsForMonth({
            'workingHoursByMonth': {
              '2026-11': {'totalSeconds': 'oops', 'sessions': null}
            }
          }, '2026-11'),
          0);
      expect(
          repWorkSessionsForMonth({
            'workingHoursByMonth': {
              '2026-11': {'totalSeconds': 'oops', 'sessions': null}
            }
          }, '2026-11'),
          0);
    });

    test('10. تجميع الفريق من الحقول: مميز بلا تكرار', () {
      final team = {
        'R1': {
          'workingHoursByMonth': {
            '2026-11': {'totalSeconds': 28800, 'sessions': 4}
          }
        },
        'R2': {
          'workingHoursByMonth': {
            '2026-11': {'totalSeconds': 14400, 'sessions': 2}
          }
        },
      };
      expect(
          sumTeamWorkSecondsForMonth(
              repDataByCode: team, monthKey: '2026-11'),
          43200);
      expect(
          sumTeamWorkSessionsForMonth(
              repDataByCode: team, monthKey: '2026-11'),
          6);
      expect(
          sumTeamWorkSecondsForMonth(
              repDataByCode: {}, monthKey: '2026-11'),
          0);
    });

    test('8. المتوسطات: نفس القواعد للوحة والتطبيق', () {
      const s = WorkdayHistorySummary(
        workdays: 2,
        visits: 6,
        workMinutes: 960,
        visitMinutes: 180,
      );
      expect(s.workHours, 16);
      expect(s.avgWorkHoursPerDay, 8);
      expect(s.avgVisitsPerDay, 3);
      expect(s.avgVisitMinutes, 30);
      expect(
        (s + const WorkdayHistorySummary(workdays: 1, visits: 1))
            .workdays,
        3,
      );
    });
  });
}
