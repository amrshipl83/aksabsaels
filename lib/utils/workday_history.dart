// مصدر الحقيقة الموحد لأداء المندوبين من السجلات التاريخية (aksabsaels).
//
// تقرأ هذه الطبقة حصرًا من المجموعتين اللتين تكتب فيهما خدمة الإغلاق
// التلقائي (WorkdayAutoCloseService) والسجلات اليدوية المكافئة:
//
//   daily_logs: { repCode, startTime, endTime, status }
//     - status: 'open' | 'closed' (القيمتان الوحيدتان اللتان تكتبان فعليًا:
//       'open' عند بدء اليوم، 'closed' عند الإنهاء اليدوي أو التلقائي).
//     - closedBy: 'rep' | 'auto' (اختياري — السجلات القديمة قد تفتقده،
//       فلا يُشترط في العد).
//     - endTime: تُكتب بـ serverTimestamp عند الإغلاق فقط (يدوي/تلقائي).
//       اليوم المفتوح أو غير المكتمل (بلا endTime) لا يُحتسب مغلقًا أبدًا.
//     - حقول الجدولة autoClose* (nextCheckAt/basisMs/lastDecision/...) استشارية
//       ولا تدخل في أي مؤشر.
//   visits: { repCode, startTime, endTime, status }
//     - status النهائية اليدوية: 'sold' | 'followup' | 'busy' | 'rejected'.
//     - الإغلاق التلقائي يكتب status='auto_closed' + autoClosed=true.
//     - 'in_progress' تعني زيارة مفتوحة — تُستبعد من كل مؤشرات الأداء
//       (لا تُعد ولا تدخل في المدد).
//     - workdayId/autoCloseReason/autoClosedAt اختيارية (قد تغيب في القديم).
//
// القواعد (تُفرض هنا لا في الشاشات):
// - نطاق التاريخ: [startInclusive, endExclusive) على startTime فقط.
//   اليوم/الزيارة يُنسب إلى تاريخ بدئه (startTime)، حتى لو امتد الإغلاق
//   إلى اليوم التالي — بلا تكرار (كل مستند يُحتسب مرة واحدة بمعرفه).
// - اليوم المغلق: status == 'closed' + startTime/endTime صالحان + end >= start.
//   أي شيء آخر (open، بلا endTime، end قبل start) يُحصى كـ open/incomplete
//   للشفافية ولا يدخل في المدد ولا في عدد الأيام المغلقة.
// - الزيارة المحتسبة: status موجود وغير 'in_progress' + startTime صالح.
//   المدة تُحسب فقط عند توفر endTime صالح و end >= start؛ الزيارة المحتسبة
//   بلا مدة صالحة تدخل في العدد ولا تدخل في مجموع المدد (تُحصى في
//   visitsWithoutDuration للشفافية بدل اختراع قيم).
// - عدم افتراض حقول: غياب closedBy/workdayId/autoClosed لا يمنع العد،
//   وغياب endTime لا يُقدَّر بصفر مدة مضللة بل يُستبعد من المدد مع توثيقه.
// - لا Backfill ولا كتابة إطلاقًا: كل الواجهات هنا قراءة فقط.
library;

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'client_counts.dart';
import 'firestore_helpers.dart';

/// الحالات النصية كما تكتب فعليًا (يدوي + تلقائي).
const String kDayStatusOpen = 'open';
const String kDayStatusClosed = 'closed';
const String kVisitStatusInProgress = 'in_progress';

/// ملخص فترة واحدة (مندوب أو فريق) من السجلات التاريخية.
class WorkdayHistorySummary {
  /// عدد أيام العمل المغلقة فعليًا في النطاق.
  final int workdays;

  /// عدد الزيارات المحتسبة (مغلقة بتاريخ البدء داخل النطاق).
  final int visits;

  /// مجموع مدد أيام العمل المغلقة بالدقائق.
  final double workMinutes;

  /// مجموع مدد الزيارات المحتسبة ذات المدة الصالحة بالدقائق.
  final double visitMinutes;

  /// أيام مفتوحة/غير مكتملة داخل النطاق (للشفافية — مستبعدة من كل المدد).
  final int openDays;

  /// زيارات مفتوحة داخل النطاق (مستبعدة من العدد والمدد).
  final int openVisits;

  /// زيارات محتسبة لكن بلا مدة صالحة (داخلة في العدد، خارج المدد).
  final int visitsWithoutDuration;

  const WorkdayHistorySummary({
    this.workdays = 0,
    this.visits = 0,
    this.workMinutes = 0,
    this.visitMinutes = 0,
    this.openDays = 0,
    this.openVisits = 0,
    this.visitsWithoutDuration = 0,
  });

  double get workHours => workMinutes / 60.0;
  double get visitHours => visitMinutes / 60.0;

  /// متوسط ساعات العمل لكل يوم مغلق (0 عند غياب أيام مغلقة).
  double get avgWorkHoursPerDay => workdays <= 0 ? 0 : workHours / workdays;

  /// متوسط الزيارات لكل يوم مغلق (0 عند غياب أيام مغلقة).
  double get avgVisitsPerDay => workdays <= 0 ? 0 : visits / workdays;

  /// متوسط مدة الزيارة بالدقائق (فقط الزيارات ذات المدة الصالحة).
  double get avgVisitMinutes {
    final withDur = visits - visitsWithoutDuration;
    if (withDur <= 0) return 0;
    return visitMinutes / withDur;
  }

  WorkdayHistorySummary operator +(WorkdayHistorySummary other) =>
      WorkdayHistorySummary(
        workdays: workdays + other.workdays,
        visits: visits + other.visits,
        workMinutes: workMinutes + other.workMinutes,
        visitMinutes: visitMinutes + other.visitMinutes,
        openDays: openDays + other.openDays,
        openVisits: openVisits + other.openVisits,
        visitsWithoutDuration:
            visitsWithoutDuration + other.visitsWithoutDuration,
      );
}

/// هل يمثل [data] يوم عمل مغلقًا فعليًا؟ (status + طابعان صالحان + end>=start).
/// لا يشترط closedBy (السجلات القديمة قد تفتقده).
bool isClosedDay(Map<String, dynamic>? data) {
  if (data == null) return false;
  if (data['status'] != kDayStatusClosed) return false;
  final start = data['startTime'];
  final end = data['endTime'];
  if (start is! Timestamp || end is! Timestamp) return false;
  return !end.toDate().isBefore(start.toDate());
}

/// مدة اليوم بالدقائق، أو null عندما لا يكون مغلقًا فعليًا.
double? closedDayMinutes(Map<String, dynamic>? data) {
  if (!isClosedDay(data)) return null;
  final start = (data!['startTime'] as Timestamp).toDate();
  final end = (data['endTime'] as Timestamp).toDate();
  return end.difference(start).inMinutes.toDouble();
}

/// هل تُحتسب الزيارة؟ (حالة نهائية + startTime صالح).
/// 'in_progress' وغياب status/gStart يستبعدان الزيارة من العدد والمدد.
bool isCountedVisit(Map<String, dynamic>? data) {
  if (data == null) return false;
  final status = data['status']?.toString() ?? '';
  if (status.isEmpty || status == kVisitStatusInProgress) return false;
  return data['startTime'] is Timestamp;
}

/// مدة الزيارة بالدقائق، أو null عند غياب endTime صالح أو end قبل start.
/// (الزيارة المحتسبة بلا مدة تدخل في العدد فقط — بلا تقدير مضلل).
double? countedVisitMinutes(Map<String, dynamic>? data) {
  if (!isCountedVisit(data)) return null;
  final start = (data!['startTime'] as Timestamp).toDate();
  final end = data['endTime'];
  if (end is! Timestamp) return null;
  final endDate = end.toDate();
  if (endDate.isBefore(start)) return null;
  return endDate.difference(start).inMinutes.toDouble();
}

/// يلخص مستندات daily_logs (تُمرَّر مع معرفاتها لمنع التكرار خارجيًا).
/// المستندات خارج النطاق تُستبعد من الاستدعاء نفسه — هذه الدالة لا تُرشح
/// بالتاريخ (الترشيح على startTime في الاستعلام)، بل تصنف مغلق/مفتوح فقط.
WorkdayHistorySummary summarizeDayDocs(
    Iterable<Map<String, dynamic>> docs) {
  var closed = 0;
  var open = 0;
  var minutes = 0.0;
  for (final d in docs) {
    final m = closedDayMinutes(d);
    if (m == null) {
      open++;
    } else {
      closed++;
      minutes += m;
    }
  }
  return WorkdayHistorySummary(
    workdays: closed,
    workMinutes: minutes,
    openDays: open,
  );
}

/// يلخص مستندات visits (المفتوحة مستبعدة، وبلا مدة تُحصى في حقلها الشفاف).
WorkdayHistorySummary summarizeVisitDocs(
    Iterable<Map<String, dynamic>> docs) {
  var counted = 0;
  var open = 0;
  var noDur = 0;
  var minutes = 0.0;
  for (final d in docs) {
    final status = d['status']?.toString() ?? '';
    if (d['startTime'] is! Timestamp) continue;
    if (status.isEmpty || status == kVisitStatusInProgress) {
      open++;
      continue;
    }
    counted++;
    final m = countedVisitMinutes(d);
    if (m == null) {
      noDur++;
    } else {
      minutes += m;
    }
  }
  return WorkdayHistorySummary(
    visits: counted,
    visitMinutes: minutes,
    openVisits: open,
    visitsWithoutDuration: noDur,
  );
}

// ---------------------------------------------------------------------------
// ---------------------------------------------------------------------------
// قراءة إجماليات الدالة الخلفية working_hours_performance.
// الدالة تكتب على مستند salesRep (وليس daily_logs):
//   workingHoursByMonth.<YYYY-MM>.totalSeconds (عدد صحيح بالثواني)
//   workingHoursByMonth.<YYYY-MM>.sessions (عدد الجلسات المغلقة المحتسبة)
//   workingHoursByMonth.<YYYY-MM>.days.<YYYY-MM-DD> (ثواني اليوم)
// الواجهة تعرض هذه الحقول مباشرة (ثواني/3600 للساعات) ولا تعيد التجميع.
// الغائب أو غير الرقمي يُقرأ صفرًا — بلا افتراضات وبلا رمي.
// ---------------------------------------------------------------------------

/// إجمالي ثواني العمل المخزنة لمندوب واحد عن شهر `YYYY-MM`.
int repWorkSecondsForMonth(Map<String, dynamic>? data, String monthKey) {
  final wh = data?['workingHoursByMonth'];
  if (wh is! Map) return 0;
  final m = wh[monthKey];
  if (m is! Map) return 0;
  final t = m['totalSeconds'];
  return t is num ? t.toInt() : 0;
}

/// عدد الجلسات (أيام العمل المغلقة المحتسبة) المخزن لمندوب واحد عن شهر ما.
int repWorkSessionsForMonth(Map<String, dynamic>? data, String monthKey) {
  final wh = data?['workingHoursByMonth'];
  if (wh is! Map) return 0;
  final m = wh[monthKey];
  if (m is! Map) return 0;
  final s = m['sessions'];
  return s is num ? s.toInt() : 0;
}

/// مجموع الثواني عبر مندوبين مميزين (خريطة code -> doc، بلا تكرار).
int sumTeamWorkSecondsForMonth({
  required Map<String, Map<String, dynamic>> repDataByCode,
  required String monthKey,
}) {
  var total = 0;
  for (final data in repDataByCode.values) {
    total += repWorkSecondsForMonth(data, monthKey);
  }
  return total;
}

/// مجموع الجلسات عبر مندوبين مميزين (خريطة code -> doc، بلا تكرار).
int sumTeamWorkSessionsForMonth({
  required Map<String, Map<String, dynamic>> repDataByCode,
  required String monthKey,
}) {
  var total = 0;
  for (final data in repDataByCode.values) {
    total += repWorkSessionsForMonth(data, monthKey);
  }
  return total;
}

// ---------------------------------------------------------------------------
// توافق المفاتيح الشهرية (Cairo YYYY-MM / YYYY-MM-DD) فوق السجلات التاريخية.
// نفس توقيع عدّادات الأداء السابقة (repCode/supervisorDocId/managerDocId +
// monthKey) حتى تتبدل الشاشات بسطر واحد، لكن القراءة من daily_logs +
// visits (السجلات التاريخية التي تكتبها دالة الإغلاق) لا من عدّادات salesRep.
// المفتاح غير الصالح يُقرأ كصفر بلا رمي.
// ---------------------------------------------------------------------------

/// نطاق [startInclusive, endExclusive) لمفتاح شهري `YYYY-MM`.
({DateTime start, DateTime end})? monthKeyToRange(String monthKey) {
  final m =
      RegExp(r'^(\d{4})-(0[1-9]|1[0-2])$').firstMatch(monthKey.trim());
  if (m == null) return null;
  final y = int.parse(m.group(1)!);
  final mo = int.parse(m.group(2)!);
  return (start: DateTime(y, mo, 1), end: DateTime(y, mo + 1, 1));
}

/// نطاق يوم واحد لمفتاح `YYYY-MM-DD`.
({DateTime start, DateTime end})? dayKeyToRange(String dayKey) {
  final m = RegExp(r'^(\d{4})-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$')
      .firstMatch(dayKey.trim());
  if (m == null) return null;
  final d = DateTime(
      int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
  if (d.month != int.parse(m.group(2)!)) return null;
  return (start: d, end: d.add(const Duration(days: 1)));
}

/// زيارات الشهر لمندوب واحد من السجلات التاريخية (الحالات النهائية فقط).
Stream<int> watchRepVisitMonthTotalHist({
  required FirebaseFirestore db,
  required String repCode,
  required String monthKey,
}) {
  final range = monthKeyToRange(monthKey);
  if (range == null) return Stream.value(0);
  return watchRepWorkdaySummary(
    db: db,
    repCode: repCode,
    startInclusive: range.start,
    endExclusive: range.end,
  ).map((s) => s.visits);
}

/// زيارات يوم واحد لمندوب واحد من السجلات التاريخية.
Stream<int> watchRepVisitDayTotalHist({
  required FirebaseFirestore db,
  required String repCode,
  required String monthKey,
  required String dayKey,
}) {
  final range = dayKeyToRange(dayKey);
  if (range == null) return Stream.value(0);
  return watchRepWorkdaySummary(
    db: db,
    repCode: repCode,
    startInclusive: range.start,
    endExclusive: range.end,
  ).map((s) => s.visits);
}

/// زيارات الشهر لفريق من السجلات التاريخية (دفعات ≤10، منع تكرار).
Stream<int> watchTeamVisitMonthTotalHist({
  required FirebaseFirestore db,
  required List<String> repCodes,
  required String monthKey,
}) {
  final range = monthKeyToRange(monthKey);
  if (range == null) return Stream.value(0);
  return watchTeamWorkdaySummary(
    db: db,
    repCodes: repCodes,
    startInclusive: range.start,
    endExclusive: range.end,
  ).map((s) => s.visits);
}

/// زيارات الشهر لفريق مشرف واحد من السجلات التاريخية.
Stream<int> watchSupervisorVisitMonthTotalHist({
  required FirebaseFirestore db,
  required String supervisorDocId,
  required String monthKey,
}) {
  final range = monthKeyToRange(monthKey);
  if (range == null) return Stream.value(0);
  return watchSupervisorWorkdaySummary(
    db: db,
    supervisorDocId: supervisorDocId,
    startInclusive: range.start,
    endExclusive: range.end,
  ).map((s) => s.visits);
}

/// زيارات الشهر لهرم مدير كامل من السجلات التاريخية.
Stream<int> watchManagerVisitMonthTotalHist({
  required FirebaseFirestore db,
  required String managerDocId,
  required String monthKey,
}) {
  final range = monthKeyToRange(monthKey);
  if (range == null) return Stream.value(0);
  return watchManagerWorkdaySummary(
    db: db,
    managerDocId: managerDocId,
    startInclusive: range.start,
    endExclusive: range.end,
  ).map((s) => s.visits);
}

WorkdayHistorySummary combineDayAndVisitSummaries(
  WorkdayHistorySummary days,
  WorkdayHistorySummary visits,
) =>
    WorkdayHistorySummary(
      workdays: days.workdays,
      visits: visits.visits,
      workMinutes: days.workMinutes,
      visitMinutes: visits.visitMinutes,
      openDays: days.openDays,
      openVisits: visits.openVisits,
      visitsWithoutDuration: visits.visitsWithoutDuration,
    );

// ---------------------------------------------------------------------------
// Firestore reads (قراءة فقط — بلا أي كتابة).
// النطاق: [startInclusive, endExclusive) على startTime (تاريخ بدء المستند).
// ---------------------------------------------------------------------------

/// جلب لمرة واحدة لمندوب واحد من السجلات التاريخية.
Future<WorkdayHistorySummary> fetchRepWorkdaySummary({
  required FirebaseFirestore db,
  required String repCode,
  required DateTime startInclusive,
  required DateTime endExclusive,
}) async {
  final code = repCode.trim();
  if (code.isEmpty) return const WorkdayHistorySummary();
  final daySnap = await db
      .collection('daily_logs')
      .where('repCode', isEqualTo: code)
      .where('startTime',
          isGreaterThanOrEqualTo: Timestamp.fromDate(startInclusive))
      .where('startTime', isLessThan: Timestamp.fromDate(endExclusive))
      .get();
  final visitSnap = await db
      .collection('visits')
      .where('repCode', isEqualTo: code)
      .where('startTime',
          isGreaterThanOrEqualTo: Timestamp.fromDate(startInclusive))
      .where('startTime', isLessThan: Timestamp.fromDate(endExclusive))
      .get();
  // معرفات المستندات فريدة بطبيعتها — لا تكرار داخل الاستعلام الواحد.
  final days = summarizeDayDocs(daySnap.docs.map((d) => d.data()));
  final visits = summarizeVisitDocs(visitSnap.docs.map((d) => d.data()));
  return combineDayAndVisitSummaries(days, visits);
}

/// جلب لمرة واحدة لفريق (أكواد مميزة، دفعات ≤10، منع تكرار بمعرف المستند).
Future<WorkdayHistorySummary> fetchTeamWorkdaySummary({
  required FirebaseFirestore db,
  required List<String> repCodes,
  required DateTime startInclusive,
  required DateTime endExclusive,
}) async {
  final codes = distinctRepCodes(repCodes);
  if (codes.isEmpty) return const WorkdayHistorySummary();
  var out = const WorkdayHistorySummary();
  for (final chunk in chunkList(codes, 10)) {
    final daySnap = await db
        .collection('daily_logs')
        .where('repCode', whereIn: chunk)
        .where('startTime',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startInclusive))
        .where('startTime', isLessThan: Timestamp.fromDate(endExclusive))
        .get();
    final visitSnap = await db
        .collection('visits')
        .where('repCode', whereIn: chunk)
        .where('startTime',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startInclusive))
        .where('startTime', isLessThan: Timestamp.fromDate(endExclusive))
        .get();
    // منع تكرار احتساب المستند عبر الدفعات (الحماية عند تداخل الدفعات).
    final seenDays = <String>{};
    final dayMaps = <Map<String, dynamic>>[];
    for (final d in daySnap.docs) {
      if (seenDays.add(d.id)) dayMaps.add(d.data());
    }
    final seenVisits = <String>{};
    final visitMaps = <Map<String, dynamic>>[];
    for (final d in visitSnap.docs) {
      if (seenVisits.add(d.id)) visitMaps.add(d.data());
    }
    out = out +
        combineDayAndVisitSummaries(
          summarizeDayDocs(dayMaps),
          summarizeVisitDocs(visitMaps),
        );
  }
  return out;
}

/// جلب الزيارات فقط لمرة واحدة لفريق (بطاقة مدة الزيارات).
/// لا يقرأ `daily_logs` إطلاقًا — خاص بمدد الزيارات وعددها.
Future<WorkdayHistorySummary> fetchTeamVisitSummary({
  required FirebaseFirestore db,
  required List<String> repCodes,
  required DateTime startInclusive,
  required DateTime endExclusive,
}) async {
  final codes = distinctRepCodes(repCodes);
  if (codes.isEmpty) return const WorkdayHistorySummary();
  var out = const WorkdayHistorySummary();
  for (final chunk in chunkList(codes, 10)) {
    final visitSnap = await db
        .collection('visits')
        .where('repCode', whereIn: chunk)
        .where('startTime',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startInclusive))
        .where('startTime', isLessThan: Timestamp.fromDate(endExclusive))
        .get();
    final seenVisits = <String>{};
    final visitMaps = <Map<String, dynamic>>[];
    for (final d in visitSnap.docs) {
      if (seenVisits.add(d.id)) visitMaps.add(d.data());
    }
    out = out + summarizeVisitDocs(visitMaps);
  }
  return out;
}

/// بث حي لمندوب واحد (نفس قواعد الجلب لمرة واحدة).
Stream<WorkdayHistorySummary> watchRepWorkdaySummary({
  required FirebaseFirestore db,
  required String repCode,
  required DateTime startInclusive,
  required DateTime endExclusive,
}) {
  final code = repCode.trim();
  if (code.isEmpty) {
    return Stream.value(const WorkdayHistorySummary());
  }
  final dayStream = db
      .collection('daily_logs')
      .where('repCode', isEqualTo: code)
      .where('startTime',
          isGreaterThanOrEqualTo: Timestamp.fromDate(startInclusive))
      .where('startTime', isLessThan: Timestamp.fromDate(endExclusive))
      .snapshots();
  final visitStream = db
      .collection('visits')
      .where('repCode', isEqualTo: code)
      .where('startTime',
          isGreaterThanOrEqualTo: Timestamp.fromDate(startInclusive))
      .where('startTime', isLessThan: Timestamp.fromDate(endExclusive))
      .snapshots();
  late final StreamController<WorkdayHistorySummary> controller;
  StreamSubscription? daySub;
  StreamSubscription? visitSub;
  List<Map<String, dynamic>> latestDays = const [];
  List<Map<String, dynamic>> latestVisits = const [];
  void emit() {
    if (controller.isClosed) return;
    controller.add(combineDayAndVisitSummaries(
      summarizeDayDocs(latestDays),
      summarizeVisitDocs(latestVisits),
    ));
  }

  controller = StreamController<WorkdayHistorySummary>(
    onListen: () {
      daySub = dayStream.listen((s) {
        latestDays = s.docs.map((d) => d.data()).toList();
        emit();
      }, onError: controller.addError);
      visitSub = visitStream.listen((s) {
        latestVisits = s.docs.map((d) => d.data()).toList();
        emit();
      }, onError: controller.addError);
    },
    onCancel: () async {
      await daySub?.cancel();
      await visitSub?.cancel();
    },
  );
  return controller.stream;
}

/// بث حي لفريق (دفعات ≤10 عبر watchChunkedSnapshots — بلا اقتطاع).
Stream<WorkdayHistorySummary> watchTeamWorkdaySummary({
  required FirebaseFirestore db,
  required List<String> repCodes,
  required DateTime startInclusive,
  required DateTime endExclusive,
}) {
  final codes = distinctRepCodes(repCodes);
  if (codes.isEmpty) {
    return Stream.value(const WorkdayHistorySummary());
  }
  final dayStream = watchChunkedSnapshots(
    values: codes,
    queryChunk: (chunk) => db
        .collection('daily_logs')
        .where('repCode', whereIn: chunk)
        .where('startTime',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startInclusive))
        .where('startTime', isLessThan: Timestamp.fromDate(endExclusive)),
  );
  final visitStream = watchChunkedSnapshots(
    values: codes,
    queryChunk: (chunk) => db
        .collection('visits')
        .where('repCode', whereIn: chunk)
        .where('startTime',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startInclusive))
        .where('startTime', isLessThan: Timestamp.fromDate(endExclusive)),
  );
  late final StreamController<WorkdayHistorySummary> controller;
  StreamSubscription? daySub;
  StreamSubscription? visitSub;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> latestDays = const [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> latestVisits = const [];
  void emit() {
    if (controller.isClosed) return;
    final seenDays = <String>{};
    final dayMaps = <Map<String, dynamic>>[];
    for (final d in latestDays) {
      if (seenDays.add(d.id)) dayMaps.add(d.data());
    }
    final seenVisits = <String>{};
    final visitMaps = <Map<String, dynamic>>[];
    for (final d in latestVisits) {
      if (seenVisits.add(d.id)) visitMaps.add(d.data());
    }
    controller.add(combineDayAndVisitSummaries(
      summarizeDayDocs(dayMaps),
      summarizeVisitDocs(visitMaps),
    ));
  }

  controller = StreamController<WorkdayHistorySummary>(
    onListen: () {
      daySub = dayStream.listen((docs) {
        latestDays = docs;
        emit();
      }, onError: controller.addError);
      visitSub = visitStream.listen((docs) {
        latestVisits = docs;
        emit();
      }, onError: controller.addError);
    },
    onCancel: () async {
      await daySub?.cancel();
      await visitSub?.cancel();
    },
  );
  return controller.stream;
}

/// بث حي لفريق مشرف واحد (نفس قاعدة الأهلية: freelance مستبعد).
Stream<WorkdayHistorySummary> watchSupervisorWorkdaySummary({
  required FirebaseFirestore db,
  required String supervisorDocId,
  required DateTime startInclusive,
  required DateTime endExclusive,
}) {
  if (supervisorDocId.isEmpty) {
    return Stream.value(const WorkdayHistorySummary());
  }
  late final StreamController<WorkdayHistorySummary> controller;
  StreamSubscription<List<String>>? codesSub;
  StreamSubscription<WorkdayHistorySummary>? totalSub;
  controller = StreamController<WorkdayHistorySummary>(
    onListen: () {
      codesSub = watchSupervisorRepCodes(
        db: db,
        supervisorDocId: supervisorDocId,
      ).listen((codes) async {
        await totalSub?.cancel();
        if (controller.isClosed) return;
        if (codes.isEmpty) {
          controller.add(const WorkdayHistorySummary());
          return;
        }
        totalSub = watchTeamWorkdaySummary(
          db: db,
          repCodes: codes,
          startInclusive: startInclusive,
          endExclusive: endExclusive,
        ).listen(controller.add, onError: controller.addError);
      }, onError: controller.addError);
    },
    onCancel: () async {
      await codesSub?.cancel();
      await totalSub?.cancel();
    },
  );
  return controller.stream;
}

/// بث حي لهرم مدير كامل.
Stream<WorkdayHistorySummary> watchManagerWorkdaySummary({
  required FirebaseFirestore db,
  required String managerDocId,
  required DateTime startInclusive,
  required DateTime endExclusive,
}) {
  if (managerDocId.isEmpty) {
    return Stream.value(const WorkdayHistorySummary());
  }
  late final StreamController<WorkdayHistorySummary> controller;
  StreamSubscription<List<String>>? codesSub;
  StreamSubscription<WorkdayHistorySummary>? totalSub;
  controller = StreamController<WorkdayHistorySummary>(
    onListen: () {
      codesSub = watchManagerRepCodes(
        db: db,
        managerDocId: managerDocId,
      ).listen((codes) async {
        await totalSub?.cancel();
        if (controller.isClosed) return;
        if (codes.isEmpty) {
          controller.add(const WorkdayHistorySummary());
          return;
        }
        totalSub = watchTeamWorkdaySummary(
          db: db,
          repCodes: codes,
          startInclusive: startInclusive,
          endExclusive: endExclusive,
        ).listen(controller.add, onError: controller.addError);
      }, onError: controller.addError);
    },
    onCancel: () async {
      await codesSub?.cancel();
      await totalSub?.cancel();
    },
  );
  return controller.stream;
}
