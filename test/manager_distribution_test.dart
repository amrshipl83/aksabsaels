import 'dart:convert';

import 'package:aksab_sales/screens/admin/manage_users_screen.dart';
import 'package:aksab_sales/utils/target_distribution.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sizer/sizer.dart';

// Phase-2 manager distribution (aksabsaels, manager role only):
// receiving the admin target, listing own supervisors, partial/excess
// distribution, edits with audit, role gating, freelance exclusion.
void main() {
  String monthKey() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';
  }

  Map<String, dynamic> managerEntry({
    double financial = 10000,
    double hours = 160,
    double invoices = 100,
    double clients = 50,
    double visits = 200,
  }) =>
      {
        'financialTarget': financial,
        'hoursTarget': hours,
        'invoicesTarget': invoices,
        'clientsTarget': clients,
        'visitsTarget': visits,
        'setByUid': 'admin',
        'setByRole': 'admin',
        'setAt': DateTime(2026, 11, 1),
        'updatedAt': DateTime(2026, 11, 1),
        'status': kTargetStatusAssigned,
        'distributed': {
          for (final f in kTargetFields) f: 0,
        },
        'history': [
          {'note': 'set', 'byUid': 'admin', 'byRole': 'admin'}
        ],
      };

  Future<FakeFirebaseFirestore> seed() async {
    final fake = FakeFirebaseFirestore();
    final month = monthKey();
    await fake.collection('managers').doc('m1').set({
      'role': 'sales_manager',
      'fullname': 'مدير المبيعات',
      'targets': {month: managerEntry()},
    });
    await fake.collection('managers').doc('m0').set({
      'role': 'sales_manager',
      'fullname': 'مدير بلا هدف',
    });
    await fake.collection('managers').doc('s1').set({
      'role': 'sales_supervisor',
      'fullname': 'مشرف أول',
      'managerId': 'm1',
    });
    await fake.collection('managers').doc('s2').set({
      'role': 'sales_supervisor',
      'fullname': 'مشرف ثان',
      'managerId': 'm1',
    });
    await fake.collection('managers').doc('s3').set({
      'role': 'sales_supervisor',
      'fullname': 'مشرف أجنبي',
      'managerId': 'other',
    });
    await fake.collection('salesRep').doc('p1').set({
      'fullname': 'مندوب ثابت',
      'repCode': 'R1',
      'repType': 'permanent',
      'supervisorId': 's1',
    });
    await fake.collection('salesRep').doc('f1').set({
      'fullname': 'مندوب حر',
      'repCode': 'RF',
      'repType': 'freelance',
      'supervisorId': 's1',
    });
    return fake;
  }

  Future<void> pumpAs(
    WidgetTester tester,
    FakeFirebaseFirestore fake,
    Map<String, dynamic> user,
  ) async {
    SharedPreferences.setMockInitialValues({'userData': jsonEncode(user)});
    await tester.pumpWidget(
      Sizer(
        builder: (context, orientation, deviceType) => MaterialApp(
          home: Scaffold(body: ManageUsersScreen(firestore: fake)),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  Map<String, dynamic> managerUser(String docId, String name) => {
        'docId': docId,
        'role': 'sales_manager',
        'fullname': name,
      };

  group('manager receives the admin target', () {
    testWidgets('header shows the five indicators with totals',
        (tester) async {
      final fake = await seed();
      await pumpAs(tester, fake, managerUser('m1', 'مدير المبيعات'));
      final month = monthKey();
      expect(find.text('هدفك المستلم من الإدارة — $month'), findsOneWidget);
      expect(find.text('مستلم: 10000'), findsOneWidget);
      expect(find.text('موزع: 0'), findsNWidgets(5));
      expect(find.text('متبقي: 10000'), findsOneWidget);
    });

    testWidgets('manager without a target sees the empty message',
        (tester) async {
      final fake = await seed();
      await pumpAs(tester, fake, managerUser('m0', 'مدير بلا هدف'));
      expect(find.text('لم يُسند إليك هدف لهذا الشهر بعد.'), findsOneWidget);
    });

    testWidgets('only own supervisors are listed', (tester) async {
      final fake = await seed();
      await pumpAs(tester, fake, managerUser('m1', 'مدير المبيعات'));
      expect(find.text('مشرف أول'), findsOneWidget);
      expect(find.text('مشرف ثان'), findsOneWidget);
      expect(find.text('مشرف أجنبي'), findsNothing);
    });
  });

  group('distribution flow', () {
    Future<void> distributeFirst(
      WidgetTester tester,
      FakeFirebaseFirestore fake, {
      String financial = '4000',
      String visits = '50',
    }) async {
      await pumpAs(tester, fake, managerUser('m1', 'مدير المبيعات'));
      expect(find.text('توزيع الهدف'), findsNWidgets(2));
      await tester.tap(find.text('توزيع الهدف').first);
      await tester.pumpAndSettle();
      expect(find.text('توزيع الهدف: مشرف أول'), findsOneWidget);
      final fields = find.byType(TextField);
      expect(fields, findsNWidgets(5)); // the five indicators, current month fixed
      await tester.enterText(fields.at(0), financial);
      await tester.enterText(fields.at(4), visits);
      await tester.tap(find.text('حفظ التوزيع'));
      await tester.pumpAndSettle();
    }

    testWidgets('partial distribution saves and updates remaining',
        (tester) async {
      final fake = await seed();
      await distributeFirst(tester, fake);
      final month = monthKey();

      final sup = await fake.collection('managers').doc('s1').get();
      final entry = (sup.data()!['targets'] as Map)[month] as Map;
      expect(entry['financialTarget'], 4000);
      expect(entry['visitsTarget'], 50);
      expect(entry['setByRole'], 'sales_manager');
      expect((entry['history'] as List), hasLength(1));

      final mgr = await fake.collection('managers').doc('m1').get();
      final mEntry = (mgr.data()!['targets'] as Map)[month] as Map;
      expect((mEntry['distributed'] as Map)['financialTarget'], 4000);
      expect((mEntry['history'] as List), hasLength(2));
      expect(
          ((mEntry['history'] as List).last as Map)['note'], 'distribute');

      // Header reflects the new remaining (dialog closed → back on list).
      expect(find.text('متبقي: 6000'), findsOneWidget);
    });

    testWidgets('exceeding the remaining share is rejected', (tester) async {
      final fake = await seed();
      await distributeFirst(tester, fake,
          financial: '9000', visits: '190');
      // Second supervisor tries more than the remaining 1000 / 10.
      await tester.ensureVisible(find.text('توزيع الهدف').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('توزيع الهدف').last);
      await tester.pumpAndSettle();
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), '2000');
      await tester.tap(find.text('حفظ التوزيع'));
      await tester.pumpAndSettle();
      expect(find.textContaining('تجاوز'), findsOneWidget);
      // Dialog stays open (not saved).
      expect(find.text('حفظ التوزيع'), findsOneWidget);
    });

    testWidgets('editing a previous distribution and reopening',
        (tester) async {
      final fake = await seed();
      await distributeFirst(tester, fake);
      final month = monthKey();

      // Reopen the same supervisor: saved values are prefilled.
      await tester.ensureVisible(find.text('توزيع الهدف').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('توزيع الهدف').first);
      await tester.pumpAndSettle();
      final fields = find.byType(TextField);
      expect(
          (fields.at(0).evaluate().single.widget as TextField)
              .controller
              ?.text,
          '4000');

      // Raise to 5000 (within the 10000 total).
      await tester.enterText(fields.at(0), '5000');
      await tester.tap(find.text('حفظ التوزيع'));
      await tester.pumpAndSettle();

      final sup = await fake.collection('managers').doc('s1').get();
      final entry = (sup.data()!['targets'] as Map)[month] as Map;
      expect(entry['financialTarget'], 5000);
      // Edit appends history instead of erasing it.
      expect((entry['history'] as List), hasLength(2));
    });
  });

  group('transaction-level caps (no joint overshoot)', () {
    test('second overlapping save fails inside the transaction', () async {
      final fake = await seed();
      final month = monthKey();
      await distributeSupervisorTarget(
        db: fake,
        managerId: 'm1',
        supervisorId: 's1',
        allSupervisorIds: const ['s1', 's2'],
        month: month,
        values: {
          'financialTarget': 6000,
          'hoursTarget': 96,
          'invoicesTarget': 60,
          'clientsTarget': 30,
          'visitsTarget': 120,
        },
        setByUid: 'm1',
        now: DateTime.now(),
      );
      // 6000 + 5000 > 10000 → rejected even though each alone fits.
      await expectLater(
        distributeSupervisorTarget(
          db: fake,
          managerId: 'm1',
          supervisorId: 's2',
          allSupervisorIds: const ['s1', 's2'],
          month: month,
          values: {'financialTarget': 5000},
          setByUid: 'm1',
          now: DateTime.now(),
        ),
        throwsA(isA<StateError>()),
      );
      // ... while a fitting remainder succeeds and marks totals.
      await distributeSupervisorTarget(
        db: fake,
        managerId: 'm1',
        supervisorId: 's2',
        allSupervisorIds: const ['s1', 's2'],
        month: month,
        values: {
          'financialTarget': 4000,
          'hoursTarget': 64,
          'invoicesTarget': 40,
          'clientsTarget': 20,
          'visitsTarget': 80,
        },
        setByUid: 'm1',
        now: DateTime.now(),
      );
      final mgr = await fake.collection('managers').doc('m1').get();
      final mEntry = (mgr.data()!['targets'] as Map)[month] as Map;
      expect((mEntry['distributed'] as Map)['financialTarget'], 10000);
      expect(mEntry['status'], kTargetStatusFull);
    });

    test('distribution without a manager target throws', () async {
      final fake = await seed();
      await expectLater(
        distributeSupervisorTarget(
          db: fake,
          managerId: 'm0',
          supervisorId: 's1',
          allSupervisorIds: const ['s1'],
          month: monthKey(),
          values: {'financialTarget': 100},
          setByUid: 'm0',
          now: DateTime.now(),
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('role gating', () {
    testWidgets('supervisor sees no distribution tools', (tester) async {
      final fake = await seed();
      await pumpAs(tester, fake, {
        'docId': 's1',
        'role': 'sales_supervisor',
        'fullname': 'مشرف أول',
      });
      expect(find.text('توزيع الهدف'), findsNothing);
      expect(find.text('هدفك المستلم من الإدارة'), findsNothing);
      // Own permanent rep listed; freelance rep excluded.
      expect(find.text('مندوب ثابت'), findsOneWidget);
      expect(find.text('مندوب حر'), findsNothing);
    });

    testWidgets('freelance reps never enter the manager reps tab',
        (tester) async {
      final fake = await seed();
      await pumpAs(tester, fake, managerUser('m1', 'مدير المبيعات'));
      await tester.tap(find.text('جميع المندوبين'));
      await tester.pumpAndSettle();
      expect(find.text('مندوب ثابت'), findsOneWidget);
      expect(find.text('مندوب حر'), findsNothing);
    });
  });
}
