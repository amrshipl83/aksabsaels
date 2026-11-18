// Single Source of Truth reader for order performance counters (aksabsaels).
//
// The ONLY source for order/sales actuals is the NESTED backend schema
// written by cashback/orders_performance_counter (counter.js `bucketPaths`,
// count.js transaction):
//
//   salesRep/{documentId}.ordersByMonth.{YYYY-MM}.new.{total, days.{YYYY-MM-DD}}
//   salesRep/{documentId}.ordersByMonth.{YYYY-MM}.delivered.{total, days.{day},
//     value, valueByDay.{day}}
//   salesRep/{documentId}.ordersByMonth.{YYYY-MM}.cancelled.{total, days.{day}}
//
// Verified 2026-11-19 against the Function Island sources above. There is NO
// flat `total` / `new` / `deliveredValue` field on the month level — readers
// here derive them: total = new.total + delivered.total + cancelled.total,
// deliveredValue = delivered.value.
//
// Month/day keys use Africa/Cairo wall-clock (see [cairoNow] in
// client_counts.dart). A missing month reads as 0, never as a recomputation
// from the `orders` collection.
//
// Backend status contract (exactly three tracked buckets):
// - 'new-order' and 'new' -> counted in the `new` bucket.
// - 'delivered' is the only bucket carrying money (`value`, `valueByDay`).
// - 'cancelled' counts documents, never money.
// - 'shipped', 'processing' and anything else are untracked: they never
//   enter any counter (a later move into a tracked bucket is counted then;
//   a move out reverses the old bucket).
//
// Rules enforced here (not in screens):
// - one value per repCode: duplicate salesRep docs sharing a repCode hold
//   the SAME counter, so exactly one doc per repCode is read (first wins);
// - teams sum across DISTINCT repCodes only;
// - hierarchy uses the real relations (supervisorId / managerId document
//   ids); repCode is never treated as a document id;
// - no `orders` collection reads for totals; detail screens keep their own
//   document queries for line items only;
// - whereIn fan-out is chunked (10 per query), never truncated;
// - every watch* API below is a live Firestore snapshots() stream.
// - current-month display uses the Cairo month key; an absent month reads
//   as 0 with a natural empty state.
//
// Pure helpers below the stream section stay unit-testable with no
// Firestore dependency beyond types.
library;

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'client_counts.dart';

/// One month (or day, or all-time rollup) of order performance for a single
/// rep or a team sum. `total` is derived (new + delivered + cancelled);
/// `deliveredValue` mirrors backend `delivered.value`.
class OrderMonthSummary {
  final int total;
  final int fresh;
  final int delivered;
  final int cancelled;
  final double deliveredValue;

  const OrderMonthSummary({
    this.total = 0,
    this.fresh = 0,
    this.delivered = 0,
    this.cancelled = 0,
    this.deliveredValue = 0,
  });

  /// Average delivered order value, guarded against division by zero.
  double get avgDelivered =>
      delivered <= 0 ? 0 : deliveredValue / delivered;

  OrderMonthSummary operator +(OrderMonthSummary other) => OrderMonthSummary(
        total: total + other.total,
        fresh: fresh + other.fresh,
        delivered: delivered + other.delivered,
        cancelled: cancelled + other.cancelled,
        deliveredValue: deliveredValue + other.deliveredValue,
      );

  @override
  bool operator ==(Object other) =>
      other is OrderMonthSummary &&
      total == other.total &&
      fresh == other.fresh &&
      delivered == other.delivered &&
      cancelled == other.cancelled &&
      deliveredValue == other.deliveredValue;

  @override
  int get hashCode =>
      Object.hash(total, fresh, delivered, cancelled, deliveredValue);
}

/// Backend bucket contract (cashback/orders_performance_counter/counter.js
/// `normalizeStatus`): raw 'new-order'/'new' -> 'new'; anything else besides
/// 'delivered'/'cancelled' (e.g. shipped, processing) is untracked -> null.
/// The backend applies this mapping; the frontend never maps raw statuses.
String? normalizeOrderStatus(dynamic raw) {
  final s = raw?.toString().trim() ?? '';
  if (s == 'new' || s == 'new-order') return 'new';
  if (s == 'delivered') return 'delivered';
  if (s == 'cancelled') return 'cancelled';
  return null;
}

/// Raw month map for [monthKey], or null when absent/malformed.
Map<String, dynamic>? _monthMap(Map<String, dynamic>? data, String monthKey) {
  final counts = data?['ordersByMonth'];
  if (counts is! Map) return null;
  final month = counts[monthKey];
  if (month is! Map) return null;
  return month.cast<String, dynamic>();
}

/// Raw bucket map (`new` / `delivered` / `cancelled`), or null when absent.
Map<String, dynamic>? _bucketMap(Map<String, dynamic>? month, String bucket) {
  final b = month?[bucket];
  if (b is! Map) return null;
  return b.cast<String, dynamic>();
}

int _asInt(dynamic raw) => raw is num ? raw.toInt() : 0;

double _asDouble(dynamic raw) => raw is num ? raw.toDouble() : 0;

/// Monthly summary for ONE salesRep doc from the NESTED backend buckets.
/// Missing maps, missing months and non-numeric fields read as 0
/// (no recomputation, no throw).
OrderMonthSummary repOrderMonthSummary(
    Map<String, dynamic>? data, String monthKey) {
  final month = _monthMap(data, monthKey);
  if (month == null) return const OrderMonthSummary();
  final fresh = _asInt(_bucketMap(month, 'new')?['total']);
  final delivered = _asInt(_bucketMap(month, 'delivered')?['total']);
  final cancelled = _asInt(_bucketMap(month, 'cancelled')?['total']);
  return OrderMonthSummary(
    total: fresh + delivered + cancelled,
    fresh: fresh,
    delivered: delivered,
    cancelled: cancelled,
    deliveredValue: _asDouble(_bucketMap(month, 'delivered')?['value']),
  );
}

/// Monthly order-document count for ONE salesRep doc
/// (new.total + delivered.total + cancelled.total).
int repOrderMonthTotal(Map<String, dynamic>? data, String monthKey) =>
    repOrderMonthSummary(data, monthKey).total;

/// Monthly delivered-only sales value for ONE salesRep doc
/// (backend `delivered.value`).
double repOrderMonthDeliveredValue(
        Map<String, dynamic>? data, String monthKey) =>
    repOrderMonthSummary(data, monthKey).deliveredValue;

/// One Cairo day's summary for ONE salesRep doc. Day counters live under
/// EACH bucket (`{bucket}.days.{dayKey}`); the day total is their sum.
/// Same fail-safe rules as [repOrderMonthSummary].
OrderMonthSummary repOrderDaySummary(
    Map<String, dynamic>? data, String monthKey, String dayKey) {
  final month = _monthMap(data, monthKey);
  if (month == null) return const OrderMonthSummary();
  int dayTotal(Map<String, dynamic>? bucket) {
    final days = bucket?['days'];
    if (days is! Map) return 0;
    return _asInt(days[dayKey]);
  }
  final newB = _bucketMap(month, 'new');
  final delB = _bucketMap(month, 'delivered');
  final canB = _bucketMap(month, 'cancelled');
  final fresh = dayTotal(newB);
  final delivered = dayTotal(delB);
  final cancelled = dayTotal(canB);
  return OrderMonthSummary(
    total: fresh + delivered + cancelled,
    fresh: fresh,
    delivered: delivered,
    cancelled: cancelled,
    deliveredValue: 0,
  );
}

/// One Cairo day's order-document count for ONE salesRep doc.
int repOrderDayTotal(
        Map<String, dynamic>? data, String monthKey, String dayKey) =>
    repOrderDaySummary(data, monthKey, dayKey).total;

/// True when [data] carries a usable numeric order counter for [monthKey]
/// (any tracked bucket total is numeric).
bool hasOrderMonthCounter(Map<String, dynamic>? data, String monthKey) {
  final month = _monthMap(data, monthKey);
  if (month == null) return false;
  return _bucketMap(month, 'new')?['total'] is num ||
      _bucketMap(month, 'delivered')?['total'] is num ||
      _bucketMap(month, 'cancelled')?['total'] is num;
}

/// Sums the monthly summary across DISTINCT repCodes (deduplicated map).
OrderMonthSummary sumTeamOrderMonthSummary({
  required Map<String, Map<String, dynamic>> repDataByCode,
  required String monthKey,
}) {
  var out = const OrderMonthSummary();
  for (final data in repDataByCode.values) {
    out = out + repOrderMonthSummary(data, monthKey);
  }
  return out;
}

/// All-time rollup for ONE salesRep doc: sums every month in
/// `ordersByMonth`. Still aggregate-only (one doc read, never `orders`).
OrderMonthSummary sumAllTimeOrderSummary(Map<String, dynamic>? data) {
  final counts = data?['ordersByMonth'];
  if (counts is! Map) return const OrderMonthSummary();
  var out = const OrderMonthSummary();
  for (final monthKey in counts.keys) {
    out = out + repOrderMonthSummary(data, monthKey.toString());
  }
  return out;
}

/// Daily delivered-only sales values keyed by day-of-month, for charts.
/// Reads backend `delivered.valueByDay` ({dayKey: value}); non-numeric
/// entries contribute 0 for their day (never throws, never falls back
/// to `orders`).
Map<int, double> orderDailyDeliveredValues(
    Map<String, dynamic>? data, String monthKey) {
  final month = _monthMap(data, monthKey);
  final byDay = _bucketMap(month, 'delivered')?['valueByDay'];
  if (byDay is! Map) return const {};
  final out = <int, double>{};
  for (final entry in byDay.entries) {
    final key = entry.key.toString();
    final dayNum = int.tryParse(key.length >= 10 ? key.substring(8, 10) : '');
    if (dayNum == null) continue;
    final v = entry.value;
    if (v is num) out[dayNum] = (out[dayNum] ?? 0) + v.toDouble();
  }
  return out;
}

// ---------------------------------------------------------------------------
// Live Firestore streams (read-only snapshots, never writes).
// ---------------------------------------------------------------------------

/// Live monthly order summary for ONE repCode (deduplicated doc).
Stream<OrderMonthSummary> watchRepOrderMonthSummary({
  required FirebaseFirestore db,
  required String repCode,
  required String monthKey,
}) {
  final code = repCode.trim();
  if (code.isEmpty) return Stream.value(const OrderMonthSummary());
  return db
      .collection('salesRep')
      .where('repCode', isEqualTo: code)
      .snapshots()
      .map((snap) {
    if (snap.docs.isEmpty) return const OrderMonthSummary();
    final byCode = dedupeRepDocsByCode(snap.docs.map((d) => d.data()));
    return repOrderMonthSummary(byCode[code], monthKey);
  });
}

/// Live one-day order summary for ONE repCode (Cairo [dayKey]).
Stream<OrderMonthSummary> watchRepOrderDaySummary({
  required FirebaseFirestore db,
  required String repCode,
  required String monthKey,
  required String dayKey,
}) {
  final code = repCode.trim();
  if (code.isEmpty) return Stream.value(const OrderMonthSummary());
  return db
      .collection('salesRep')
      .where('repCode', isEqualTo: code)
      .snapshots()
      .map((snap) {
    if (snap.docs.isEmpty) return const OrderMonthSummary();
    final byCode = dedupeRepDocsByCode(snap.docs.map((d) => d.data()));
    return repOrderDaySummary(byCode[code], monthKey, dayKey);
  });
}

/// Live monthly order summary for a team of repCodes (chunked, deduped).
Stream<OrderMonthSummary> watchTeamOrderMonthSummary({
  required FirebaseFirestore db,
  required List<String> repCodes,
  required String monthKey,
}) {
  final codes = distinctRepCodes(repCodes);
  if (codes.isEmpty) return Stream.value(const OrderMonthSummary());
  return watchChunkedSnapshots(
    values: codes,
    queryChunk: (chunk) =>
        db.collection('salesRep').where('repCode', whereIn: chunk),
  ).map((docs) {
    final byCode = dedupeRepDocsByCode(docs.map((d) => d.data()));
    return sumTeamOrderMonthSummary(
        repDataByCode: byCode, monthKey: monthKey);
  });
}

/// Live monthly order summary for one supervisor's whole team.
/// Supervisor's own visits/orders are never included: only reps whose
/// salesRep doc carries this supervisor's document id.
Stream<OrderMonthSummary> watchSupervisorOrderMonthSummary({
  required FirebaseFirestore db,
  required String supervisorDocId,
  required String monthKey,
}) {
  if (supervisorDocId.isEmpty) {
    return Stream.value(const OrderMonthSummary());
  }
  late final StreamController<OrderMonthSummary> controller;
  StreamSubscription<List<String>>? codesSub;
  StreamSubscription<OrderMonthSummary>? totalSub;
  controller = StreamController<OrderMonthSummary>(
    onListen: () {
      codesSub = watchSupervisorRepCodes(
        db: db,
        supervisorDocId: supervisorDocId,
      ).listen((codes) async {
        await totalSub?.cancel();
        if (controller.isClosed) return;
        if (codes.isEmpty) {
          controller.add(const OrderMonthSummary());
          return;
        }
        totalSub = watchTeamOrderMonthSummary(
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

/// Live monthly order summary for a whole manager hierarchy.
Stream<OrderMonthSummary> watchManagerOrderMonthSummary({
  required FirebaseFirestore db,
  required String managerDocId,
  required String monthKey,
}) {
  if (managerDocId.isEmpty) return Stream.value(const OrderMonthSummary());
  late final StreamController<OrderMonthSummary> controller;
  StreamSubscription<List<String>>? codesSub;
  StreamSubscription<OrderMonthSummary>? totalSub;
  controller = StreamController<OrderMonthSummary>(
    onListen: () {
      codesSub = watchManagerRepCodes(
        db: db,
        managerDocId: managerDocId,
      ).listen((codes) async {
        await totalSub?.cancel();
        if (controller.isClosed) return;
        if (codes.isEmpty) {
          controller.add(const OrderMonthSummary());
          return;
        }
        totalSub = watchTeamOrderMonthSummary(
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
