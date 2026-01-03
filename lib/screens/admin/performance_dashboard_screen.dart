import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:sizer/sizer.dart';

class PerformanceDashboardScreen extends StatefulWidget {
  final String targetDocId;
  final String targetType;
  final String targetName;
  final String? repCode;

  const PerformanceDashboardScreen({
    super.key,
    required this.targetDocId,
    required this.targetType,
    required this.targetName,
    this.repCode,
  });

  @override
  State<PerformanceDashboardScreen> createState() => _PerformanceDashboardScreenState();
}

class _PerformanceDashboardScreenState extends State<PerformanceDashboardScreen> {
  DateTime _startDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _endDate = DateTime.now();
  bool _isLoading = true;

  double totalSales = 0;
  int totalOrders = 0;
  int activeCustomers = 0;
  double workingHours = 0;
  int executedVisits = 0; // حقل الزيارات الجديد
  Map<String, dynamic> targets = {};

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      List<String> codesToQuery = [];

      // 1. تحديد الـ repCodes المطلوبة
      if (widget.targetType == 'sales_supervisor') {
        var reps = await FirebaseFirestore.instance
            .collection('salesRep')
            .where('supervisorId', isEqualTo: widget.targetDocId)
            .get();
        codesToQuery = reps.docs.map((d) => d['repCode']?.toString() ?? '').toList();

        var supervisorDoc = await FirebaseFirestore.instance.collection('managers').doc(widget.targetDocId).get();
        targets = supervisorDoc.data()?['targets'] ?? {};
      } else {
        codesToQuery = [widget.repCode ?? ''];
        var repDoc = await FirebaseFirestore.instance.collection('salesRep').doc(widget.targetDocId).get();
        targets = repDoc.data()?['targets'] ?? {};
      }

      if (codesToQuery.isNotEmpty) {
        // 2. جلب الأوردرات والمبيعات
        var orders = await FirebaseFirestore.instance
            .collection('orders')
            .where('buyer.repCode', whereIn: codesToQuery)
            .where('orderDate', isGreaterThanOrEqualTo: Timestamp.fromDate(_startDate))
            .where('orderDate', isLessThanOrEqualTo: Timestamp.fromDate(_endDate.add(const Duration(days: 1))))
            .get();

        double salesSum = 0;
        Set<String> buyersSet = {};
        for (var doc in orders.docs) {
          salesSum += (doc['total'] ?? 0).toDouble();
          if (doc['buyer']?['id'] != null) buyersSet.add(doc['buyer']['id']);
        }

        // 3. جلب الزيارات المنفذة (من كولكشن visits)
        var visits = await FirebaseFirestore.instance
            .collection('visits')
            .where('repCode', whereIn: codesToQuery)
            .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(_startDate))
            .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(_endDate.add(const Duration(days: 1))))
            .get();

        // 4. جلب ساعات العمل (daily_logs)
        // ملاحظة: الـ daily_logs تستخدم repCode المندوب الفردي غالباً
        var logs = await FirebaseFirestore.instance
            .collection('daily_logs')
            .where('repCode', whereIn: codesToQuery)
            .where('startTime', isGreaterThanOrEqualTo: Timestamp.fromDate(_startDate))
            .get();

        double hours = 0;
        for (var log in logs.docs) {
          var data = log.data();
          if (data['startTime'] != null && data['endTime'] != null) {
            DateTime start = (data['startTime'] as Timestamp).toDate();
            DateTime end = (data['endTime'] as Timestamp).toDate();
            hours += end.difference(start).inMinutes / 60;
          }
        }

        if (mounted) {
          setState(() {
            totalSales = salesSum;
            totalOrders = orders.docs.length;
            activeCustomers = buyersSet.length;
            executedVisits = visits.docs.length;
            workingHours = hours;
          });
        }
      }
    } catch (e) {
      debugPrint("Error fetching performance: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    String currentMonth = DateFormat('yyyy-MM').format(_startDate);
    var currentTarget = targets[currentMonth] ?? {};

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: Text("أداء ${widget.targetName}", style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold)),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF2F3542),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1ABC9C)))
          : SingleChildScrollView(
              padding: EdgeInsets.all(12.sp),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDateFilter(),
                  SizedBox(height: 3.h),
                  Text("مؤشرات الأداء الرئيسية (KPIs)",
                      style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                  SizedBox(height: 2.h),
                  _buildKpiGrid(currentTarget),
                ],
              ),
            ),
    );
  }

  Widget _buildDateFilter() {
    return Container(
      padding: EdgeInsets.all(12.sp),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _dateTile("من تاريخ", _startDate, (date) {
            if (date != null) {
              setState(() => _startDate = date);
              _fetchData();
            }
          }),
          Container(width: 1, height: 30, color: Colors.grey[200]),
          _dateTile("إلى تاريخ", _endDate, (date) {
            if (date != null) {
              setState(() => _endDate = date);
              _fetchData();
            }
          }),
          CircleAvatar(
            backgroundColor: const Color(0xFF1ABC9C).withOpacity(0.1),
            child: IconButton(
              icon: Icon(Icons.refresh, color: const Color(0xFF1ABC9C), size: 15.sp),
              onPressed: _fetchData,
            ),
          )
        ],
      ),
    );
  }

  Widget _dateTile(String label, DateTime date, Function(DateTime?) onSelect) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date,
          firstDate: DateTime(2025),
          lastDate: DateTime(2030),
        );
        onSelect(picked);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 9.sp, color: Colors.grey)),
          Text(DateFormat('yyyy-MM-dd').format(date),
              style: TextStyle(fontSize: 10.sp, fontWeight: FontWeight.bold, color: const Color(0xFF2F3542))),
        ],
      ),
    );
  }

  Widget _buildKpiGrid(Map<String, dynamic> currentTarget) {
    double financialGoal = (currentTarget['financialTarget'] ?? 0).toDouble();
    double visitsGoal = (currentTarget['visitsTarget'] ?? 0).toDouble();

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 12.sp,
      crossAxisSpacing: 12.sp,
      childAspectRatio: 0.85, // تعديل بسيط ليتناسب مع الخط الكبير
      children: [
        _kpiCard("إجمالي المبيعات", totalSales, financialGoal, isCurrency: true),
        _kpiCard("الزيارات المنفذة", executedVisits.toDouble(), visitsGoal, unit: "زيارة"),
        _kpiCard("عدد الأوردرات", totalOrders.toDouble(), 0),
        _kpiCard("عملاء فعالين", activeCustomers.toDouble(), 0),
        _kpiCard("ساعات العمل", workingHours, 0, unit: "ساعة"),
      ],
    );
  }

  Widget _kpiCard(String title, double actual, double goal, {bool isCurrency = false, String unit = ''}) {
    double percentage = (goal > 0) ? (actual / goal) : 0;
    double displayProgress = percentage > 1 ? 1.0 : percentage;

    return Container(
      padding: EdgeInsets.all(12.sp),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 15, offset: const Offset(0, 5))],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(title, style: TextStyle(fontSize: 10.sp, color: Colors.blueGrey, fontWeight: FontWeight.w500)),
          SizedBox(height: 8.sp),
          FittedBox(
            child: Text(
              isCurrency ? "${NumberFormat("#,###").format(actual)} ج.م" : "${actual.toStringAsFixed(1)} $unit",
              style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w900, color: const Color(0xFF1ABC9C)),
            ),
          ),
          if (goal > 0) ...[
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("الهدف: ${goal.toInt()}", style: TextStyle(fontSize: 8.sp, color: Colors.grey)),
                Text("${(percentage * 100).toInt()}%",
                    style: TextStyle(
                        fontSize: 9.sp,
                        fontWeight: FontWeight.bold,
                        color: percentage >= 1 ? Colors.green : Colors.orange)),
              ],
            ),
            SizedBox(height: 5.sp),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: displayProgress,
                backgroundColor: Colors.grey[100],
                valueColor: AlwaysStoppedAnimation<Color>(percentage >= 1 ? Colors.green : const Color(0xFF1ABC9C)),
                minHeight: 6.sp,
              ),
            ),
          ]
        ],
      ),
    );
  }
}

