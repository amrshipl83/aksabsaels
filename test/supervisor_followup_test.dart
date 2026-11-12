import 'package:aksab_sales/screens/admin/performance_dashboard_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sizer/sizer.dart';

// Supervisor follow-up (aksabsaels, manager view of one supervisor):
// five team indicators vs the distributed monthly target, real percents,
// remaining, month switching, supervisor-visits inclusion, team-hours
// separation, missing-goal handling.
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
    // Supervisor WITH a distributed target and an optional own repCode
    // (the same key visits use; supervisors have no repCode by default).
    await fake.collection('managers').doc('s1').set({
      'role': 'sales_supervisor',
      'fullname': 'مشرف',
      'managerId': 'm1',
      'repCode': 'S1',
      'targets': {
        month: {
          'financialTarget': 10000,
          'hoursTarget': 100,
          'invoicesTarget': 50,
          'clientsTarget': 20,
          'visitsTarget': 30,
          'setByUid': 'm1',
          'setByRole': 'sales_manager',
        },
      },
    });
    // Supervisor WITHOUT any target.
    await fake.collection('managers').doc('s2').set({
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
    // Orders: R1/B1 twice (one cancelled → still counted, documented),
    // R2/B2 once. Distinct clients = 2, invoices = 3, sales = 12000.
    Future<void> order(String id, String rep, String buyer, double total,
        [String status = 'delivered']) =>
        fake.collection('orders').doc(id).set({
          'buyer': {'repCode': rep, 'id': buyer},
          'total': total,
          'status': status,
          'orderDate': ts(5),
        });
    await order('o1', 'R1', 'B1', 5000);
    await order('o2', 'R1', 'B1', 3000, 'cancelled');
    await order('o3', 'R2', 'B2', 4000);
    // Visits: 2 (R1) + 1 (R2) + 1 (supervisor's own S1) = 4.
    Future<void> visit(String id, String rep) =>
        fake.collection('visits').doc(id).set({
          'repCode': rep,
          'startTime': ts(6),
        });
    await visit('v1', 'R1');
    await visit('v2', 'R1');
    await visit('v3', 'R2');
    await visit('v4', 'S1');
    // Hours: R1 8h + R2 4h = 12 team hours; supervisor's own 5h excluded.
    Future<void> log(String id, String rep, int h) => fake
        .collection('daily_logs')
        .doc(id)
        .set({
          'repCode': rep,
          'startTime': Timestamp.fromDate(DateTime.now().subtract(
              Duration(hours: h + 1))),
          'endTime': Timestamp.fromDate(
              DateTime.now().subtract(const Duration(hours: 1))),
        });
    await log('l1', 'R1', 8);
    await log('l2', 'R2', 4);
    await log('l3', 'S1', 5);
    return fake;
  }

  Future<void> pumpSupervisor(
      WidgetTester tester, FakeFirebaseFirestore fake, String id,
      [String name = 'مشرف']) async {
    await tester.pumpWidget(
      Sizer(
        builder: (context, orientation, deviceType) => MaterialApp(
          home: Scaffold(
            body: PerformanceDashboardScreen(
              targetDocId: id,
              targetType: 'sales_supervisor',
              targetName: name,
              firestore: fake,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  group('supervisor follow-up cards', () {
    testWidgets('shows the five team indicators vs the target',
        (tester) async {
      final fake = await seed();
      await pumpSupervisor(tester, fake, 's1');

      expect(find.text('متابعة أداء المشرفين'), findsOneWidget);
      expect(find.text('عدد المندوبين التابعين: 2'), findsOneWidget);

      // Team hours exclude the supervisor's own 5h log.
      expect(find.text('الفعلي حتى اليوم: 12 ساعة'), findsOneWidget);
      expect(find.text('الإنجاز: 12%'), findsOneWidget);

      // Cancelled invoice still counted (documented behavior): 3 invoices,
      // 2 distinct clients by stable buyer id.
      expect(find.text('الفعلي حتى اليوم: 3 فاتورة'), findsOneWidget);
      expect(find.text('الفعلي حتى اليوم: 2 عميل'), findsOneWidget);

      // Supervisor's own visit joins the team total: 4.
      expect(find.text('الفعلي حتى اليوم: 4 زيارة'), findsOneWidget);

      // Financial over-achievement shows the real percent.
      expect(find.text('الفعلي حتى اليوم: 12000 ج.م'), findsOneWidget);
      expect(find.text('الإنجاز: 120%'), findsOneWidget);
      expect(find.text('المتبقي: 0 ج.م (تجاوز بـ 2000 ج.م)'),
          findsOneWidget);

      // Counting rules are documented on the page.
      expect(find.textContaining('الملغاة'), findsOneWidget);
      expect(find.textContaining('الفريق فقط'), findsWidgets);
    });

    testWidgets('missing goal shows the no-target badge, never a fake 0%',
        (tester) async {
      final fake = await seed();
      await pumpSupervisor(tester, fake, 's2', 'مشرف بلا هدف');
      expect(find.textContaining('لم يُحدد هدف'), findsNWidgets(5));
      expect(find.textContaining('الإنجاز:'), findsNothing);
    });
  });

  group('month switching', () {
    testWidgets('shows the selected month only', (tester) async {
      final fake = await seed();
      final now = DateTime.now();
      final prev = DateTime(now.year, now.month - 1, 15);
      final prevKey =
          '${prev.year.toString().padLeft(4, '0')}-${prev.month.toString().padLeft(2, '0')}';
      // Previous-month target + one previous-month order.
      final s1 = await fake.collection('managers').doc('s1').get();
      final data = Map<String, dynamic>.from(s1.data()!);
      final targets =
          Map<String, dynamic>.from(data['targets'] as Map);
      targets[prevKey] = {
        'financialTarget': 5000,
        'hoursTarget': 10,
        'invoicesTarget': 5,
        'clientsTarget': 5,
        'visitsTarget': 5,
      };
      await fake
          .collection('managers')
          .doc('s1')
          .update({'targets': targets});
      await fake.collection('orders').doc('op').set({
        'buyer': {'repCode': 'R1', 'id': 'B9'},
        'total': 5000,
        'status': 'delivered',
        'orderDate': Timestamp.fromDate(prev),
      });

      await pumpSupervisor(tester, fake, 's1');
      expect(find.text('الفعلي حتى اليوم: 12000 ج.م'), findsOneWidget);

      const arabicMonths = [
        'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
        'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
      ];
      await tester.tap(
          find.byKey(ValueKey('month_${DateTime.now().month}')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(arabicMonths[prev.month - 1]).last);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 500));

      // Previous-month data only: the one 5000 order, nothing else.
      expect(find.text('الفعلي حتى اليوم: 5000 ج.م'), findsOneWidget);
      expect(find.text('الفعلي حتى اليوم: 12000 ج.م'), findsNothing);
    });
  });
}
