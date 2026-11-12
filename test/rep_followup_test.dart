import 'package:aksab_sales/screens/admin/performance_dashboard_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sizer/sizer.dart';

// Rep monthly follow-up (aksabsaels): the rep's five indicators vs the
// share distributed by their supervisor, same layout rules as the
// supervisor page (goal / actual / real percent / remaining, no fake 0%).
void main() {
  String monthKey() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';
  }

  Timestamp ts(int day, [int hour = 10]) {
    final now = DateTime.now();
    return Timestamp.fromDate(DateTime(now.year, now.month, day, hour));
  }

  Future<FakeFirebaseFirestore> seed() async {
    final fake = FakeFirebaseFirestore();
    final month = monthKey();
    // Rep with a full five-indicator distributed target.
    await fake.collection('salesRep').doc('p1').set({
      'fullname': 'مندوب',
      'repCode': 'R1',
      'repType': 'permanent',
      'supervisorId': 's1',
      'targets': {
        month: {
          'financialTarget': 8000,
          'hoursTarget': 40,
          'invoicesTarget': 20,
          'clientsTarget': 10,
          'visitsTarget': 25,
          'setByUid': 's1',
          'setByRole': 'sales_supervisor',
        },
      },
    });
    // Rep with a legacy two-field target (backward compatibility).
    await fake.collection('salesRep').doc('p2').set({
      'fullname': 'مندوب قديم',
      'repCode': 'R2',
      'repType': 'permanent',
      'supervisorId': 's1',
      'targets': {
        month: {'financialTarget': 5000, 'visitsTarget': 20},
      },
    });
    // Rep without any target.
    await fake.collection('salesRep').doc('p3').set({
      'fullname': 'مندوب بلا هدف',
      'repCode': 'R3',
      'repType': 'permanent',
      'supervisorId': 's1',
    });
    // Freelance rep (out of scope badge).
    await fake.collection('salesRep').doc('f1').set({
      'fullname': 'مندوب حر',
      'repCode': 'RF',
      'repType': 'freelance',
      'supervisorId': 's1',
    });
    // Orders for R1: B1 twice + B2 once → 3 invoices, 2 clients, 9000.
    await fake.collection('orders').doc('o1').set({
      'buyer': {'repCode': 'R1', 'id': 'B1'},
      'total': 3000,
      'status': 'delivered',
      'orderDate': ts(5),
    });
    await fake.collection('orders').doc('o2').set({
      'buyer': {'repCode': 'R1', 'id': 'B1'},
      'total': 2000,
      'status': 'delivered',
      'orderDate': ts(6),
    });
    await fake.collection('orders').doc('o3').set({
      'buyer': {'repCode': 'R1', 'id': 'B2'},
      'total': 4000,
      'status': 'delivered',
      'orderDate': ts(7),
    });
    await fake.collection('visits').doc('v1').set({
      'repCode': 'R1',
      'startTime': ts(5),
    });
    await fake.collection('visits').doc('v2').set({
      'repCode': 'R1',
      'startTime': ts(6),
    });
    Future<void> log(String id, int h) => fake
        .collection('daily_logs')
        .doc(id)
        .set({
          'repCode': 'R1',
          'startTime': Timestamp.fromDate(DateTime.now()
              .subtract(Duration(hours: h + 1))),
          'endTime': Timestamp.fromDate(
              DateTime.now().subtract(const Duration(hours: 1))),
        });
    await log('l1', 6);
    await log('l2', 2);
    return fake;
  }

  Future<void> pumpRep(
      WidgetTester tester, FakeFirebaseFirestore fake, String id,
      [String name = 'مندوب', String? repCode]) async {
    await tester.pumpWidget(
      Sizer(
        builder: (context, orientation, deviceType) => MaterialApp(
          home: Scaffold(
            body: PerformanceDashboardScreen(
              targetDocId: id,
              targetType: 'sales',
              targetName: name,
              repCode: repCode,
              firestore: fake,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  group('rep follow-up cards', () {
    testWidgets('shows the five indicators vs the distributed target',
        (tester) async {
      final fake = await seed();
      await pumpRep(tester, fake, 'p1', 'مندوب', 'R1');

      expect(find.text('كود المندوب: R1'), findsOneWidget);
      expect(find.text('الفعلي حتى اليوم: 8 ساعة'), findsOneWidget);
      // 20% twice: hours (8/40) and clients (2/10) — same percent, both real.
      expect(find.text('الإنجاز: 20%'), findsNWidgets(2));
      expect(find.text('الفعلي حتى اليوم: 3 فاتورة'), findsOneWidget);
      expect(find.text('الفعلي حتى اليوم: 2 عميل'), findsOneWidget);
      expect(find.text('الفعلي حتى اليوم: 2 زيارة'), findsOneWidget);
      // 9000 / 8000 → real 112.5%, bar capped, remaining zeroed with overrun.
      expect(find.text('الفعلي حتى اليوم: 9000 ج.م'), findsOneWidget);
      expect(find.text('الإنجاز: 112.5%'), findsOneWidget);
      expect(find.text('المتبقي: 0 ج.م (تجاوز بـ 1000 ج.م)'),
          findsOneWidget);
    });

    testWidgets('legacy two-field entries keep working, rest show no-target',
        (tester) async {
      final fake = await seed();
      await pumpRep(tester, fake, 'p2', 'مندوب قديم', 'R2');
      expect(find.text('الهدف: 5000 ج.م'), findsOneWidget);
      expect(find.text('الهدف: 20 زيارة'), findsOneWidget);
      expect(find.textContaining('لم يُحدد هدف'), findsNWidgets(3));
      expect(find.textContaining('الإنجاز:'), findsNWidgets(2));
    });

    testWidgets('missing goal shows the badge, never a fake 0%',
        (tester) async {
      final fake = await seed();
      await pumpRep(tester, fake, 'p3', 'مندوب بلا هدف', 'R3');
      expect(find.textContaining('لم يُحدد هدف'), findsNWidgets(5));
      expect(find.textContaining('الإنجاز:'), findsNothing);
    });

    testWidgets('freelance rep gets the out-of-scope badge', (tester) async {
      final fake = await seed();
      await pumpRep(tester, fake, 'f1', 'مندوب حر', 'RF');
      expect(find.textContaining('خارج نطاق توزيع ومتابعة الأهداف'),
          findsOneWidget);
    });
  });
}
