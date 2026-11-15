// منفذ الإغلاق التلقائي ليوم العمل على Firestore.
// يعمل داخل مشروع aksabsaels فقط (Flutter) — بلا Timer وبلا فحص شامل.
//
// دور هذه الخدمة:
// 1. تقييم يوم عمل واحد من أحدث بيانات السيرفر عبر transaction واحدة.
// 2. عند الاستحقاق: إغلاق الزيارة المفتوحة (بعلامة تلقائية مستقلة) ثم اليوم.
// 3. عند عدم الاستحقاق: تحديث بيانات الجدولة الاستشارية للفحص القادم.
//
// ملاحظة زمنية صريحة: قرار الاستحقاق يستخدم ساعة الجهاز (DateTime.now)
// في مسار التقييم الفرصي داخل التطبيق. لحظة الإغلاق المسجلة نفسها
// (endTime/autoClosedAt) تُكتب بـ FieldValue.serverTimestamp() فيطابق
// حساب الساعات الحالي (endTime - startTime) دون أي تغيير في المعادلات.
// المجدول الخارجي المستقبلي (Cloud Tasks + Functions — خارج نطاق هذا
// المشروع ويتطلب موافقة) يجب أن يمرر now بتوقيت السيرفر لنفس الدالة.

import 'package:cloud_firestore/cloud_firestore.dart';

import 'workday_auto_close_policy.dart';

/// أسماء الحقول المضافة (كلها اختيارية — لا تكسر المستندات القديمة).
abstract final class WorkdayAutoCloseFields {
  // على daily_logs:
  static const String nextCheckAt = 'autoCloseNextCheckAt';
  static const String basisMs = 'autoCloseBasisMs';
  static const String lastDecisionAt = 'autoCloseLastDecisionAt';
  static const String lastDecision = 'autoCloseLastDecision';
  static const String closedBy = 'closedBy'; // 'rep' | 'auto'
  static const String closedByRep = 'rep';
  static const String closedByAuto = 'auto';
  static const String autoCloseReason = 'autoCloseReason';
  static const String autoClosedAt = 'autoClosedAt';
  static const String notified = 'autoCloseNotified';
  static const String notifiedAt = 'autoCloseNotifiedAt';
  static const String pushPending = 'autoClosePushPending';
  static const String noticeText = 'autoCloseNoticeText';

  // على visits:
  static const String workdayId = 'workdayId';
  static const String autoClosed = 'autoClosed';
  static const String visitAutoClosedAt = 'autoClosedAt';
  static const String visitAutoCloseReason = 'autoCloseReason';
  static const String visitAutoClosedStatus = 'auto_closed';
}

/// نتيجة تنفيذ واحد (تُستخدم للواجهة والتقارير).
class WorkdayAutoCloseOutcome {
  /// هل أُغلق اليوم في هذه الدعوة تحديدًا.
  final bool dayClosedNow;

  /// هل أُغلقت زيارة تلقائيًا في هذه الدعوة.
  final bool visitClosedNow;
  final String? closedVisitId;

  /// هل اكتُفي بتحديث موعد الفحص القادم.
  final bool rescheduled;
  final DateTime? nextCheckAt;

  final String? reason;

  /// اليوم كان مغلقًا أصلًا — لم يُكتب أي شيء.
  final bool alreadyClosed;

  const WorkdayAutoCloseOutcome({
    required this.dayClosedNow,
    required this.visitClosedNow,
    this.closedVisitId,
    required this.rescheduled,
    this.nextCheckAt,
    this.reason,
    required this.alreadyClosed,
  });

  const WorkdayAutoCloseOutcome.noop({this.alreadyClosed = false})
      : dayClosedNow = false,
        visitClosedNow = false,
        closedVisitId = null,
        rescheduled = false,
        nextCheckAt = null,
        reason = null;
}

/// يُرمى عند محاولة إنشاء زيارة على يوم أُغلق في نفس اللحظة.
/// على الواجهة عرض رسالة بدء يوم جديد بدل إنشاء زيارة يتيمة.
class WorkdayClosedError implements Exception {}

class WorkdayAutoCloseService {
  final FirebaseFirestore db;

  WorkdayAutoCloseService({FirebaseFirestore? db})
      : db = db ?? FirebaseFirestore.instance;

  /// التقييم والتنفيذ ليوم عمل واحد.
  ///
  /// [workdayId]: معرف مستند daily_logs.
  /// [taskBasisMs]: أساس هذه المهمة (يُقرأ من المستند عند غيابه).
  /// [nowOverride]: لحظة التنفيذ (المجدول الخارجي يمرر توقيت السيرفر).
  ///
  /// آمن ضد التزامن: الاستعلامات (where) ممنوعة داخل transaction في
  /// Firestore، لذلك تُقرأ الزيارات قبل فتحها، ثم تُطبق الكتابة داخل
  /// transaction تعيد التحقق من بقاء اليوم مفتوحًا. القرار يُبنى على
  /// أحدث البيانات لا على بيانات الجدولة.
  Future<WorkdayAutoCloseOutcome> enforceOnce({
    required String workdayId,
    int? taskBasisMs,
    DateTime? nowOverride,
  }) async {
    final now = nowOverride ?? DateTime.now();
    final dayRef = db.collection('daily_logs').doc(workdayId);

    // قراءة اليوم خارج الـ transaction (الاستعلامات التالية ممنوعة داخلها).
    final dayPre = await dayRef.get();
    if (!dayPre.exists) return const WorkdayAutoCloseOutcome.noop();
    final pre = dayPre.data() ?? <String, dynamic>{};

    // اليوم مغلق بالفعل: لا تعديل إطلاقًا (يحمي من التنفيذ المكرر).
    if (pre['status'] != 'open') {
      return const WorkdayAutoCloseOutcome.noop(alreadyClosed: true);
    }

    final repCode = (pre['repCode'] ?? '').toString();
    final startTs = pre['startTime'];
    if (repCode.isEmpty || startTs is! Timestamp) {
      return const WorkdayAutoCloseOutcome.noop();
    }
    final dayStart = startTs.toDate();
    final int basis = taskBasisMs ??
        (pre[WorkdayAutoCloseFields.basisMs] is int
            ? pre[WorkdayAutoCloseFields.basisMs] as int
            : dayStart.millisecondsSinceEpoch);

      // الزيارات المرتبطة: الجديدة عبر workdayId، والقديمة (قبل الميزة)
      // عبر repCode + حد زمني من بداية اليوم. زيارات يوم آخر (تحمل
      // workdayId مختلفًا) تُستبعد حتى لا تؤثر مهمة قديمة على يوم أحدث.
      final linkedSnap = await db
          .collection('visits')
          .where(
            WorkdayAutoCloseFields.workdayId,
            isEqualTo: workdayId,
          )
          .get();
      final legacySnap = await db
          .collection('visits')
          .where('repCode', isEqualTo: repCode)
          .where(
            'startTime',
            isGreaterThanOrEqualTo: Timestamp.fromDate(dayStart),
          )
          .where(
            'startTime',
            isLessThanOrEqualTo:
                Timestamp.fromDate(now.add(const Duration(minutes: 5))),
          )
          .get();

      final refs = <VisitStartRef>[];
      final seen = <String>{};
      void collect(QuerySnapshot<Map<String, dynamic>> snap) {
        for (final d in snap.docs) {
          if (!seen.add(d.id)) continue;
          final data = d.data();
          final linked = data[WorkdayAutoCloseFields.workdayId];
          if (linked != null &&
              linked is String &&
              linked.isNotEmpty &&
              linked != workdayId) {
            continue; // زيارة تخص يوم عمل آخر.
          }
          final st = data['startTime'];
          if (st is! Timestamp) continue;
          refs.add(VisitStartRef(
            id: d.id,
            startTime: st.toDate(),
            isOpen: data['status'] == 'in_progress',
          ));
        }
      }

      collect(linkedSnap);
      collect(legacySnap);

      final decision = decideWorkdayAutoClose(
        workdayOpen: true,
        workdayStart: dayStart,
        visits: refs,
        taskBasisMs: basis,
        now: now,
      );

      // مرجع المندوب للقراءة المشروطة داخل الـ transaction (بدل استعلام).
      final repQuery = await db
          .collection('salesRep')
          .where('repCode', isEqualTo: repCode)
          .limit(1)
          .get();
      final DocumentReference<Map<String, dynamic>>? repRef =
          repQuery.docs.isNotEmpty ? repQuery.docs.first.reference : null;

      switch (decision.action) {
        case WorkdayAutoCloseAction.noop:
          return const WorkdayAutoCloseOutcome.noop();

        case WorkdayAutoCloseAction.reschedule:
          // كتابة الجدولة فقط إن بقي اليوم مفتوحًا لحظة الكتابة.
          await db.runTransaction((tx) async {
            final snap = await tx.get(dayRef);
            if (!snap.exists) return;
            if ((snap.data() ?? <String, dynamic>{})['status'] != 'open') {
              return;
            }
            tx.update(dayRef, {
              WorkdayAutoCloseFields.nextCheckAt:
                  Timestamp.fromDate(decision.nextCheckAt!),
              WorkdayAutoCloseFields.basisMs: decision.nextBasisMs!,
              WorkdayAutoCloseFields.lastDecisionAt:
                  FieldValue.serverTimestamp(),
              WorkdayAutoCloseFields.lastDecision: 'reschedule',
            });
          });
          return WorkdayAutoCloseOutcome(
            dayClosedNow: false,
            visitClosedNow: false,
            rescheduled: true,
            nextCheckAt: decision.nextCheckAt,
            alreadyClosed: false,
          );

        case WorkdayAutoCloseAction.closeWorkday:
          return db.runTransaction<WorkdayAutoCloseOutcome>((tx) async {
            final snap = await tx.get(dayRef);
            if (!snap.exists) return const WorkdayAutoCloseOutcome.noop();
            if ((snap.data() ?? <String, dynamic>{})['status'] != 'open') {
              return const WorkdayAutoCloseOutcome.noop(alreadyClosed: true);
            }
            _closeDayInTxn(tx, dayRef, decision.reason!);
            return WorkdayAutoCloseOutcome(
              dayClosedNow: true,
              visitClosedNow: false,
              rescheduled: false,
              reason: decision.reason,
              alreadyClosed: false,
            );
          });

        case WorkdayAutoCloseAction.closeVisitAndWorkday:
          return db.runTransaction<WorkdayAutoCloseOutcome>((tx) async {
            final snap = await tx.get(dayRef);
            if (!snap.exists) return const WorkdayAutoCloseOutcome.noop();
            if ((snap.data() ?? <String, dynamic>{})['status'] != 'open') {
              return const WorkdayAutoCloseOutcome.noop(alreadyClosed: true);
            }
            final visitRef =
                db.collection('visits').doc(decision.visitIdToClose!);
            final visitSnap = await tx.get(visitRef);
            var visitClosed = false;
            // لا نلمس زيارة أُغلقت يدويًا في نفس اللحظة.
            if (visitSnap.exists &&
                (visitSnap.data()?['status'] == 'in_progress')) {
              tx.update(visitRef, {
                'status': WorkdayAutoCloseFields.visitAutoClosedStatus,
                'endTime': FieldValue.serverTimestamp(),
                'notes': 'إغلاق تلقائي لانتهاء ساعة دون زيارة جديدة',
                WorkdayAutoCloseFields.autoClosed: true,
                WorkdayAutoCloseFields.visitAutoClosedAt:
                    FieldValue.serverTimestamp(),
                WorkdayAutoCloseFields.visitAutoCloseReason: decision.reason!,
              });
              visitClosed = true;
              // تصفير علامة الزيارة النشطة كما يفعل الإنهاء اليدوي.
              if (repRef != null) {
                final repSnap = await tx.get(repRef);
                if (repSnap.exists &&
                    repSnap.data()?['hasActiveVisit'] == true) {
                  tx.update(repRef, {
                    'hasActiveVisit': false,
                  });
                }
              }
            }
            _closeDayInTxn(tx, dayRef, decision.reason!);
            return WorkdayAutoCloseOutcome(
              dayClosedNow: true,
              visitClosedNow: visitClosed,
              closedVisitId: visitClosed ? decision.visitIdToClose : null,
              rescheduled: false,
              reason: decision.reason,
              alreadyClosed: false,
            );
          });
      }
  }

  void _closeDayInTxn(
    Transaction tx,
    DocumentReference<Map<String, dynamic>> dayRef,
    String reason,
  ) {
    tx.update(dayRef, {
      'status': 'closed',
      // بتوقيت السيرفر فيطابق حساب الساعات الحالي endTime - startTime.
      'endTime': FieldValue.serverTimestamp(),
      WorkdayAutoCloseFields.closedBy: WorkdayAutoCloseFields.closedByAuto,
      WorkdayAutoCloseFields.autoCloseReason: reason,
      WorkdayAutoCloseFields.autoClosedAt: FieldValue.serverTimestamp(),
      WorkdayAutoCloseFields.notified: false,
      WorkdayAutoCloseFields.pushPending: true,
      WorkdayAutoCloseFields.noticeText: kWorkdayAutoCloseNotice,
      WorkdayAutoCloseFields.nextCheckAt: FieldValue.delete(),
      WorkdayAutoCloseFields.lastDecisionAt: FieldValue.serverTimestamp(),
      WorkdayAutoCloseFields.lastDecision: 'close',
    });
  }

  /// تحديث بيانات الجدولة الاستشارية من أحدث بيانات السيرفر.
  /// يُستدعى بعد بدء يوم/زيارة أو إنهاء يدوي. استشاري فقط — القرار
  /// الحقيقي يُتخذ دائمًا في enforceOnce من البيانات الطازجة.
  Future<void> refreshScheduleMetadata(String workdayId) async {
    final dayRef = db.collection('daily_logs').doc(workdayId);
    final daySnap = await dayRef.get();
    if (!daySnap.exists) return;
    final day = daySnap.data() ?? <String, dynamic>{};
    if (day['status'] != 'open') return;
    final repCode = (day['repCode'] ?? '').toString();
    final startTs = day['startTime'];
    if (repCode.isEmpty || startTs is! Timestamp) return;
    final dayStart = startTs.toDate();

    DateTime basisTime = dayStart;
    final linked = await db
        .collection('visits')
        .where(WorkdayAutoCloseFields.workdayId, isEqualTo: workdayId)
        .get();
    final legacy = await db
        .collection('visits')
        .where('repCode', isEqualTo: repCode)
        .where('startTime',
            isGreaterThanOrEqualTo: Timestamp.fromDate(dayStart))
        .where('startTime',
            isLessThanOrEqualTo: Timestamp.fromDate(
                DateTime.now().add(const Duration(minutes: 5))))
        .get();
    for (final snap in [linked, legacy]) {
      for (final d in snap.docs) {
        final data = d.data();
        final linkedId = data[WorkdayAutoCloseFields.workdayId];
        if (linkedId != null &&
            linkedId is String &&
            linkedId.isNotEmpty &&
            linkedId != workdayId) {
          continue;
        }
        final st = data['startTime'];
        if (st is Timestamp && st.toDate().isAfter(basisTime)) {
          basisTime = st.toDate();
        }
      }
    }

    await dayRef.update({
      WorkdayAutoCloseFields.nextCheckAt: Timestamp.fromDate(
        basisTime.add(
          const Duration(milliseconds: kWorkdayAutoCloseInactivityMs),
        ),
      ),
      WorkdayAutoCloseFields.basisMs: basisTime.millisecondsSinceEpoch,
      WorkdayAutoCloseFields.lastDecisionAt: FieldValue.serverTimestamp(),
      WorkdayAutoCloseFields.lastDecision: 'refresh',
    });
  }

  /// حجز عرض الإشعار داخل الواجهة مرة واحدة (يمنع التكرار عند إعادة التنفيذ).
  /// يعيد true للفائز الأول فقط.
  /// إنشاء زيارة داخل transaction تشترط بقاء اليوم مفتوحًا.
  /// يتعارض مع transaction الإغلاق على مستند اليوم فيُعاد تنفيذ أحدهما —
  /// استحالة زيارة مفتوحة على يوم مغلق من الطرفين.
  Future<String> createVisitAssertingOpenDay({
    required Map<String, dynamic> visitData,
    required String? workdayId,
  }) async {
    final ref = db.collection('visits').doc();
    await db.runTransaction((tx) async {
      if (workdayId != null) {
        final snap = await tx.get(db.collection('daily_logs').doc(workdayId));
        if (!snap.exists || snap.data()?['status'] != 'open') {
          throw WorkdayClosedError();
        }
      }
      tx.set(ref, {
        ...visitData,
        if (workdayId != null) 'workdayId': workdayId,
      });
    });
    return ref.id;
  }

  Future<bool> claimNotice({required String workdayId}) async {
    final dayRef = db.collection('daily_logs').doc(workdayId);
    return db.runTransaction<bool>((tx) async {
      final snap = await tx.get(dayRef);
      final data = snap.data() ?? <String, dynamic>{};
      if (data[WorkdayAutoCloseFields.closedBy] !=
              WorkdayAutoCloseFields.closedByAuto ||
          data[WorkdayAutoCloseFields.notified] == true) {
        return false;
      }
      tx.update(dayRef, {
        WorkdayAutoCloseFields.notified: true,
        WorkdayAutoCloseFields.notifiedAt: FieldValue.serverTimestamp(),
      });
      return true;
    });
  }
}
