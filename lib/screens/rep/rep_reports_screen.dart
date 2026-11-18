import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../utils/client_counts.dart';
import '../../utils/order_counts.dart';

const Color kPrimaryColor = Color(0xFF43B97F);
const Color kSecondaryColor = Color(0xFF1A2C3D);
const Color kBgColor = Color(0xFFf0f2f5);

class RepReportsScreen extends StatefulWidget {
  const RepReportsScreen({super.key});

  @override
  State<RepReportsScreen> createState() => _RepReportsScreenState();
}

class _RepReportsScreenState extends State<RepReportsScreen> {
  Map<String, dynamic>? repData;
  bool _isLoading = true;
  double totalSales = 0.0;
  Map<String, double> salesByStatus = {};
  Map<String, int> ordersCountByStatus = {};
  String _selectedFilter = 'month';

  @override
  void initState() {
    super.initState();
    _loadRepDataAndOrders();
  }

  Future<void> _loadRepDataAndOrders() async {
    final prefs = await SharedPreferences.getInstance();
    final userDataString = prefs.getString('userData');
    if (userDataString != null) {
      repData = jsonDecode(userDataString);
      await _fetchOrders();
    }
  }

  // KPIs come ONLY from the unified `salesRep.ordersByMonth` aggregates
  // (nested backend buckets: new/delivered/cancelled + delivered.value).
  // No `orders` collection reads here; day/month/all all resolve from the
  // single salesRep doc with Cairo keys. Raw order docs stay readable in
  // the detail screens (my_orders, sales_orders_report).
  Future<void> _fetchOrders() async {
    setState(() => _isLoading = true);
    try {
      final repCode = repData?['repCode']?.toString() ?? '';
      final monthKey = clientCountMonthKey();
      final dayKey = clientCountDayKey();

      OrderMonthSummary summary = const OrderMonthSummary();
      double periodSales = 0;
      if (repCode.isNotEmpty) {
        final snap = await FirebaseFirestore.instance
            .collection('salesRep')
            .where('repCode', isEqualTo: repCode)
            .limit(1)
            .get();
        if (snap.docs.isNotEmpty) {
          final data = snap.docs.first.data();
          if (_selectedFilter == 'day') {
            summary = repOrderDaySummary(data, monthKey, dayKey);
            final daily = orderDailyDeliveredValues(data, monthKey);
            final dayNum = int.tryParse(
                dayKey.length >= 10 ? dayKey.substring(8, 10) : '');
            periodSales = (dayNum == null) ? 0 : (daily[dayNum] ?? 0);
          } else if (_selectedFilter == 'all') {
            summary = sumAllTimeOrderSummary(data);
            periodSales = summary.deliveredValue;
          } else {
            summary = repOrderMonthSummary(data, monthKey);
            periodSales = summary.deliveredValue;
          }
        }
      }

      // Status breakdown mirrors the backend's three tracked buckets.
      // Only `delivered` carries money; new/cancelled rows show 0.
      final Map<String, double> tempStatusSales = {};
      final Map<String, int> tempStatusCount = {};
      void putBucket(String key, int count, double value) {
        if (count <= 0) return;
        tempStatusCount[key] = count;
        tempStatusSales[key] = value;
      }

      putBucket('new', summary.fresh, 0);
      putBucket('delivered', summary.delivered, periodSales);
      putBucket('cancelled', summary.cancelled, 0);

      setState(() {
        totalSales = periodSales;
        salesByStatus = tempStatusSales;
        ordersCountByStatus = tempStatusCount;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Error fetching reports: $e");
      setState(() => _isLoading = false);
    }
  }

  Future<void> _generatePdf() async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.almaraiRegular();
    final boldFont = await PdfGoogleFonts.almaraiBold();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('تقارير المندوب',
                      style: pw.TextStyle(font: boldFont, fontSize: 18, color: PdfColors.green)),
                  pw.Text(DateTime.now().toString().substring(0, 10),
                      style: pw.TextStyle(font: font, fontSize: 12)),
                ],
              ),
              pw.Divider(thickness: 2, color: PdfColors.grey300),
              pw.SizedBox(height: 20),
              pw.Text('اسم المندوب: ${repData?['fullname']}', style: pw.TextStyle(font: font, fontSize: 14)),
              pw.Text('كود المندوب: ${repData?['repCode']}', style: pw.TextStyle(font: font, fontSize: 14)),
              pw.SizedBox(height: 20),
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: const pw.BoxDecoration(color: PdfColors.green50),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('إجمالي مبيعات الفترة:', style: pw.TextStyle(font: boldFont, fontSize: 16)),
                    pw.Text('${totalSales.toStringAsFixed(2)} ج.م',
                        style: pw.TextStyle(font: boldFont, fontSize: 16, color: PdfColors.green)),
                  ],
                ),
              ),
              pw.SizedBox(height: 30),
              pw.Text('تفصيل المبيعات حسب الحالة:', style: pw.TextStyle(font: boldFont, fontSize: 14)),
              pw.SizedBox(height: 10),
              pw.TableHelper.fromTextArray(
                cellStyle: pw.TextStyle(font: font),
                headerStyle: pw.TextStyle(font: boldFont, color: PdfColors.white),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
                cellAlignment: pw.Alignment.centerRight,
                data: <List<String>>[
                  ['الحالة', 'عدد الطلبات', 'القيمة الإجمالية'],
                  ...salesByStatus.entries.map((e) => [
                        e.key,
                        ordersCountByStatus[e.key].toString(),
                        '${e.value.toStringAsFixed(2)} ج.م'
                      ]),
                ],
              ),
            ],
          );
        },
      ),
    );
    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: kBgColor,
        appBar: AppBar(
          title: const Text('تقارير أدائي', style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: Colors.white,
          foregroundColor: kSecondaryColor,
          elevation: 0.5,
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.picture_as_pdf, color: Colors.redAccent),
              onPressed: totalSales > 0 ? _generatePdf : null,
            )
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              _buildFilterTabs(),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: kPrimaryColor))
                    : RefreshIndicator(
                        onRefresh: _fetchOrders,
                        child: SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              _buildTotalCard(),
                              const SizedBox(height: 20),
                              if (salesByStatus.isNotEmpty) ...[
                                _buildStatusChartSection(),
                                const SizedBox(height: 20),
                                _buildStatusTable(),
                              ] else
                                _buildNoDataState(),
                            ],
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterTabs() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _filterButton('اليوم', 'day'),
          _filterButton('الشهر', 'month'),
          _filterButton('الكل', 'all'),
        ],
      ),
    );
  }

  Widget _filterButton(String title, String value) {
    bool isSelected = _selectedFilter == value;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedFilter = value;
        });
        _fetchOrders();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? kPrimaryColor : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(title,
            style: TextStyle(
                color: isSelected ? Colors.white : Colors.grey, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildTotalCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [kPrimaryColor, Color(0xFF34A36D)]),
        borderRadius: BorderRadius.circular(15),
        boxShadow: [BoxShadow(color: kPrimaryColor.withOpacity(0.3), blurRadius: 10)],
      ),
      child: Column(
        children: [
          const Text('إجمالي المبيعات', style: TextStyle(color: Colors.white, fontSize: 16)),
          const SizedBox(height: 10),
          Text(
            '${totalSales.toStringAsFixed(2)} ج.م',
            style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChartSection() {
    // Distribution over the three tracked buckets (counts, not money:
    // only delivered carries a value in the backend).
    final chartTotal = ordersCountByStatus.values.fold<int>(0, (sum, value) => sum + value);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
      child: Column(
        children: [
          const Text('توزيع الحالات', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 20),
          ...ordersCountByStatus.entries.map((entry) {
            final percentage = chartTotal == 0 ? 0.0 : entry.value / chartTotal;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: _getStatusColor(entry.key),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(entry.key)),
                      Text('${(percentage * 100).toStringAsFixed(0)}%'),
                    ],
                  ),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: percentage,
                      minHeight: 8,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: AlwaysStoppedAnimation<Color>(_getStatusColor(entry.key)),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildStatusTable() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
      child: DataTable(
        columnSpacing: 15,
        horizontalMargin: 10,
        columns: const [
          DataColumn(label: Text('الحالة')),
          DataColumn(label: Text('الطلبات')),
          DataColumn(label: Text('الإجمالي')),
        ],
        rows: salesByStatus.entries.map((entry) {
          return DataRow(cells: [
            DataCell(Text(entry.key, style: const TextStyle(fontSize: 12))),
            DataCell(Text(ordersCountByStatus[entry.key].toString())),
            DataCell(Text('${entry.value.toStringAsFixed(0)} ج.م',
                style: const TextStyle(fontWeight: FontWeight.bold))),
          ]);
        }).toList(),
      ),
    );
  }

  Widget _buildNoDataState() {
    return Padding(
      padding: const EdgeInsets.only(top: 50),
      child: Column(
        children: [
          const Icon(Icons.insert_chart_outlined, size: 80, color: Colors.grey),
          const SizedBox(height: 10),
          const Text("لا توجد مبيعات مسجلة لهذه الفترة", style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 20),
          TextButton(
            onPressed: () {
              setState(() => _selectedFilter = 'all');
              _fetchOrders();
            },
            child: const Text("عرض كل المبيعات", style: TextStyle(color: kPrimaryColor)),
          )
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'delivered':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      case 'processing':
        return Colors.orange;
      default:
        return Colors.blue;
    }
  }
}