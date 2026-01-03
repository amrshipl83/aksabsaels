import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:sizer/sizer.dart';

class OffersScreen extends StatefulWidget {
  const OffersScreen({super.key});

  @override
  State<OffersScreen> createState() => _OffersScreenState();
}

class _OffersScreenState extends State<OffersScreen> {
  final Color kPrimaryColor = const Color(0xFF1ABC9C); // لون الكاش باك
  final Color kGiftColor = const Color(0xFF6C5CE7);    // لون الهدايا
  final Color kTargetColor = const Color(0xFFE67E22);  // لون التارجت

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F6FA),
        appBar: AppBar(
          title: Text("مركز العروض والجوائز", 
              style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
          centerTitle: true,
          backgroundColor: Colors.white,
          elevation: 0.5,
          bottom: TabBar(
            indicatorColor: kPrimaryColor,
            labelColor: kPrimaryColor,
            unselectedLabelColor: Colors.grey,
            tabs: const [
              Tab(text: "كاش باك مالي", icon: Icon(Icons.monetization_on_outlined)),
              Tab(text: "هدايا عينية", icon: Icon(Icons.card_giftcard)),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildCashbackTab(),
            _buildGiftsTab(),
          ],
        ),
      ),
    );
  }

  // --- تبويب الكاش باك ---
  Widget _buildCashbackTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('cashbackRules')
          .where('status', isEqualTo: 'active')
          .orderBy('priority', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        
        var docs = snapshot.data!.docs.where((doc) {
          var d = doc.data() as Map<String, dynamic>;
          Timestamp? end = d['endDate'];
          return end == null || end.seconds > Timestamp.now().seconds;
        }).toList();

        if (docs.isEmpty) return _buildEmptyState("لا توجد قواعد كاش باك نشطة");

        return ListView.builder(
          padding: EdgeInsets.all(12.sp),
          itemCount: docs.length,
          itemBuilder: (context, index) => _buildCashbackCard(docs[index]),
        );
      },
    );
  }

  // --- تبويب الهدايا الترويجية ---
  Widget _buildGiftsTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('giftPromos')
          .where('status', isEqualTo: 'active')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        
        var docs = snapshot.data!.docs.where((doc) {
          var d = doc.data() as Map<String, dynamic>;
          if (d['expiryDate'] == null) return true;
          return DateTime.parse(d['expiryDate']).isAfter(DateTime.now());
        }).toList();

        if (docs.isEmpty) return _buildEmptyState("لا توجد عروض هدايا حالياً");

        return ListView.builder(
          padding: EdgeInsets.all(12.sp),
          itemCount: docs.length,
          itemBuilder: (context, index) => _buildGiftCard(docs[index]),
        );
      },
    );
  }

  // بطاقة الكاش باك
  Widget _buildCashbackCard(DocumentSnapshot doc) {
    var data = doc.data() as Map<String, dynamic>;
    bool hasTarget = data['targetType'] != 'none';
    String valueText = data['type'] == 'percentage' 
        ? "${((data['value'] ?? 0) * 100).toInt()}%" 
        : "${data['value']} ج.م";

    return Card(
      margin: EdgeInsets.only(bottom: 12.sp),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 5.sp),
            decoration: BoxDecoration(
              color: hasTarget ? kTargetColor : kPrimaryColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(hasTarget ? "عرض بتارجت" : "خصم مباشر", 
                  style: TextStyle(color: Colors.white, fontSize: 9.sp, fontWeight: FontWeight.bold)),
                Text(valueText, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12.sp)),
              ],
            ),
          ),
          ListTile(
            title: Text(data['description'] ?? '', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.sp)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _infoRow(Icons.layers, "النطاق: ${_translateAppliesTo(data['appliesTo'])}"),
                if (hasTarget) _infoRow(Icons.shopping_bag, "الشرط: شراء بـ ${data['minPurchaseAmount']} ج.م"),
                _infoRow(Icons.calendar_today, "ينتهي: ${_formatTS(data['endDate'])}"),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // بطاقة الهدايا
  Widget _buildGiftCard(DocumentSnapshot doc) {
    var data = doc.data() as Map<String, dynamic>;
    var trigger = data['trigger'] as Map<String, dynamic>;

    return Card(
      margin: EdgeInsets.only(bottom: 12.sp),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(5.sp),
            decoration: BoxDecoration(color: kGiftColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(15))),
            child: Text("عرض هدايا التاجر", textAlign: TextAlign.center, 
                style: TextStyle(color: Colors.white, fontSize: 9.sp, fontWeight: FontWeight.bold)),
          ),
          Padding(
            padding: EdgeInsets.all(10.sp),
            child: Row(
              children: [
                _buildProductImage(data['giftProductImage']),
                SizedBox(width: 10.sp),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(data['promoName'] ?? '', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.sp)),
                      const Divider(),
                      _infoRow(Icons.card_giftcard, "الهدية: ${data['giftQuantityPerBase']} ${data['giftUnitName']}"),
                      _infoRow(Icons.bolt, "الشرط: ${_getTriggerText(trigger)}"),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // مساعدات الواجهة
  Widget _buildProductImage(String? url) {
    return Container(
      width: 60.sp, height: 60.sp,
      decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(10)),
      child: (url != null && url.isNotEmpty)
          ? ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.network(url, fit: BoxFit.cover))
          : Icon(Icons.redeem, color: kGiftColor, size: 30.sp),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 2.sp),
      child: Row(
        children: [
          Icon(icon, size: 10.sp, color: Colors.grey[600]),
          SizedBox(width: 5.sp),
          Expanded(child: Text(text, style: TextStyle(fontSize: 9.sp, color: Colors.black87))),
        ],
      ),
    );
  }

  String _getTriggerText(Map trigger) {
    if (trigger['type'] == 'min_order') return "طلب بـ ${trigger['value']} ج.م";
    return "شراء ${trigger['triggerQuantityBase']} من ${trigger['productName']}";
  }

  String _translateAppliesTo(String? val) {
    if (val == 'all') return "المنصة بالكامل";
    if (val == 'seller') return "تاجر محدد";
    return "قسم محدد";
  }

  String _formatTS(dynamic ts) => ts != null ? DateFormat('yyyy/MM/dd').format(ts.toDate()) : "غير محدد";

  Widget _buildEmptyState(String msg) => Center(child: Text(msg, style: const TextStyle(color: Colors.grey)));
}

