import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:sizer/sizer.dart';
import 'manager_distribution_dialog.dart';
import 'rep_distribution_dialog.dart';
import 'performance_dashboard_screen.dart';
import '../../utils/firestore_error_helpers.dart';
import '../../utils/firestore_helpers.dart';
import '../../utils/staff_display_name.dart';
import '../../utils/target_distribution.dart';

class ManageUsersScreen extends StatefulWidget {
  final FirebaseFirestore? firestore;
  const ManageUsersScreen({super.key, this.firestore});

  @override
  State<ManageUsersScreen> createState() => _ManageUsersScreenState();
}

class _ManageUsersScreenState extends State<ManageUsersScreen> with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _userData;
  TabController? _tabController;
  final Color kPrimaryColor = const Color(0xFF1ABC9C);
  final Color kSidebarColor = const Color(0xFF2F3542);
  List<String> _mySupervisorsIds = [];
  FirebaseFirestore get _db => widget.firestore ?? FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('userData');
    if (data != null) {
      if (mounted) {
        setState(() {
          _userData = jsonDecode(data);
          int tabCount = (_userData?['role'] == 'sales_manager') ? 2 : 1;
          _tabController = TabController(length: tabCount, vsync: this);
        });

        if (_userData?['role'] == 'sales_manager') {
          _fetchSupervisorsList();
        }
      }
    }
  }

  Future<void> _fetchSupervisorsList() async {
    String myDocId = _userData?['docId'] ?? '';
    var snapshot = await _db
        .collection('managers')
        .where('managerId', isEqualTo: myDocId)
        .get();

    if (mounted) {
      setState(() {
        _mySupervisorsIds = snapshot.docs.map((d) => d.id).toList();
      });
    }
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_userData == null || _tabController == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    bool isManager = _userData?['role'] == 'sales_manager';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: Text("إدارة الموظفين والأداء",
            style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold)), // تكبير العنوان
        backgroundColor: Colors.white,
        foregroundColor: kSidebarColor,
        elevation: 0.5,
        bottom: TabBar(
          controller: _tabController,
          labelColor: kPrimaryColor,
          unselectedLabelColor: Colors.grey,
          indicatorColor: kPrimaryColor,
          labelStyle: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold), // تكبير خط التبويبات
          tabs: isManager
              ? [const Tab(text: "المشرفين"), const Tab(text: "جميع المندوبين")]
              : [const Tab(text: "مندوبي المبيعات")],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: isManager
            ? [
                Column(
                  children: [
                    _buildManagerTargetHeader(sourceLabel: 'الإدارة'),
                    Expanded(child: _buildUserList('managers', 'managerId')),
                  ],
                ),
                _buildAllRepsForManager(),
              ]
            : [
                Column(
                  children: [
                    _buildManagerTargetHeader(sourceLabel: 'المدير'),
                    Expanded(child: _buildUserList('salesRep', 'supervisorId')),
                  ],
                ),
              ],
      ),
    );
  }

  Widget _buildAllRepsForManager() {
    if (_mySupervisorsIds.length > 10) return Center(child: Text("عدد المشرفين كبير. راجع التقسيم الإداري.", style: TextStyle(fontSize: 14.sp)));
    if (_mySupervisorsIds.isEmpty) {
      return Center(child: Text("لا يوجد مشرفين تابعين لك حالياً", style: TextStyle(fontSize: 14.sp)));
    }
    return StreamBuilder<QuerySnapshot>(
      stream: _db
          .collection('salesRep')
          .where('supervisorId', whereIn: _mySupervisorsIds)
          .snapshots(),
      builder: (context, snapshot) => _handleStreamResult(snapshot, 'salesRep'),
    );
  }

  Widget _buildUserList(String collectionName, String filterField) {
    String myDocId = _userData?['docId'] ?? '';
    return StreamBuilder<QuerySnapshot>(
      stream: _db
          .collection(collectionName)
          .where(filterField, isEqualTo: myDocId)
          .snapshots(),
      builder: (context, snapshot) => _handleStreamResult(snapshot, collectionName),
    );
  }

  /// بطاقة الهدف المستلم للشهر الحالي: المستلم والموزع والمتبقي لكل
  /// مقياس. قراءة فقط؛ التوزيع يتم من البطاقات. الهدف المالي هنا للمبيعات
  /// فقط ولا يشمل مستهدف الراتب (targetAmount).
  Widget _buildManagerTargetHeader({required String sourceLabel}) {
    final String myDocId = _userData?['docId'] ?? '';
    if (myDocId.isEmpty) return const SizedBox.shrink();
    final String month = targetMonthKey(DateTime.now());
    return StreamBuilder<DocumentSnapshot>(
      stream: _db.collection('managers').doc(myDocId).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Container(
            margin: EdgeInsets.fromLTRB(12.sp, 12.sp, 12.sp, 0),
            padding: EdgeInsets.all(14.sp),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15),
              border: const Border(top: BorderSide(color: Colors.redAccent, width: 4)),
            ),
            child: _queryErrorBody(snapshot.error),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(
              child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator()));
        }
        final data = snapshot.data?.data() as Map<String, dynamic>?;
        final summary = summarizeTargetEntry(data?['targets'], month);
        final bool hasTarget = summary['hasTarget'] as bool;
        final values = summary['values'] as Map<String, double>;
        final distributed = summary['distributed'] as Map<String, double>;
        final remaining =
            remainingTargets(received: values, distributed: distributed);
        String fmt(double v) => v == v.roundToDouble()
            ? v.toInt().toString()
            : v.toStringAsFixed(1);
        return Container(
          margin: EdgeInsets.fromLTRB(12.sp, 12.sp, 12.sp, 0),
          padding: EdgeInsets.all(14.sp),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(15),
            border: Border(top: BorderSide(color: kPrimaryColor, width: 4)),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 4))
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.emoji_events_outlined,
                      color: kPrimaryColor, size: 20.sp),
                  SizedBox(width: 8.sp),
                  Expanded(
                    child: Text("هدفك المستلم من $sourceLabel — $month",
                        style: TextStyle(
                            fontSize: 14.sp,
                            fontWeight: FontWeight.bold,
                            color: kSidebarColor)),
                  ),
                ],
              ),
              SizedBox(height: 4.sp),
              Text("الهدف المالي هنا للمبيعات فقط ولا يشمل مستهدف الراتب.",
                  style: TextStyle(fontSize: 10.sp, color: Colors.grey[600])),
              SizedBox(height: 8.sp),
              if (!hasTarget)
                Text("لم يُسند إليك هدف لهذا الشهر بعد.",
                    style: TextStyle(
                        fontSize: 12.sp,
                        color: Colors.orange[800],
                        fontWeight: FontWeight.bold))
              else
                for (final f in kTargetFields)
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 3.sp),
                    child: Row(
                      children: [
                        Expanded(
                            flex: 3,
                            child: Text(kTargetLabelsAr[f]!,
                                style: TextStyle(
                                    fontSize: 11.sp, color: kSidebarColor))),
                        Expanded(
                            flex: 2,
                            child: Text("مستلم: ${fmt(values[f]!)}",
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 11.sp))),
                        Expanded(
                            flex: 2,
                            child: Text("موزع: ${fmt(distributed[f]!)}",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: 11.sp, color: Colors.teal))),
                        Expanded(
                            flex: 2,
                            child: Text("متبقي: ${fmt(remaining[f]!)}",
                                textAlign: TextAlign.end,
                                style: TextStyle(
                                    fontSize: 11.sp,
                                    fontWeight: FontWeight.bold,
                                    color: remaining[f]! < 0
                                        ? Colors.red
                                        : kSidebarColor))),
                      ],
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }

  void _showDistributeDialog(
      String supervisorId, Map<String, dynamic> supData) {
    final String myDocId = _userData?['docId'] ?? '';
    if (myDocId.isEmpty) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => ManagerDistributionDialog(
        db: _db,
        managerId: myDocId,
        supervisorId: supervisorId,
        supervisorName: staffDisplayName(supData),
        setByUid: myDocId,
      ),
    );
  }

  void _showRepDistributeDialog(String repId, Map<String, dynamic> repData) {
    final String myDocId = _userData?['docId'] ?? '';
    if (myDocId.isEmpty) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => RepDistributionDialog(
        db: _db,
        supervisorId: myDocId,
        repId: repId,
        repName: staffDisplayName(repData),
        setByUid: myDocId,
      ),
    );
  }

  /// Stream failure body: names the real cause (missing index vs rules)
  /// and shows the console "create index" link when Firestore provides one,
  /// so a grey/generic screen becomes an actionable message.
  Widget _queryErrorBody(Object? error) {
    final url = extractFirestoreIndexUrl(error);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.error_outline, color: Colors.redAccent, size: 28.sp),
        SizedBox(height: 8.sp),
        Text(describeQueryErrorAr(error),
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 13.sp,
                fontWeight: FontWeight.bold,
                color: kSidebarColor)),
        if (url != null) ...[
          SizedBox(height: 8.sp),
          SelectableText(url,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.sp, color: Colors.blue)),
        ],
      ],
    );
  }

  Widget _handleStreamResult(AsyncSnapshot<QuerySnapshot> snapshot, String collectionName) {
    if (snapshot.hasError) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(16.sp),
          child: _queryErrorBody(snapshot.error),
        ),
      );
    }
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const Center(child: CircularProgressIndicator());
    }
    var docs = snapshot.data?.docs ?? [];
    // Targets distribution is permanent-only: freelance reps never appear
    // in these lists. Client-side on purpose: legacy docs have no repType
    // field, so a query filter would wrongly drop them (they count as
    // permanent via normalizeRepType).
    if (collectionName == 'salesRep') {
      docs = docs
          .where((d) => isTargetEligible((d.data() as Map<String, dynamic>)['repType']))
          .toList();
    }
    if (docs.isEmpty) return Center(child: Text("لا توجد سجلات حالياً", style: TextStyle(fontSize: 14.sp)));
    
    return ListView.builder(
      padding: EdgeInsets.all(12.sp),
      itemCount: docs.length,
      itemBuilder: (context, index) {
        var data = docs[index].data() as Map<String, dynamic>;
        return _buildUserCard(data, docs[index].id, collectionName);
      },
    );
  }

  Widget _buildUserCard(Map<String, dynamic> data, String docId, String collection) {
    String currentMonth = DateTime.now().toString().substring(0, 7);
    // Hardened: a non-map or mistyped targets/repCode/phone value must never
    // crash the build (grey screen) — fall back to empty/absent instead.
    final targetsRaw = data['targets'];
    bool hasTarget =
        targetsRaw is Map && targetsRaw[currentMonth] != null;
    String targetType = (collection == 'managers') ? 'sales_supervisor' : 'sales';

    return Card(
      elevation: 3,
      margin: EdgeInsets.only(bottom: 15.sp),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PerformanceDashboardScreen(
                targetDocId: docId,
                targetType: targetType,
                targetName: staffDisplayName(data),
                repCode: data['repCode']?.toString(),
              ),
            ),
          );
        },
        child: Padding(
          padding: EdgeInsets.all(15.sp),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(staffDisplayName(data),
                          style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold, color: kSidebarColor)),
                      Text(targetType == 'sales_supervisor' ? "مشرف مبيعات" : "مندوب مبيعات",
                          style: TextStyle(fontSize: 11.sp, color: kPrimaryColor, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  Icon(Icons.analytics_outlined, color: kPrimaryColor, size: 25.sp),
                ],
              ),
              const Divider(height: 25),
              _infoRow(Icons.badge_outlined, "الكود:",
                  (data['repCode'] ?? 'إدارة').toString()),
              _infoRow(Icons.phone_android, "الهاتف:",
                  (data['phone'] ?? '-').toString()),
              const SizedBox(height: 15),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        hasTarget ? Icons.check_circle : Icons.warning_amber_rounded,
                        size: 16.sp,
                        color: hasTarget ? Colors.green : Colors.orange,
                      ),
                      SizedBox(width: 5.sp),
                      Text(hasTarget ? "هدف الشهر محدد" : "لم يحدد هدف",
                          style: TextStyle(fontSize: 12.sp, color: hasTarget ? Colors.green : Colors.orange, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  
                  // التوزيع الهرمي من الهدف المستلم (نفس النمط المعتمد):
                  // المدير يوزع على المشرفين، والمشرف يوزع على مناديبه
                  // الثابتين. النافذة المباشرة القديمة (حقلان + قفل) أُزيلت
                  // لأنها كانت تستبدل قيد الشهر كاملاً.
                  // دفاعياً: لا زر أهداف لمن ليس مؤهلاً لها حتى لو وصل للكارت.
                  if (_userData?['role'] == 'sales_manager' && collection == 'managers')
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.teal,
                        side: const BorderSide(color: Colors.teal),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        padding: EdgeInsets.symmetric(horizontal: 10.sp, vertical: 5.sp),
                      ),
                      onPressed: () => _showDistributeDialog(docId, data),
                      icon: Icon(Icons.pie_chart_outline, size: 14.sp),
                      label: Text("توزيع الهدف", style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.bold)),
                    )
                  else if (_userData?['role'] == 'sales_supervisor' &&
                      collection == 'salesRep' &&
                      isTargetEligible(data['repType']))
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.teal,
                        side: const BorderSide(color: Colors.teal),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        padding: EdgeInsets.symmetric(horizontal: 10.sp, vertical: 5.sp),
                      ),
                      onPressed: () => _showRepDistributeDialog(docId, data),
                      icon: Icon(Icons.pie_chart_outline, size: 14.sp),
                      label: Text("توزيع الهدف", style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4.sp),
      child: Row(
        children: [
          Icon(icon, size: 15.sp, color: Colors.grey[400]),
          SizedBox(width: 8.sp),
          Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 13.sp)),
          SizedBox(width: 6.sp),
          Expanded(
            child: Text(value,
                style: TextStyle(color: kSidebarColor, fontWeight: FontWeight.bold, fontSize: 13.sp),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

}

