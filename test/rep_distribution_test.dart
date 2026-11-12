import 'dart:convert';

import 'package:aksab_sales/screens/admin/manage_users_screen.dart';
import 'package:aksab_sales/screens/admin/rep_distribution_dialog.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sizer/sizer.dart';

// Supervisor → permanent reps distribution (aksabsaels, supervisor role):
// receiving the manager target, listing own permanent reps only,
// partial/excess distribution, edits with audit, freelance exclusion.
void main() {
  String monthKey() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';
  }

  Map<String, dynamic> supEntry({
    double financial = 5000,
    double hours = 100,
    double invoices = 50,
    double clients = 20,
    double visits = 30,
  }) =>
      {
        'financialTarget': financial,
        'hoursTarget': hours,
        'invoicesTarget': invoices,
        'clientsTarget': clients,
        'visitsTarget': visits,
        'setByUid': 'm1',
        'setByRole': 'sales_manager',
        'setAt': DateTime(2026, 11, 1),
        'updatedAt': DateTime(2026, 11, 1),
        'status': 'assigned',
        'distributed': {
          'financialTarget': 0,
          'hoursTarget': 0,
          'invoicesTarget': 0,
          'clientsTarget': 0,
          'visitsTarget': 0,
        },
        'history': [
          {'note': 'set', 'byUid': 'm1', 'byRole': 'sales_manager'}
        ],
      };

  Future<FakeFirebaseFirestore> seed() async {
    final fake = FakeFirebaseFirestore();
    final month = monthKey();
    await fake.collection('managers').doc('s1').set({
      'role': 'sales_supervisor',
      'fullname': 'مشرف',
      'managerId': 'm1',
      'targets': {month: supEntry()},
    });
    await fake.collection('managers').doc('s0').set({
      'role': 'sales_supervisor',
      'fullname': 'مشرف بلا هدف',
      'managerId': 'm1',
    });
    await fake.collection('salesRep').doc('p1').set({
      'fullname': 'مندوب أول',
      'repCode': 'R1',
      'repType': 'permanent',
      'supervisorId': 's1',
    });
    await fake.collection('salesRep').doc('p2').set({
      'fullname': 'مندوب ثان',
      'repCode': 'R2',
      'repType': 'permanent',
      'supervisorId': 's1',
    });
    await fake.collection('salesRep').doc('p0').set({
      'fullname': 'مندوب المشرف الآخر',
      'repCode': 'R0',
      'repType': 'permanent',
      'supervisorId': 's0',
    });
    await fake.collection('salesRep').doc('p9').set({
      'fullname': 'مندوب أجنبي',
      'repCode': 'R9',
      'repType': 'permanent',
      'supervisorId': 's2',
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

  group('supervisor receives the manager target', () {
    testWidgets('header shows the five indicators with totals',
        (tester) async {
      final fake = await seed();
      await pumpAs(tester, fake, {
        'docId': 's1',
        'role': 'sales_supervisor',
        'fullname': 'مشرف',
      });
      final month = monthKey();
      expect(find.text('هدفك المستلم من المدير — $month'), findsOneWidget);
      expect(find.text('مستلم: 5000'), findsOneWidget);
      expect(find.text('موزع: 0'), findsNWidgets(5));
    });

    testWidgets('only own permanent reps are listed', (tester) async {
      final fake = await seed();
      await pumpAs(tester, fake, {
        'docId': 's1',
        'role': 'sales_supervisor',
        'fullname': 'مشرف',
      });
      expect(find.text('مندوب أول'), findsOneWidget);
      expect(find.text('مندوب ثان'), findsOneWidget);
      expect(find.text('مندوب أجنبي'), findsNothing);
      expect(find.text('مندوب حر'), findsNothing);
      expect(find.text('توزيع الهدف'), findsNWidgets(2));
    });

    testWidgets('supervisor without a target sees the empty message',
        (tester) async {
      final fake = await seed();
      await pumpAs(tester, fake, {
        'docId': 's0',
        'role': 'sales_supervisor',
        'fullname': 'مشرف بلا هدف',
      });
      expect(find.text('لم يُسند إليك هدف لهذا الشهر بعد.'), findsOneWidget);
    });
  });

  group('rep distribution flow', () {
    Future<void> distributeFirst(
      WidgetTester tester,
      FakeFirebaseFirestore fake, {
      String financial = '2000',
      String visits = '10',
    }) async {
      await pumpAs(tester, fake, {
        'docId': 's1',
        'role': 'sales_supervisor',
        'fullname': 'مشرف',
      });
      await tester.ensureVisible(find.text('توزيع الهدف').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('توزيع الهدف').first);
      await tester.pumpAndSettle();
      expect(find.text('توزيع الهدف: مندوب أول'), findsOneWidget);
      final fields = find.byType(TextField);
      expect(fields, findsNWidgets(5));
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

      final rep = await fake.collection('salesRep').doc('p1').get();
      final entry = (rep.data()!['targets'] as Map)[month] as Map;
      expect(entry['financialTarget'], 2000);
      expect(entry['visitsTarget'], 10);
      expect(entry['setByRole'], 'sales_supervisor');
      expect((entry['history'] as List), hasLength(1));

      final sup = await fake.collection('managers').doc('s1').get();
      final sEntry = (sup.data()!['targets'] as Map)[month] as Map;
      expect((sEntry['distributed'] as Map)['financialTarget'], 2000);
      expect(sEntry['financialTarget'], 5000);
      final history = sEntry['history'] as List;
      expect(history, hasLength(2));
      expect((history.last as Map)['note'], 'distribute');
      expect(((history.last as Map)['changes'] as Map)['repId'], 'p1');

      expect(find.text('متبقي: 3000'), findsOneWidget);
    });

    testWidgets('exceeding the remaining share is rejected', (tester) async {
      final fake = await seed();
      await distributeFirst(tester, fake, financial: '4500', visits: '25');
      await tester.ensureVisible(find.text('توزيع الهدف').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('توزيع الهدف').last);
      await tester.pumpAndSettle();
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), '1000');
      await tester.tap(find.text('حفظ التوزيع'));
      await tester.pumpAndSettle();
      expect(find.textContaining('تجاوز'), findsOneWidget);
      expect(find.text('حفظ التوزيع'), findsOneWidget);
    });

    testWidgets('editing a previous distribution and reopening',
        (tester) async {
      final fake = await seed();
      await distributeFirst(tester, fake);
      final month = monthKey();

      await tester.ensureVisible(find.text('توزيع الهدف').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('توزيع الهدف').first);
      await tester.pumpAndSettle();
      final fields = find.byType(TextField);
      expect(
          (fields.at(0).evaluate().single.widget as TextField)
              .controller
              ?.text,
          '2000');

      await tester.enterText(fields.at(0), '2500');
      await tester.tap(find.text('حفظ التوزيع'));
      await tester.pumpAndSettle();

      final rep = await fake.collection('salesRep').doc('p1').get();
      final entry = (rep.data()!['targets'] as Map)[month] as Map;
      expect(entry['financialTarget'], 2500);
      expect((entry['history'] as List), hasLength(2));
    });

    testWidgets('dialog without a holder target blocks saving',
        (tester) async {
      final fake = await seed();
      await pumpAs(tester, fake, {
        'docId': 's0',
        'role': 'sales_supervisor',
        'fullname': 'مشرف بلا هدف',
      });
      await tester.tap(find.text('توزيع الهدف'));
      await tester.pumpAndSettle();
      expect(find.text('لا يوجد هدف مسند لهذا الشهر بعد.'), findsOneWidget);
      expect(find.text('حفظ التوزيع'), findsNothing);
    });
  });

  group('legacy docs and load failures never grey the dialog', () {
    Future<void> pumpDialog(
      WidgetTester tester,
      FakeFirebaseFirestore fake, {
      String repId = 'p1',
    }) async {
      await tester.pumpWidget(
        Sizer(
          builder: (context, orientation, deviceType) => MaterialApp(
            home: Scaffold(
              body: RepDistributionDialog(
                db: fake,
                supervisorId: 's1',
                repId: repId,
                repName: 'مندوب أول',
                setByUid: 's1',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('legacy rep doc without repType still opens the dialog',
        (tester) async {
      final fake = await seed();
      // مستند قديم مفتاحه رقم الهاتف ولا يحمل حقل repType.
      await fake.collection('salesRep').doc('201021070461').set({
        'fullname': 'مندوب قديم',
        'repCode': 'R0',
        'phone': '01021070461',
        'supervisorId': 's1',
      });
      await pumpAs(tester, fake, {
        'docId': 's1',
        'role': 'sales_supervisor',
        'fullname': 'مشرف',
      });
      await tester.ensureVisible(find.text('توزيع الهدف').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('توزيع الهدف').first);
      await tester.pumpAndSettle();
      expect(find.text('توزيع الهدف: مندوب أول'), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(5));
    });

    testWidgets('load failure shows an error instead of a grey dialog',
        (tester) async {
      final fake = _ThrowingSalesRepFirestore();
      final month = monthKey();
      await fake.collection('managers').doc('s1').set({
        'role': 'sales_supervisor',
        'fullname': 'مشرف',
        'managerId': 'm1',
        'targets': {
          month: {'financialTarget': 5000}
        },
      });
      await pumpDialog(tester, fake);
      expect(find.textContaining('تعذّر تحميل البيانات'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('حفظ التوزيع'), findsNothing);
    });
  });
}

class _ThrowingSalesRepFirestore extends FakeFirebaseFirestore {
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) {
    if (path == 'salesRep') throw StateError('query failed');
    return super.collection(path);
  }
}
