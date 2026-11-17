// First-login customer counting for rep goals (aksabsaels).
//
// A customer counts toward their rep's `clientsTarget` goal exactly once,
// when ALL of the following hold:
//   1. the `users` doc carries the rep's `repCode` (server-bound at
//      registration by `repBuyer`; self-registered buyers have none),
//   2. `firstLoginAt` is present (stamped once by backend `/mint` on the
//      first successful OTP login — never from `logAppEvent` or the local
//      queue), at or after the counting start below,
//   3. `createdAt` is at or after the counting start below (legacy accounts
//      created before the feature are never counted retroactively, even if
//      they log in after deploy and receive a `firstLoginAt` stamp).
//
// Everything below is pure (no Firestore imports) so it stays unit-testable.
library;

/// Start of goal counting (UTC). Only customers created AND first-logged-in
/// at/after this instant count.
///
/// DEPLOY GATE: production deploy must happen at/after this instant. It is
/// set to the start of the deploy day - the latest safe lower bound needing
/// no wall-clock precision. An earlier value stays safe; a later one would
///
/// wrongly exclude accounts created between it and the real deploy moment.
/// Legacy accounts (created before it) are excluded even if they log in later.
final DateTime kRepGoalCountStartUtc = DateTime.utc(2026, 11, 14);

/// Reads Firestore Timestamps, DateTimes, or epoch-millis numbers as UTC.
/// Returns null when the value is missing or unreadable (fail-closed: the
/// doc does not count).
DateTime? repGoalDateUtc(dynamic raw) {
  if (raw == null) return null;
  if (raw is DateTime) return raw.toUtc();
  if (raw is num) {
    return DateTime.fromMillisecondsSinceEpoch(raw.toInt(), isUtc: true);
  }
  try {
    final dynamic millis = (raw as dynamic).toMillis();
    if (millis is num) {
      return DateTime.fromMillisecondsSinceEpoch(millis.toInt(), isUtc: true);
    }
  } catch (_) {
    // No toMillis() — not a readable timestamp.
  }
  return null;
}

/// True when one `users` doc counts once toward [repCode]'s goal.
/// [goLive] defaults to [kRepGoalCountStartUtc] (injectable for tests).
bool repCustomerCountsTowardGoal({
  required Map<String, dynamic> data,
  required String repCode,
  DateTime? goLive,
}) {
  if (repCode.isEmpty) return false;
  if (data['repCode']?.toString() != repCode) return false;
  final start = (goLive ?? kRepGoalCountStartUtc).toUtc();
  final firstLogin = repGoalDateUtc(data['firstLoginAt']);
  if (firstLogin == null || firstLogin.isBefore(start)) return false;
  final created = repGoalDateUtc(data['createdAt']);
  if (created == null || created.isBefore(start)) return false;
  return true;
}

/// Counts distinct customers toward one rep's goal from raw `users` docs
/// keyed by doc id. Dedupe key is the `uid` field (falls back to doc id),
/// so one UID is never counted twice even if two docs reference it.
int countRepGoalCustomers({
  required Map<String, Map<String, dynamic>> docsById,
  required String repCode,
  DateTime? goLive,
}) {
  final seen = <String>{};
  var count = 0;
  docsById.forEach((docId, data) {
    final rawUid = data['uid']?.toString() ?? '';
    final key = rawUid.isNotEmpty ? rawUid : docId;
    if (!seen.add(key)) return;
    if (repCustomerCountsTowardGoal(data: data, repCode: repCode, goLive: goLive)) {
      count++;
    }
  });
  return count;
}

/// Team variant: counts distinct customers whose `repCode` is in [repCodes]
/// (supervisor view). Same once-per-UID and go-live rules as above.
int countRepGoalCustomersForTeam({
  required Map<String, Map<String, dynamic>> docsById,
  required Set<String> repCodes,
  DateTime? goLive,
}) {
  if (repCodes.isEmpty) return 0;
  final seen = <String>{};
  var count = 0;
  final start = (goLive ?? kRepGoalCountStartUtc).toUtc();
  bool counts(Map<String, dynamic> data) {
    if (!repCodes.contains(data['repCode']?.toString() ?? '')) return false;
    final firstLogin = repGoalDateUtc(data['firstLoginAt']);
    if (firstLogin == null || firstLogin.isBefore(start)) return false;
    final created = repGoalDateUtc(data['createdAt']);
    if (created == null || created.isBefore(start)) return false;
    return true;
  }

  docsById.forEach((docId, data) {
    final rawUid = data['uid']?.toString() ?? '';
    final key = rawUid.isNotEmpty ? rawUid : docId;
    if (!seen.add(key)) return;
    if (counts(data)) count++;
  });
  return count;
}

/// Sums the server-side `clientCounts[monthKey].total` counter across every
/// matching salesRep doc (robust to duplicate repCode docs: the backend
/// increments all of them, so the sum is the authoritative total).
/// Missing months, missing maps, and non-numeric totals contribute 0 —
/// callers fall back to the live computation when no counter exists at all.
int sumClientCountsTotal({
  required List<Map<String, dynamic>> repDocs,
  required String monthKey,
}) {
  var total = 0;
  for (final doc in repDocs) {
    final counts = doc['clientCounts'];
    if (counts is Map) {
      final month = counts[monthKey];
      if (month is Map) {
        final t = month['total'];
        if (t is num) total += t.toInt();
      }
    }
  }
  return total;
}

/// True when at least one rep doc carries a usable numeric
/// `clientCounts[monthKey].total` — i.e. the counter era has begun for
/// this rep/month. A month entry without a numeric total does not count.
bool hasClientCountsMonth({
  required List<Map<String, dynamic>> repDocs,
  required String monthKey,
}) {
  for (final doc in repDocs) {
    final counts = doc['clientCounts'];
    if (counts is Map) {
      final month = counts[monthKey];
      if (month is Map && month['total'] is num) return true;
    }
  }
  return false;
}
