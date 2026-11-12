// Hierarchical target distribution for sales managers (aksabsaels).
//
// Same entry shape as the admin panel (phase 1): a manager's monthly target
// lives on their own `managers` doc under `targets.<yyyy-MM>`, and each
// supervisor's share lives on the supervisor's own `managers` doc under the
// SAME month key — so the supervisor screen (phase 3) reads it with no
// rebuild. The five indicator names are identical on both sides:
//
// `financialTarget`, `hoursTarget`, `invoicesTarget`, `clientsTarget`,
// `visitsTarget`.
//
// Pure helpers below never touch Firestore (unit-testable with no plugins).
// The thin [distributeSupervisorTarget] wrapper performs the atomic
// read-modify-write via a Firestore transaction.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

/// The five monthly indicators, in canonical order (same as admin panel).
const List<String> kTargetFields = <String>[
  'financialTarget',
  'hoursTarget',
  'invoicesTarget',
  'clientsTarget',
  'visitsTarget',
];

/// Arabic labels for the five indicators.
const Map<String, String> kTargetLabelsAr = <String, String>{
  'financialTarget': 'الهدف المالي للمبيعات (ج.م)',
  'hoursTarget': 'ساعات العمل',
  'invoicesTarget': 'عدد الفواتير',
  'clientsTarget': 'عدد العملاء',
  'visitsTarget': 'عدد الزيارات',
};

/// Target entry states.
const String kTargetStatusAssigned = 'assigned';
const String kTargetStatusPartial = 'partially_distributed';
const String kTargetStatusFull = 'fully_distributed';

/// Builds a `yyyy-MM` month key (same format as the admin panel).
String targetMonthKey(DateTime date) => DateFormat('yyyy-MM').format(date);

/// True for strict `yyyy-MM` keys (01–12 only).
bool isValidTargetMonthKey(String raw) =>
    RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(raw.trim());

/// Normalizes one raw indicator value: numbers stay, numeric strings parse,
/// anything else (or a negative) becomes 0. Never throws.
double normalizeTargetValue(dynamic raw) {
  double value;
  if (raw is num) {
    value = raw.toDouble();
  } else {
    value = double.tryParse(raw?.toString().trim() ?? '') ?? 0;
  }
  if (value.isNaN || value.isNegative) return 0;
  if (value.isInfinite) return 0;
  return value;
}

/// Normalizes a raw map to exactly the five canonical fields.
Map<String, double> normalizeTargets(Map? raw) {
  final out = <String, double>{};
  for (final field in kTargetFields) {
    out[field] = normalizeTargetValue(raw?[field]);
  }
  return out;
}

/// Validates raw dialog input. Empty counts as 0. Returns an Arabic error
/// message, or null when the entry shape itself is acceptable (cap checks
/// against the manager's remaining share happen in [validateDistribution]).
String? validateTargetInputs(Map<String, String> controllers) {
  for (final field in kTargetFields) {
    final text = controllers[field]?.trim() ?? '';
    if (text.isEmpty) continue;
    final parsed = double.tryParse(text);
    if (parsed == null || parsed.isNaN || parsed.isInfinite) {
      return 'قيمة غير صالحة في ${kTargetLabelsAr[field]}';
    }
    if (parsed.isNegative) {
      return 'لا يُسمح بقيم سالبة في ${kTargetLabelsAr[field]}';
    }
  }
  return null;
}

/// Sums the five indicators across supervisor month entries.
Map<String, double> sumAllocations(Iterable<Map> entries) {
  final out = <String, double>{for (final f in kTargetFields) f: 0};
  for (final entry in entries) {
    final values = normalizeTargets(entry);
    for (final f in kTargetFields) {
      out[f] = out[f]! + values[f]!;
    }
  }
  return out;
}

/// Remaining share per indicator: received − already distributed.
Map<String, double> remainingTargets({
  required Map<String, double> received,
  required Map<String, double> distributed,
}) {
  return {
    for (final f in kTargetFields) f: (received[f]! - distributed[f]!),
  };
}

/// Validates a proposed supervisor allocation against the manager's
/// remaining share (received − sum of OTHER supervisors). Returns an Arabic
/// error naming the first offending indicator and its available amount.
String? validateDistribution({
  required Map<String, double> received,
  required Map<String, double> othersSum,
  required Map<String, double> proposed,
}) {
  for (final f in kTargetFields) {
    final available = received[f]! - othersSum[f]!;
    if (proposed[f]! - available > 1e-9) {
      return 'تجاوز في ${kTargetLabelsAr[f]}: المتاح ${available.toStringAsFixed(available == available.roundToDouble() ? 0 : 1)}';
    }
  }
  return null;
}

/// Builds a supervisor's `targets.<month>` entry. Merges over any existing
/// month entry so unrelated keys are preserved; only the five indicators,
/// audit fields, status and history are written. Previous history is kept
/// (capped at 50 entries, oldest dropped) — edits never erase the log.
Map<String, dynamic> buildSupervisorTargetEntry({
  required Map? existingEntry,
  required Map<String, dynamic> values,
  required String setByUid,
  required DateTime now,
}) {
  final normalized = normalizeTargets(values);
  final base = (existingEntry is Map)
      ? Map<String, dynamic>.from(existingEntry)
      : <String, dynamic>{};
  final history = <Map<String, dynamic>>[];
  if (base['history'] is List) {
    for (final item in (base['history'] as List)) {
      if (item is Map) history.add(Map<String, dynamic>.from(item));
    }
  }
  history.add(<String, dynamic>{
    'at': now,
    'byUid': setByUid,
    'byRole': 'sales_manager',
    'changes': Map<String, double>.from(normalized),
    'note': 'set',
  });
  while (history.length > 50) {
    history.removeAt(0);
  }
  return <String, dynamic>{
    ...base,
    ...normalized,
    'setByUid': setByUid,
    'setByRole': 'sales_manager',
    'setAt': base['setAt'] ?? now,
    'updatedAt': now,
    'status': kTargetStatusAssigned,
    'distributed': <String, double>{
      for (final f in kTargetFields) f: 0,
    },
    'history': history,
  };
}

/// Returns the updated manager month entry after a distribution: received
/// values untouched, `distributed` refreshed to the new totals, one audit
/// record appended (previous history preserved, capped at 50).
Map<String, dynamic> applyDistributionToManager({
  required Map managerEntry,
  required Map<String, double> distributed,
  required String setByUid,
  required String supervisorId,
  required DateTime now,
}) {
  final base = Map<String, dynamic>.from(managerEntry);
  final received = normalizeTargets(base);
  final fully = kTargetFields.every(
      (f) => distributed[f]! + 1e-9 >= received[f]!);
  final history = <Map<String, dynamic>>[];
  if (base['history'] is List) {
    for (final item in (base['history'] as List)) {
      if (item is Map) history.add(Map<String, dynamic>.from(item));
    }
  }
  history.add(<String, dynamic>{
    'at': now,
    'byUid': setByUid,
    'byRole': 'sales_manager',
    'changes': <String, dynamic>{
      'supervisorId': supervisorId,
      'distributed': Map<String, double>.from(distributed),
    },
    'note': 'distribute',
  });
  while (history.length > 50) {
    history.removeAt(0);
  }
  return <String, dynamic>{
    ...base,
    'distributed': Map<String, double>.from(distributed),
    'updatedAt': now,
    'status': fully ? kTargetStatusFull : kTargetStatusPartial,
    'history': history,
  };
}

/// Month progress for follow-up headers. Never throws. For the current month
/// the elapsed share is days passed (including today) over month length; a
/// past month reports 100% with 0 remaining, a future one 0% with all days
/// remaining.
Map<String, dynamic> monthProgress({
  required DateTime now,
  required int year,
  required int month,
}) {
  final start = DateTime(year, month, 1);
  final daysInMonth = DateTime(year, month + 1, 0).day;
  final end = DateTime(year, month, daysInMonth);
  final today = DateTime(now.year, now.month, now.day);
  late final int elapsedDays;
  late final double percent;
  if (today.isBefore(start)) {
    elapsedDays = 0;
    percent = 0;
  } else if (today.isAfter(end)) {
    elapsedDays = daysInMonth;
    percent = 100;
  } else {
    elapsedDays = today.difference(start).inDays + 1;
    percent = elapsedDays / daysInMonth * 100;
  }
  return <String, dynamic>{
    'start': start,
    'end': end,
    'daysInMonth': daysInMonth,
    'elapsedDays': elapsedDays,
    'remainingDays': daysInMonth - elapsedDays,
    'percent': percent,
  };
}

/// Reads one month out of a document's `targets` map. Never throws; a
/// missing month reports `hasTarget: false` with zeroed values.
Map<String, dynamic> summarizeTargetEntry(Map? targets, String monthKey) {
  final month = (targets is Map) ? targets[monthKey] : null;
  if (month is! Map) {
    return <String, dynamic>{
      'hasTarget': false,
      'values': normalizeTargets(null),
      'distributed': normalizeTargets(null),
      'status': '',
      'historyCount': 0,
    };
  }
  final data = Map<String, dynamic>.from(month);
  final distributed = (data['distributed'] is Map)
      ? normalizeTargets(data['distributed'])
      : normalizeTargets(null);
  final history = data['history'];
  return <String, dynamic>{
    'hasTarget': true,
    'values': normalizeTargets(data),
    'distributed': distributed,
    'status': data['status']?.toString() ?? '',
    'setByUid': data['setByUid']?.toString() ?? '',
    'setByRole': data['setByRole']?.toString() ?? '',
    'historyCount': history is List ? history.length : 0,
  };
}

/// Atomically distributes one supervisor's share of the manager's monthly
/// target. Everything is re-read inside the transaction, so two concurrent
/// saves cannot jointly exceed the manager's target: the second one sees
/// the first one's write and fails validation.
///
/// Throws [StateError] with an Arabic message when the manager has no
/// target for [month] or the proposal exceeds the remaining share.
Future<void> distributeSupervisorTarget({
  required FirebaseFirestore db,
  required String managerId,
  required String supervisorId,
  required List<String> allSupervisorIds,
  required String month,
  required Map<String, dynamic> values,
  required String setByUid,
  required DateTime now,
}) async {
  final proposed = normalizeTargets(values);
  await db.runTransaction((tx) async {
    final managerRef = db.collection('managers').doc(managerId);
    final managerSnap = await tx.get(managerRef);
    final managerData = managerSnap.data() ?? <String, dynamic>{};
    final managerTargets = (managerData['targets'] is Map)
        ? Map<String, dynamic>.from(managerData['targets'] as Map)
        : <String, dynamic>{};
    final managerEntry = managerTargets[month];
    if (managerEntry is! Map) {
      throw StateError('لا يوجد هدف مسند لهذا الشهر بعد');
    }
    final received = normalizeTargets(managerEntry);

    // Re-read every supervised supervisor inside the transaction.
    final othersEntries = <Map<String, dynamic>>[];
    for (final id in allSupervisorIds) {
      final snap = await tx.get(db.collection('managers').doc(id));
      final data = snap.data() ?? <String, dynamic>{};
      final targets = (data['targets'] is Map)
          ? Map<String, dynamic>.from(data['targets'] as Map)
          : <String, dynamic>{};
      final entry = targets[month];
      if (id != supervisorId && entry is Map) {
        othersEntries.add(Map<String, dynamic>.from(entry));
      }
    }
    final othersSum = sumAllocations(othersEntries);
    final capError = validateDistribution(
      received: received,
      othersSum: othersSum,
      proposed: proposed,
    );
    if (capError != null) {
      throw StateError(capError);
    }

    // Supervisor entry (merged, history preserved).
    final supervisorRef = db.collection('managers').doc(supervisorId);
    final supervisorSnap = await tx.get(supervisorRef);
    final supervisorData =
        Map<String, dynamic>.from(supervisorSnap.data() ?? {});
    final supervisorTargets = (supervisorData['targets'] is Map)
        ? Map<String, dynamic>.from(supervisorData['targets'] as Map)
        : <String, dynamic>{};
    supervisorTargets[month] = buildSupervisorTargetEntry(
      existingEntry: supervisorTargets[month],
      values: values,
      setByUid: setByUid,
      now: now,
    );

    // Manager entry: refresh distributed totals + audit.
    final newDistributed = sumAllocations([
      ...othersEntries,
      Map<String, dynamic>.from(normalizeTargets(proposed)),
    ]);
    managerTargets[month] = applyDistributionToManager(
      managerEntry: Map<String, dynamic>.from(managerEntry),
      distributed: newDistributed,
      setByUid: setByUid,
      supervisorId: supervisorId,
      now: now,
    );

    tx.update(supervisorRef, {'targets': supervisorTargets});
    tx.update(managerRef, {'targets': managerTargets});
  });
}
