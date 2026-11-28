// lib/utils/rep_location.dart
//
// Shared Firestore reader for the unified rep position used by every
// geo-filtered rep screen (store, offers, gifts, bundles).
//
// Priority (no alternatives, no older-visit fallback):
//  1. newest visit by `startTime` (open or closed) — location used as-is;
//  2. open workday `daily_logs.startLocation`;
//  3. unknown (null) — callers then show global-only content.
// Read-only; every read failure degrades safely to the next source.

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'rep_position.dart';

/// Reads the repCode stored at login by the auth flow.
Future<String?> readStoredRepCode() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('userData');
    if (raw == null) return null;
    final decoded = json.decode(raw);
    if (decoded is Map) return decoded['repCode']?.toString();
    return null;
  } catch (_) {
    return null;
  }
}

/// Picks the newest visit by `startTime` from raw visit documents.
/// Pure and size-independent: scans the whole input, so the newest visit
/// wins even with more documents than any fetch cap. Documents without a
/// valid `startTime` Timestamp are skipped. `endTime` is never consulted.
Map<String, dynamic>? pickNewestVisitByStartTime(
    Iterable<Map<String, dynamic>> docs) {
  Map<String, dynamic>? newest;
  DateTime? newestStart;
  for (final v in docs) {
    final ts = v['startTime'];
    if (ts is! Timestamp) continue;
    final t = ts.toDate();
    if (newestStart == null || t.isAfter(newestStart)) {
      newestStart = t;
      newest = v;
    }
  }
  return newest;
}

/// Resolves the unified rep position for [repCode].
Future<RepPoint?> fetchUnifiedRepPoint(
    FirebaseFirestore db, String repCode) async {
  RepPoint? dayStart;
  try {
    final day = await db
        .collection('daily_logs')
        .where('repCode', isEqualTo: repCode)
        .where('status', isEqualTo: 'open')
        .limit(1)
        .get();
    if (day.docs.isNotEmpty) {
      final d = day.docs.first.data() as Map<String, dynamic>;
      final loc = d['startLocation'];
      final ts = d['startTime'];
      if (loc is Map && ts is Timestamp) {
        final lat =
            (loc['lat'] is num) ? (loc['lat'] as num).toDouble() : null;
        final lng =
            (loc['lng'] is num) ? (loc['lng'] as num).toDouble() : null;
        if (isValidLatLng(lat, lng)) {
          dayStart = RepPoint(lat: lat!, lng: lng!, time: ts.toDate());
        }
      }
    }
  } catch (_) {}
  RepPoint? newestVisit;
  try {
    // Newest visit by startTime, ordered server-side: guaranteed even with
    // more visits than any client-side cap. Requires the composite index
    // (visits: repCode ASC, startTime DESC) declared in
    // aksabsaels/firestore.indexes.json (not deployed yet).
    // `endTime` is never a ranking criterion.
    final visits = await db
        .collection('visits')
        .where('repCode', isEqualTo: repCode)
        .orderBy('startTime', descending: true)
        .limit(1)
        .get();
    final newest = pickNewestVisitByStartTime(
        visits.docs.map((doc) => doc.data() as Map<String, dynamic>));
    final ts = newest?['startTime'];
    if (newest != null && ts is Timestamp) {
      final loc = newest['location'];
      if (loc is Map) {
        final lat =
            (loc['lat'] is num) ? (loc['lat'] as num).toDouble() : null;
        final lng =
            (loc['lng'] is num) ? (loc['lng'] as num).toDouble() : null;
        if (isValidLatLng(lat, lng)) {
          newestVisit = RepPoint(lat: lat!, lng: lng!, time: ts.toDate());
        }
      }
    }
  } catch (_) {}
  return resolveRepPosition(dayStart: dayStart, newestVisit: newestVisit);
}
