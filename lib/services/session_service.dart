// lib/services/session_service.dart
// Minimal client-side session hardening. Does not replace Firestore Rules
// or Custom Claims; it only prevents stale local prefs from opening screens.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class SessionService {
  static Future<Map<String, dynamic>?> loadLocalUser() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('userData');
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Returns the stored docId when present (login saves snapshot.id).
  static Future<String?> loadLocalDocId() async {
    final user = await loadLocalUser();
    final docId = user?['docId']?.toString();
    return (docId == null || docId.isEmpty) ? null : docId;
  }

  /// Resolves the salesRep document id for [uid] with ownership verification.
  /// Never trusts a cached docId blindly: the cached doc must still exist
  /// and its `uid` field must equal [uid]. Otherwise falls back to a
  /// read-only lookup by uid field. Returns null when no owned doc exists.
  static Future<String?> resolveSalesRepDocId(String uid) async {
    final local = await loadLocalDocId();
    if (local != null) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('salesRep')
            .doc(local)
            .get();
        final data = snap.data();
        if (snap.exists && data != null && data['uid']?.toString() == uid) {
          return local;
        }
      } catch (_) {
        // Fall through to uid lookup below.
      }
    }
    final q = await FirebaseFirestore.instance
        .collection('salesRep')
        .where('uid', isEqualTo: uid)
        .limit(1)
        .get();
    if (q.docs.isEmpty) return null;
    return q.docs.first.id;
  }

  /// Validates that a Firebase user exists and the stored Firestore doc
  /// is still approved. Returns false when the session must be cleared.
  static Future<bool> isSessionValid() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    final local = await loadLocalUser();
    if (local == null) return false;
    final role = local['role']?.toString() ?? '';
    final storedUid = local['uid']?.toString() ?? '';
    if (storedUid.isNotEmpty && storedUid != user.uid) return false;
    try {
      if (role == 'sales_rep') {
        final docId = await resolveSalesRepDocId(user.uid);
        if (docId == null) return false;
        final snap = await FirebaseFirestore.instance
            .collection('salesRep')
            .doc(docId)
            .get();
        if (!snap.exists) return false;
        final status = (snap.data()?['status'])?.toString() ?? '';
        return status == 'approved';
      } else {
        final docId = local['docId']?.toString() ?? '';
        if (docId.isEmpty) return false;
        final snap = await FirebaseFirestore.instance
            .collection('managers')
            .doc(docId)
            .get();
        if (!snap.exists) return false;
        final status = (snap.data()?['status'])?.toString() ?? '';
        return status == 'approved';
      }
    } catch (_) {
      // Fail-open for offline: keep local session, screens re-check online.
      return true;
    }
  }

  static Future<void> clearSession() async {
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
