// Single Source of Truth reader for qualified client counters (aksabsaels).
//
// The ONLY source for the `clientsTarget` actual is:
//
//   salesRep/{documentId}.clientCounts.{YYYY-MM} = { total, days: {...} }
//
// Written by the backend on each qualified first login via `/mint`.
// Month/day keys use Africa/Cairo wall-clock (see [cairoNow]).
//
// Rules enforced here (not in screens):
// - one value per repCode: duplicate salesRep docs sharing a repCode hold
//   the SAME counter, so exactly one doc per repCode is read (first wins);
//   totals are NEVER summed across duplicate docs of one rep;
// - teams sum across DISTINCT repCodes only;
// - hierarchy uses the real relations (supervisorId / managerId document
//   ids); repCode is never treated as a document id;
// - no users/deliverySupermarkets fallback or recomputation;
// - whereIn fan-out is chunked (10 per query), never truncated;
// - every watch* API below is a live Firestore snapshots() stream.
//
// Pure helpers above the stream section stay unit-testable with no
// Firestore dependency beyond types.
library;

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'firestore_helpers.dart';

// ---------------------------------------------------------------------------
// Cairo wall-clock (pure, no extra dependency).
//
// Egypt observes DST from the last Friday of April (00:00 local standard)
// until the last Thursday of October (24:00 local DST), i.e. UTC+3 inside
// that window and UTC+2 otherwise.
// ---------------------------------------------------------------------------

/// Cairo local time for [nowUtc] (defaults to now). Never uses device locale.
DateTime cairoNow({DateTime? nowUtc}) {
  final utc = (nowUtc ?? DateTime.now()).toUtc();
  return utc.add(Duration(hours: _cairoOffsetHours(utc)));
}

int _cairoOffsetHours(DateTime utc) => _isCairoDst(utc) ? 3 : 2;

/// True inside the Egypt DST window containing [utc].
bool _isCairoDst(DateTime utc) {
  final y = utc.year;
  // DST start: last Friday of April 00:00 Cairo standard == 22:00 UTC Thu.
  final start =
      _lastWeekdayOfMonthUtc(y, 4, DateTime.friday).subtract(
        const Duration(hours: 2),
      );
  // DST end: last Thursday of October 24:00 Cairo DST == 21:00 UTC Thu.
  final end =
      _lastWeekdayOfMonthUtc(y, 10, DateTime.thursday).add(
        const Duration(hours: 21),
      );
  return !utc.isBefore(start) && utc.isBefore(end);
}

DateTime _lastWeekdayOfMonthUtc(int year, int month, int weekday) {
  var d = DateTime.utc(year, month + 1, 0);
  while (d.weekday != weekday) {
    d = d.subtract(const Duration(days: 1));
  }
  return DateTime.utc(d.year, d.month, d.day);
}

/// `YYYY-MM` counter key for the Cairo month containing [nowUtc].
String clientCountMonthKey({DateTime? nowUtc}) {
  final c = cairoNow(nowUtc: nowUtc);
  return '${c.year.toString().padLeft(4, '0')}-'
      '${c.month.toString().padLeft(2, '0')}';
}

/// `YYYY-MM-DD` detail key for the Cairo day containing [nowUtc].
String clientCountDayKey({DateTime? nowUtc}) {
  final c = cairoNow(nowUtc: nowUtc);
  return '${clientCountMonthKey(nowUtc: c.toUtc())}-'
      '${c.day.toString().padLeft(2, '0')}';
}

// ---------------------------------------------------------------------------
// Pure counter reads (no Firestore).
// ---------------------------------------------------------------------------

/// Monthly qualified total for ONE salesRep doc. Missing maps, missing
/// months, and non-numeric totals read as 0 (no recomputation, no throw).
int repMonthTotal(Map<String, dynamic>? data, String monthKey) {
  final counts = data?['clientCounts'];
  if (counts is! Map) return 0;
  final month = counts[monthKey];
  if (month is! Map) return 0;
  final total = month['total'];
  if (total is num) return total.toInt();
  return 0;
}

/// One Cairo day's qualified total for ONE salesRep doc. Same fail-safe
/// rules as [repMonthTotal].
int repDayTotal(
  Map<String, dynamic>? data,
  String monthKey,
  String dayKey,
) {
  final counts = data?['clientCounts'];
  if (counts is! Map) return 0;
  final month = counts[monthKey];
  if (month is! Map) return 0;
  final days = month['days'];
  if (days is! Map) return 0;
  final v = days[dayKey];
  if (v is num) return v.toInt();
  return 0;
}

/// True when [data] carries a usable numeric counter for [monthKey].
bool hasMonthCounter(Map<String, dynamic>? data, String monthKey) {
  final counts = data?['clientCounts'];
  if (counts is! Map) return false;
  final month = counts[monthKey];
  return month is Map && month['total'] is num;
}

/// Deduplicates raw salesRep docs by trimmed non-empty `repCode`.
/// FIRST doc wins per repCode (duplicates hold the same counter; they are
/// never summed). Docs without a repCode are dropped.
Map<String, Map<String, dynamic>> dedupeRepDocsByCode(
  Iterable<Map<String, dynamic>> docs,
) {
  final out = <String, Map<String, dynamic>>{};
  for (final doc in docs) {
    final code = doc['repCode']?.toString().trim() ?? '';
    if (code.isEmpty) continue;
    out.putIfAbsent(code, () => doc);
  }
  return out;
}

/// Sums the monthly counter across DISTINCT repCodes (deduplicated map).
int sumTeamMonthTotal({
  required Map<String, Map<String, dynamic>> repDataByCode,
  required String monthKey,
}) {
  var total = 0;
  for (final data in repDataByCode.values) {
    total += repMonthTotal(data, monthKey);
  }
  return total;
}

/// Sums one Cairo day's counter across DISTINCT repCodes.
int sumTeamDayTotal({
  required Map<String, Map<String, dynamic>> repDataByCode,
  required String monthKey,
  required String dayKey,
}) {
  var total = 0;
  for (final data in repDataByCode.values) {
    total += repDayTotal(data, monthKey, dayKey);
  }
  return total;
}

/// Distinct trimmed non-empty codes, order-preserving.
List<String> distinctRepCodes(Iterable<String?> codes) {
  final seen = <String>{};
  final out = <String>[];
  for (final raw in codes) {
    final code = raw?.trim() ?? '';
    if (code.isEmpty) continue;
    if (seen.add(code)) out.add(code);
  }
  return out;
}

// ---------------------------------------------------------------------------
// Live Firestore streams (read-only snapshots, never writes).
// ---------------------------------------------------------------------------

/// Live monthly qualified total for ONE repCode.
/// Reads the single deduplicated salesRep doc for [repCode]; duplicates
/// share the counter so only one doc is read. Emits 0 when absent.
Stream<int> watchRepMonthTotal({
  required FirebaseFirestore db,
  required String repCode,
  required String monthKey,
}) {
  final code = repCode.trim();
  if (code.isEmpty) return Stream.value(0);
  return db
      .collection('salesRep')
      .where('repCode', isEqualTo: code)
      .snapshots()
      .map((snap) {
        if (snap.docs.isEmpty) return 0;
        final byCode = dedupeRepDocsByCode(
          snap.docs.map((d) => d.data()),
        );
        final data = byCode[code];
        return repMonthTotal(data, monthKey);
      });
}

/// Live one-day qualified total for ONE repCode (Cairo [dayKey]).
Stream<int> watchRepDayTotal({
  required FirebaseFirestore db,
  required String repCode,
  required String monthKey,
  required String dayKey,
}) {
  final code = repCode.trim();
  if (code.isEmpty) return Stream.value(0);
  return db
      .collection('salesRep')
      .where('repCode', isEqualTo: code)
      .snapshots()
      .map((snap) {
        if (snap.docs.isEmpty) return 0;
        final byCode = dedupeRepDocsByCode(
          snap.docs.map((d) => d.data()),
        );
        return repDayTotal(byCode[code], monthKey, dayKey);
      });
}

/// Combines per-chunk snapshot streams into one live list.
/// [queryChunk] builds the query for one <=10 chunk. Never truncates.
Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
watchChunkedSnapshots({
  required List<String> values,
  required Query<Map<String, dynamic>> Function(List<String> chunk) queryChunk,
}) {
  final chunks = chunkList(distinctRepCodes(values), 10);
  if (chunks.isEmpty) {
    return Stream.value(const []);
  }
  if (chunks.length == 1) {
    return queryChunk(chunks.first).snapshots().map((s) => s.docs);
  }
  late final StreamController<
    List<QueryDocumentSnapshot<Map<String, dynamic>>>
  >
  controller;
  final latest =
      List<List<QueryDocumentSnapshot<Map<String, dynamic>>>>.generate(
        chunks.length,
        (_) => const [],
      );
  final subs = <StreamSubscription>[];
  controller = StreamController<
    List<QueryDocumentSnapshot<Map<String, dynamic>>>
  >(
    onListen: () {
      for (var i = 0; i < chunks.length; i++) {
        final idx = i;
        subs.add(
          queryChunk(chunks[idx]).snapshots().listen((snap) {
            latest[idx] = snap.docs;
            if (!controller.isClosed) {
              controller.add(latest.expand((d) => d).toList());
            }
          }, onError: controller.addError),
        );
      }
    },
    onCancel: () async {
      for (final s in subs) {
        await s.cancel();
      }
    },
  );
  return controller.stream;
}

/// Live monthly qualified total for a team of repCodes (chunked, deduped).
Stream<int> watchTeamMonthTotal({
  required FirebaseFirestore db,
  required List<String> repCodes,
  required String monthKey,
}) {
  final codes = distinctRepCodes(repCodes);
  if (codes.isEmpty) return Stream.value(0);
  return watchChunkedSnapshots(
    values: codes,
    queryChunk: (chunk) =>
        db.collection('salesRep').where('repCode', whereIn: chunk),
  ).map((docs) {
    final byCode = dedupeRepDocsByCode(docs.map((d) => d.data()));
    return sumTeamMonthTotal(repDataByCode: byCode, monthKey: monthKey);
  });
}

/// Live repCodes of one supervisor's team (same eligibility rule as the
/// lists: freelance excluded, legacy docs count as permanent).
Stream<List<String>> watchSupervisorRepCodes({
  required FirebaseFirestore db,
  required String supervisorDocId,
}) {
  if (supervisorDocId.isEmpty) return Stream.value(const []);
  return db
      .collection('salesRep')
      .where('supervisorId', isEqualTo: supervisorDocId)
      .snapshots()
      .map(
        (snap) => distinctRepCodes(
          snap.docs
              .where((d) => isTargetEligible(d.data()['repType']))
              .map((d) => d.data()['repCode']?.toString()),
        ),
      );
}

/// Live monthly qualified total for one supervisor's whole team.
Stream<int> watchSupervisorMonthTotal({
  required FirebaseFirestore db,
  required String supervisorDocId,
  required String monthKey,
}) {
  if (supervisorDocId.isEmpty) return Stream.value(0);
  late final StreamController<int> controller;
  StreamSubscription<List<String>>? codesSub;
  StreamSubscription<int>? totalSub;
  controller = StreamController<int>(
    onListen: () {
      codesSub = watchSupervisorRepCodes(
        db: db,
        supervisorDocId: supervisorDocId,
      ).listen((codes) async {
        await totalSub?.cancel();
        if (controller.isClosed) return;
        if (codes.isEmpty) {
          controller.add(0);
          return;
        }
        totalSub = watchTeamMonthTotal(
          db: db,
          repCodes: codes,
          monthKey: monthKey,
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

/// Live repCodes under one manager (supervisors by document id, then their
/// reps; same eligibility rule, chunked supervisor fan-out).
Stream<List<String>> watchManagerRepCodes({
  required FirebaseFirestore db,
  required String managerDocId,
}) {
  if (managerDocId.isEmpty) return Stream.value(const []);
  late final StreamController<List<String>> controller;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? supSub;
  StreamSubscription<List<QueryDocumentSnapshot<Map<String, dynamic>>>>?
  repsSub;
  controller = StreamController<List<String>>(
    onListen: () {
      supSub = db
          .collection('managers')
          .where('managerId', isEqualTo: managerDocId)
          .where('role', isEqualTo: 'sales_supervisor')
          .snapshots()
          .listen((supSnap) async {
            await repsSub?.cancel();
            if (controller.isClosed) return;
            final supIds = supSnap.docs.map((d) => d.id).toList();
            if (supIds.isEmpty) {
              controller.add(const []);
              return;
            }
            repsSub =
                watchChunkedSnapshots(
                  values: supIds,
                  queryChunk: (chunk) => db
                      .collection('salesRep')
                      .where('supervisorId', whereIn: chunk),
                ).listen((repDocs) {
                  if (controller.isClosed) return;
                  controller.add(
                    distinctRepCodes(
                      repDocs
                          .where(
                            (d) => isTargetEligible(d.data()['repType']),
                          )
                          .map((d) => d.data()['repCode']?.toString()),
                    ),
                  );
                }, onError: controller.addError);
          }, onError: controller.addError);
    },
    onCancel: () async {
      await supSub?.cancel();
      await repsSub?.cancel();
    },
  );
  return controller.stream;
}

/// Live monthly qualified total for a whole manager hierarchy.
Stream<int> watchManagerMonthTotal({
  required FirebaseFirestore db,
  required String managerDocId,
  required String monthKey,
}) {
  if (managerDocId.isEmpty) return Stream.value(0);
  late final StreamController<int> controller;
  StreamSubscription<List<String>>? codesSub;
  StreamSubscription<int>? totalSub;
  controller = StreamController<int>(
    onListen: () {
      codesSub = watchManagerRepCodes(
        db: db,
        managerDocId: managerDocId,
      ).listen((codes) async {
        await totalSub?.cancel();
        if (controller.isClosed) return;
        if (codes.isEmpty) {
          controller.add(0);
          return;
        }
        totalSub = watchTeamMonthTotal(
          db: db,
          repCodes: codes,
          monthKey: monthKey,
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

/// Live directory rows for a team of repCodes (chunked, no truncation).
/// Directory listing only — NOT the qualified counter.
Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
watchUsersByRepCodes({
  required FirebaseFirestore db,
  required List<String> repCodes,
}) {
  return watchChunkedSnapshots(
    values: repCodes,
    queryChunk: (chunk) =>
        db.collection('users').where('repCode', whereIn: chunk),
  );
}
