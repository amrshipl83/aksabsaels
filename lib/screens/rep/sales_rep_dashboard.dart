import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../utils/client_counts.dart';
import '../../utils/order_counts.dart';
// (visits now from workday_history; counter import removed)
import '../../utils/workday_history.dart';

class SalesRepDashboard extends StatefulWidget {
  final String repCode;
  final DateTime currentDayStartTime;
  final VoidCallback onDataRefreshed;

  const SalesRepDashboard({
    super.key,
    required this.repCode,
    required this.currentDayStartTime,
    required this.onDataRefreshed,
  });

  @override
  State<SalesRepDashboard> createState() => _SalesRepDashboardState();
}

class _SalesRepDashboardState extends State<SalesRepDashboard> {
  // Cairo keys fixed at open (same convention as the unified counter).
  late final String _monthKey = clientCountMonthKey();
  late final String _dayKey = clientCountDayKey();
  late final Stream<int> _todayClients = watchRepDayTotal(
    db: FirebaseFirestore.instance,
    repCode: widget.repCode,
    monthKey: _monthKey,
    dayKey: _dayKey,
  );
  // Visits from the historical `visits` records: today from the day range,
  // month total from the month range — same source as the admin board.
  late final Stream<int> _todayVisits = watchRepVisitDayTotalHist(
    db: FirebaseFirestore.instance,
    repCode: widget.repCode,
    monthKey: _monthKey,
    dayKey: _dayKey,
  );
  late final Stream<int> _monthVisits = watchRepVisitMonthTotalHist(
    db: FirebaseFirestore.instance,
    repCode: widget.repCode,
    monthKey: _monthKey,
  );
  // Orders from the unified counter: today from `days`, month total
  // from `total` — never recomputed from the `orders` collection.
  // Detail screens keep their own order-document queries for line items.
  late final Stream<OrderMonthSummary> _todayOrders =
      watchRepOrderDaySummary(
    db: FirebaseFirestore.instance,
    repCode: widget.repCode,
    monthKey: _monthKey,
    dayKey: _dayKey,
  );
  late final Stream<OrderMonthSummary> _monthOrders =
      watchRepOrderMonthSummary(
    db: FirebaseFirestore.instance,
    repCode: widget.repCode,
    monthKey: _monthKey,
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // صف يحتوي على بطاقتين (الزيارات والعملاء المؤهلين اليوم)
        Row(
          children: [
            Expanded(
              child: _buildTodayVisitsCard(),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildTodayClientsCard(),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // بطاقة عريضة للطلبات من المجمّع الموحد (عدد المستندات، لا القيمة)
        _buildTodayOrdersCard(),
      ],
    );
  }

  /// زيارات اليوم من السجلات التاريخية (الحالات النهائية فقط)
  /// (نطاق اليوم/الشهر على `visits`) — بث حي، نفس مصدر لوحة الأدمن.
  /// مع إجمالي الشهر من نطاق الشهر كعنوان فرعي. المفتوحة مستبعدة.
  Widget _buildTodayVisitsCard() {
    const title = 'الزيارات';
    const color = Colors.blue;
    const icon = Icons.location_on_outlined;
    return StreamBuilder<int>(
      stream: _todayVisits,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _buildCountCard(
            title: title,
            icon: icon,
            color: color,
            count: 'تعذر التحميل',
            subtitle: 'بتوقيت القاهرة',
          );
        }
        final today = snapshot.data ?? 0;
        return StreamBuilder<int>(
          stream: _monthVisits,
          builder: (context, monthSnapshot) {
            final monthTotal = monthSnapshot.data ?? 0;
            return _buildCountCard(
              title: title,
              icon: icon,
              color: color,
              count: '$today',
              subtitle: 'الشهر: $monthTotal',
            );
          },
        );
      },
    );
  }

  /// العملاء المؤهلون اليوم من العدّاد الموحد
  /// (`salesRep.clientCounts.{Cairo month}.days.{Cairo day}`) — بث حي.
  /// هذا ليس إجمالي حسابات `users` ولا عدد المسجلين اليوم في السجل
  /// (قائمة "عملائي" تعرض السجل، وليست العدّاد المؤهل).
  Widget _buildTodayClientsCard() {
    const title = 'عملاء مؤهلون اليوم';
    const color = Colors.orange;
    const icon = Icons.person_add_alt_1_outlined;
    return StreamBuilder<int>(
      stream: _todayClients,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _buildCountCard(
            title: title,
            icon: icon,
            color: color,
            count: 'تعذر التحميل',
            subtitle: 'بتوقيت القاهرة',
          );
        }
        return _buildCountCard(
          title: title,
          icon: icon,
          color: color,
          count: '${snapshot.data ?? 0}',
          subtitle: 'بتوقيت القاهرة',
        );
      },
    );
  }

  /// طلبات اليوم من المجمّع الموحد
  /// (`salesRep.ordersByMonth.{Cairo month}.days.{Cairo day}.total`) — بث حي،
  /// مع إجمالي الشهر من `total` كعنوان فرعي. عدد المستندات فقط، وليس القيمة.
  /// ليست عدًّا من مجموعة `orders`.
  Widget _buildTodayOrdersCard() {
    const title = 'طلبات اليوم';
    const color = Colors.green;
    const icon = Icons.shopping_cart_checkout_outlined;
    return StreamBuilder<OrderMonthSummary>(
      stream: _todayOrders,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _buildCountCard(
            title: title,
            icon: icon,
            color: color,
            count: 'تعذر التحميل',
            subtitle: 'بتوقيت القاهرة',
            isWide: true,
          );
        }
        final today = snapshot.data?.total ?? 0;
        return StreamBuilder<OrderMonthSummary>(
          stream: _monthOrders,
          builder: (context, monthSnapshot) {
            final monthTotal = monthSnapshot.data?.total ?? 0;
            return _buildCountCard(
              title: title,
              icon: icon,
              color: color,
              count: '$today',
              subtitle: 'الشهر: $monthTotal',
              isWide: true,
            );
          },
        );
      },
    );
  }

  Widget _buildCountCard({
    required String title,
    required IconData icon,
    required Color color,
    required String count,
    bool isWide = false,
    String? subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border(bottom: BorderSide(color: color, width: 4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: isWide ? MainAxisAlignment.spaceAround : MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 30),
          const SizedBox(width: 15),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: Colors.grey, fontSize: 14)),
              Text(
                count,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color),
              ),
              if (subtitle != null)
                Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }
}
