// اختبارات الإغلاق اليدوي الموثوق للزيارات.
// تعمل دون شبكة عبر FakeFirebaseFirestore (اعتمادية تطوير معلنة في
// pubspec) + اختبارات خالصة لمنطق التصنيف والرسائل والأثر.
// تغطي: نجاح الإغلاق، الفشل وإعادة المحاولة، إغلاق المغلق مسبقًا،
// الاستئناف بعد إغلاق السيرفر، زيارة جديدة بعد القديمة، حماية
// الملاحظات ووقت الإغلاق الأصليين.
import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aksab_sales/services/visit_close_service.dart';

Map<String, dynamic> openVisit({String repCode = 'R1'}) => <String, dynamic>{
      'repCode': repCode,
      'customerName': 'عميل اختبار',
      'status': 'in_progress',
      'startTime': Timestamp.fromMillisecondsSinceEpoch(1790000000000),
    };

/// طابع ثابت بدل ختم الخادم (انظر توثيق `serverTimestamp` في الخدمة).
Object? Function() fixedStamp(int millis) =>
    () => Timestamp.fromMillisecondsSinceEpoch(millis);

void main() {
  group('classifyCloseTarget / shouldResumeVisit', () {
    test('in_progress تعني متابعة الإغلاق والاستئناف', () {
      expect(
        classifyCloseTarget(<String, dynamic>{'status': 'in_progress'}),
        CloseTargetDecision.proceed,
      );
      expect(
        shouldResumeVisit(<String, dynamic>{'status': 'in_progress'}),
        isTrue,
      );
    });

    test('أي حالة نهائية تعني مغلقة مسبقًا وعدم الاستئناف', () {
      for (final s in <String>[
        'sold',
        'followup',
        'busy',
        'rejected',
        'auto_closed',
        'closed',
      ]) {
        expect(
          classifyCloseTarget(<String, dynamic>{'status': s}),
          CloseTargetDecision.alreadyClosed,
          reason: s,
        );
        expect(shouldResumeVisit(<String, dynamic>{'status': s}), isFalse,
            reason: s);
      }
    });

    test('غياب المستند: missing ولا استئناف', () {
      expect(classifyCloseTarget(null), CloseTargetDecision.missing);
      expect(shouldResumeVisit(null), isFalse);
    });

    test('الحالات اليدوية المسموحة تطابق قيم القائمة الأربع', () {
      expect(
        manualVisitCloseStatuses,
        <String>{'sold', 'followup', 'busy', 'rejected'},
      );
    });
  });

  group('buildCloseUpdate', () {
    test('تكتب الحالة والملاحظات وendTime معًا في عملية واحدة', () {
      final payload = buildCloseUpdate(
        status: 'sold',
        notes: 'تم البيع',
        location: <String, double>{'lat': 30.0, 'lng': 31.0},
      );
      expect(payload['status'], 'sold');
      expect(payload['notes'], 'تم البيع');
      expect(payload['endTime'], isA<FieldValue>());
      expect(payload['location'], <String, double>{'lat': 30.0, 'lng': 31.0});
    });

    test('غياب الموقع يبقي الحقل null كما في السلوك الحالي', () {
      final payload = buildCloseUpdate(status: 'busy', notes: '');
      expect(payload['location'], isNull);
    });
  });

  group('classifyCloseError', () {
    test('انقطاع الشبكة والمهلة وأخطاء السيرفر العابرة قابلة لإعادة المحاولة', () {
      expect(classifyCloseError(const SocketException('down')).retryable,
          isTrue);
      expect(
          classifyCloseError(TimeoutException('t', const Duration(seconds: 1)))
              .retryable,
          isTrue);
      expect(
          classifyCloseError(FirebaseException(
                  plugin: 'cloud_firestore', code: 'unavailable'))
              .retryable,
          isTrue);
      expect(
          classifyCloseError(FirebaseException(
                  plugin: 'cloud_firestore', code: 'deadline-exceeded'))
              .retryable,
          isTrue);
    });

    test('رفض الصلاحيات غير قابل لإعادة المحاولة', () {
      final c = classifyCloseError(FirebaseException(
          plugin: 'cloud_firestore', code: 'permission-denied'));
      expect(c.retryable, isFalse);
    });

    test('خطأ مجهول: الافتراض الآمن إعادة المحاولة (العملية محمية)', () {
      expect(classifyCloseError(StateError('weird')).retryable, isTrue);
    });
  });

  group('effectForResult / visitCloseMessage', () {
    test('الفشل يحتفظ بالحالة المحلية ويسمح بإعادة المحاولة', () {
      final effect = effectForResult(
          const VisitCloseResult.failed(retryable: true));
      expect(effect.clearLocal, isFalse);
      expect(effect.canRetry, isTrue);
      expect(
        visitCloseMessage(const VisitCloseResult.failed(retryable: true)),
        contains('أعد المحاولة'),
      );
    });

    test('الفشل غير القابل لإعادة المحاولة يحتفظ بالحالة أيضًا', () {
      final effect = effectForResult(
          const VisitCloseResult.failed(retryable: false));
      expect(effect.clearLocal, isFalse);
      expect(
        visitCloseMessage(const VisitCloseResult.failed(retryable: false)),
        contains('الإدارة'),
      );
    });

    test('النجاح يمسح المحلي، والمغلقة مسبقًا تُسقط المعرف دون كتابة', () {
      expect(effectForResult(const VisitCloseResult.closed()).clearLocal,
          isTrue);
      expect(
          effectForResult(const VisitCloseResult.alreadyClosed('sold'))
              .clearLocal,
          isTrue);
      expect(effectForResult(const VisitCloseResult.missing()).clearLocal,
          isTrue);
      expect(
        visitCloseMessage(const VisitCloseResult.alreadyClosed('sold')),
        contains('مغلقة مسبقًا'),
      );
    });
  });

  group('closeVisitReliably مع FakeFirestore', () {
    test('إغلاق يدوي ناجح: الحالة والملاحظات وendTime تُكتب وتُتحقق', () async {
      final db = FakeFirebaseFirestore();
      final ref = await db.collection('visits').add(openVisit());
      final result = await closeVisitReliably(
        db: db,
        visitId: ref.id,
        status: 'sold',
        notes: 'تم عمل طلبية',
        serverTimestamp: fixedStamp(1790000005000),
      );
      expect(result.outcome, VisitCloseOutcome.closed);
      final after = await ref.get();
      expect(after.data()?['status'], 'sold');
      expect(after.data()?['notes'], 'تم عمل طلبية');
      expect(after.data()?['endTime'], isNotNull);
    });

    test('زيارة مغلقة مسبقًا: لا كتابة — الملاحظات ووقت الإغلاق محفوظان',
        () async {
      final db = FakeFirebaseFirestore();
      final closedAt = Timestamp.fromMillisecondsSinceEpoch(1790000001000);
      final ref = await db.collection('visits').add(<String, dynamic>{
        ...openVisit(),
        'status': 'followup',
        'notes': 'ملاحظة أصلية لا تمسح',
        'endTime': closedAt,
      });
      final result = await closeVisitReliably(
        db: db,
        visitId: ref.id,
        status: 'sold',
        notes: 'محاولة كتابة فوق المغلقة',
      );
      expect(result.outcome, VisitCloseOutcome.alreadyClosed);
      expect(result.actualStatus, 'followup');
      final after = await ref.get();
      expect(after.data()?['status'], 'followup');
      expect(after.data()?['notes'], 'ملاحظة أصلية لا تمسح');
      expect(
        (after.data()?['endTime'] as Timestamp).millisecondsSinceEpoch,
        closedAt.millisecondsSinceEpoch,
      );
      final effect = effectForResult(result);
      expect(effect.clearLocal, isTrue);
      expect(effect.canRetry, isFalse);
    });

    test('مستند غائب: missing دون كتابة', () async {
      final db = FakeFirebaseFirestore();
      final result = await closeVisitReliably(
        db: db,
        visitId: 'no-such-visit',
        status: 'sold',
        notes: 'x',
      );
      expect(result.outcome, VisitCloseOutcome.missing);
    });

    test('إعادة الإغلاق على زيارة أُغلقت للتو: no-op آمن (لا تكرار)', () async {
      final db = FakeFirebaseFirestore();
      final ref = await db.collection('visits').add(openVisit());
      final first = await closeVisitReliably(
        db: db,
        visitId: ref.id,
        status: 'sold',
        notes: 'أول إغلاق',
        serverTimestamp: fixedStamp(1790000005000),
      );
      expect(first.outcome, VisitCloseOutcome.closed);
      final second = await closeVisitReliably(
        db: db,
        visitId: ref.id,
        status: 'sold',
        notes: 'محاولة ثانية',
        serverTimestamp: fixedStamp(1790000006000),
      );
      expect(second.outcome, VisitCloseOutcome.alreadyClosed);
      final after = await ref.get();
      expect(after.data()?['notes'], 'أول إغلاق');
    });
  });

  group('findOpenVisitId', () {
    test('يعيد الزيارة المفتوحة للمندوب ويتجاهل المغلقة ومندوبًا آخر',
        () async {
      final db = FakeFirebaseFirestore();
      final mine = await db.collection('visits').add(openVisit(repCode: 'R1'));
      await db.collection('visits').add(<String, dynamic>{
        ...openVisit(repCode: 'R1'),
        'status': 'sold',
      });
      await db.collection('visits').add(openVisit(repCode: 'R2'));
      expect(await findOpenVisitId(db: db, repCode: 'R1'), mine.id);
      expect(await findOpenVisitId(db: db, repCode: 'R9'), isNull);
    });

    test('بعد إغلاق السيرفر للزيارة: لا استئناف ولا زيارة مفتوحة', () async {
      final db = FakeFirebaseFirestore();
      final ref = await db.collection('visits').add(openVisit());
      await ref.update(<String, dynamic>{
        'status': 'auto_closed',
        'endTime': Timestamp.fromMillisecondsSinceEpoch(1790000004000),
      });
      final snap = await ref.get();
      expect(shouldResumeVisit(snap.data()), isFalse);
      expect(
        await findOpenVisitId(db: db, repCode: 'R1'),
        isNull,
      );
    });
  });
}
