// Single Source of Truth reader for visit performance counters (aksabsaels).
//
// The ONLY source for visit actuals is:
//
//   salesRep/{documentId}.visitsByMonth.{YYYY-MM} = { total, days: {...} }
//
// Written by the visits_performance_counter backend on each visit creation
// (one transaction: counters + performanceCounted stamp). A visit counts at
// creation regardless of its later status; closing/cancelling never removes
// it. Month/day keys use Africa/Cairo wall-clock (see [cairoNow]).
//
// Rules enforced here (not in screens):
// - one value per repCode: duplicate salesRep docs sharing a repCode hold
//   the SAME counter, so exactly one doc per repCode is read (first wins);
//   totals are NEVER summed across duplicate docs of one rep;
// - teams sum across DISTINCT repCodes only;
// - hierarchy uses the real relations (supervisorId / managerId document
//   ids); repCode is never treated as a document id;
// - no `visits` collection reads for totals and no monthlySales fallback;
// - whereIn fan-out is chunked (10 per query), never truncated;
// - every watch* API below is a live Firestore snapshots() stream.
// - current-month display uses the Cairo month key; an absent month reads
//   as 0 with a natural empty state (never a visits recomputation).
//
// Pure helpers below the stream section stay unit-testable with no
// Firestore dependency beyond types.
library;

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'client_counts.dart';

// ---------------------------------------------------------------------------
// Pure counter reads (no Firestore).
// ---------------------------------------------------------------------------

/// Monthly visit total for ONE salesRep doc. Missing maps, missing months,
/// and non-numeric totals read as 0 (no recomputation, no throw).
int repVisitMonthTotal(Map<String, dynamic>? data, String monthKey) {
  final counts = data?['visitsByMonth'];
  if (counts is! Map) return 0;
  final month = counts[monthKey];
  if (month is! Map) return 0;
  final total = month['total'];
  if (total is num) return total.toInt();
  return 0;
}

/// One Cairo day's visit total for ONE salesRep doc. Same fail-safe rules
/// as [repVisitMonthTotal].
int repVisitDayTotal(
  Map<String, dynamic>? data,
  String monthKey,
  String dayKey,
) {
  final counts = data?['visitsByMonth'];
  if (counts is! Map) return 0;
  final month = counts[monthKey];
  if (month is! Map) return 0;
  final days = month['days'];
  if (days is! Map) return 0;
  final v = days[dayKey];
  if (v is num) return v.toInt();
  return 0;
}

/// True when [data] carries a usable numeric visit counter for [monthKey].
bool hasVisitMonthCounter(Map<String, dynamic>? data, String monthKey) {
  final counts = data?['visitsByMonth'];
  if (counts is! Map) return false;
  final month = counts[monthKey];
  return month is Map && month['total'] is num;
}

/// Sums the monthly visit counter across DISTINCT repCodes (deduplicated map).
int sumTeamVisitMonthTotal({
  required Map<String, Map<String, dynamic>> repDataByCode,
  required String monthKey,
}) {
  var total = 0;
  for (final data in repDataByCode.values) {
    total += repVisitMonthTotal(data, monthKey);
  }
  return total;
}

// ---------------------------------------------------------------------------
// Live Firestore streams (read-only snapshots, never writes).
// ---------------------------------------------------------------------------

/// Live monthly visit total for ONE repCode.
/// Reads the single deduplicated salesRep doc for [repCode]; duplicates
/// share the counter so only one doc is read. Emits 0 when absent.
Stream<int> watchRepVisitMonthTotal({
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
        return repVisitMonthTotal(data, monthKey);
      });
}

/// Live one-day visit total for ONE repCode (Cairo [dayKey]).
Stream<int> watchRepVisitDayTotal({
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
        return repVisitDayTotal(byCode[code], monthKey, dayKey);
      });
}

/// Live monthly visit total for a team of repCodes (chunked, deduped).
Stream<int> watchTeamVisitMonthTotal({
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
    return sumTeamVisitMonthTotal(repDataByCode: byCode, monthKey: monthKey);
  });
}

/// Live monthly visit total for one supervisor's whole team.
Stream<int> watchSupervisorVisitMonthTotal({
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
        totalSub = watchTeamVisitMonthTotal(
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

/// Live monthly visit total for a whole manager hierarchy.
Stream<int> watchManagerVisitMonthTotal({
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
        totalSub = watchTeamVisitMonthTotal(
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
