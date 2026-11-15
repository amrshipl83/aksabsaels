// توصيف حساب ساعات العمل: يثبت أن الإغلاق التلقائي لا يغيّر الحساب.
// الصيغ هنا مطابقة حرفيًا لمنطق goals_screen وperformance_dashboard:
// hours += end.difference(start).inMinutes / 60(.0)، مع تخطي ما بلا endTime،
// ولوحة الأداء ترفض end قبل start. أي تغيير مستقبلي هنا يجب أن يكون مقصودًا.
import 'package:flutter_test/flutter_test.dart';

/// صيغة goals_screen.dart (بلا حارس end قبل start).
double goalsHours(List<Map<String, DateTime?>> logs) {
  double hours = 0;
  for (final log in logs) {
    final start = log['startTime'];
    final end = log['endTime'];
    if (start != null && end != null) {
      hours += end.difference(start).inMinutes / 60.0;
    }
  }
  return hours;
}

/// صيغة performance_dashboard_screen.dart (مع حارس end قبل start).
double dashboardHours(List<Map<String, DateTime?>> logs) {
  double hours = 0;
  for (final log in logs) {
    final start = log['startTime'];
    final end = log['endTime'];
    if (start != null && end != null) {
      if (!end.isBefore(start)) {
        hours += end.difference(start).inMinutes / 60;
      }
    }
  }
  return hours;
}

void main() {
  final dayStart = DateTime(2026, 1, 1, 10, 0, 0);

  test('يوم مغلق تلقائيًا عند 11:00 يُحتسب ساعة كاملة في الشاشتين', () {
    final logs = [
      {'startTime': dayStart, 'endTime': DateTime(2026, 1, 1, 11, 0, 0)},
    ];
    expect(goalsHours(logs), 1.0);
    expect(dashboardHours(logs), 1.0);
  });

  test('يوم مفتوح بلا endTime لا يساهم بصفر في أي شاشة', () {
    final logs = [
      {'startTime': dayStart, 'endTime': null},
    ];
    expect(goalsHours(logs), 0.0);
    expect(dashboardHours(logs), 0.0);
  });

  test('يوم يدوي 8 ساعات + يوم تلقائي ساعة = 9 في الشاشتين', () {
    final logs = [
      {
        'startTime': DateTime(2026, 1, 2, 9, 0, 0),
        'endTime': DateTime(2026, 1, 2, 17, 0, 0),
      },
      {'startTime': dayStart, 'endTime': DateTime(2026, 1, 1, 11, 0, 0)},
    ];
    expect(goalsHours(logs), 9.0);
    expect(dashboardHours(logs), 9.0);
  });

  test('الدقائق الجزئية تُحتسب بالدقيقة (90 دقيقة = 1.5)', () {
    final logs = [
      {'startTime': dayStart, 'endTime': DateTime(2026, 1, 1, 11, 30, 0)},
    ];
    expect(goalsHours(logs), 1.5);
    expect(dashboardHours(logs), 1.5);
  });
}
