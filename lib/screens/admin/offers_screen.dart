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
  // الألوان المعتمدة للهوية البصرية
  final Color kPrimaryColor = const Color(0xFF1ABC9C); // كاش باك
  final Color kGiftColor = const Color(0xFF6C5CE7);    // الهدايا
  final Color kTargetColor = const Color(0xFFE67E22);  // التارجت
  final Color kSidebarColor = const Color(0xFF2F3542);

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F9FD),
        appBar: AppBar(
          title: Text("مركز العروض والجوائز",
              style: TextStyle(fontSize: 22.sp, fontWeight: FontWeight.w900, fontFamily: 'Cairo')),
          centerTitle: true,
          backgroundColor: Colors.white,
          elevation: 0,
          bottom: TabBar(
            indicatorColor: kPrimaryColor,
            labelColor: kPrimaryColor,
            unselectedLabelColor: Colors.grey,
            labelStyle: TextStyle(fontWeight: FontWeight.w900, fontSize: 16.sp),
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

  // --- تبويب الكاش باك المالي ---
  Widget _buildCashbackTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('cashbackRules')
          .where('status', isEqualTo: 'active')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        // فلترة زمنية صارمة لضمان دقة المعلومة للمندوب
        var docs = snapshot.data!.docs.where((doc) {
          var d = doc.data() as Map<String, dynamic>;
          DateTime now = DateTime.now();
          if (d['startDate'] != null && now.isBefore((d['startDate'] as Timestamp).toDate())) return false;
          if (d['endDate'] != null && now.isAfter((d['endDate'] as Timestamp).toDate())) return false;
          return true;
        }).toList();

        // الترتيب حسب الأولوية برمجياً لضمان عدم اختفاء أي قاعدة
        docs.sort((a, b) {
          var aPrio = (a.data() as Map)['priority'] ?? 0;
          var bPrio = (b.data() as Map)['priority'] ?? 0;
          return bPrio.compareTo(aPrio);
        });

        if (docs.isEmpty) return _buildEmptyState("لا توجد قواعد كاش باك حالياً");
        
        return ListView.builder(
          padding: EdgeInsets.all(5.w),
          itemCount: docs.length,
          itemBuilder: (context, index) => _buildCashbackCard(docs[index]),
        );
      },
    );
  }

  // --- كارت الكاش باك (النسخة الصارمة) ---
  Widget _buildCashbackCard(DocumentSnapshot doc) {
    var data = doc.data() as Map<String, dynamic>;
    bool hasTarget = data['targetType'] != 'none' && data['targetType'] != null;
    
    // معالجة القيمة لتكون واضحة وكبيرة جداً للمندوب
    double val = (data['value'] ?? 0).toDouble();
    String valueText = data['type'] == 'percentage' 
        ? (val < 1 ? "${(val * 100).toInt()}%" : "${val.toInt()}%")
        : "${val.toInt()} ج.م";

    return Container(
      margin: EdgeInsets.only(bottom: 2.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12)],
      ),
      child: Column(
        children: [
          // رأس الكارت: يوضح نوع العرض والقيمة بخط كبير جداً
          Container(
            padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 1.5.h),
            decoration: BoxDecoration(
              color: (hasTarget ? kTargetColor : kPrimaryColor).withOpacity(0.1),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _badge(hasTarget ? "عرض بتارجت" : "كاش باك مباشر",
                    hasTarget ? kTargetColor : kPrimaryColor),
                Text(valueText,
                    style: TextStyle(
                        color: hasTarget ? kTargetColor : kPrimaryColor,
                        fontWeight: FontWeight.w900,
                        fontSize: 22.sp)), // خط كبير للقيمة > 18
              ],
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.all(5.w),
            // استخدام اللوجو المدمج في القاعدة مباشرة
            leading: _buildMerchantLogo(data['sellerLogo']),
            title: Text(data['description'] ?? '',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18.sp, color: kSidebarColor)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: 1.5.h),
                _infoRow(Icons.storefront, "التاجر: ${data['sellerName'] ?? 'كل التجار'}", isBold: true),
                if (data['sellerPhone'] != null && data['sellerPhone'] != '')
                  _infoRow(Icons.phone_android, "تواصل: ${data['sellerPhone']}"),
                if (hasTarget)
                  _infoRow(Icons.shopping_bag_outlined, "الشرط: شراء بـ ${data['minPurchaseAmount']} ج.م", color: kTargetColor),
                _infoRow(Icons.event_available, "ينتهي في: ${_formatTS(data['endDate'])}"),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- تبويب الهدايا العينية ---
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
          try {
            return DateTime.parse(d['expiryDate']).isAfter(DateTime.now());
          } catch (e) { return true; }
        }).toList();

        if (docs.isEmpty) return _buildEmptyState("لا توجد هدايا متاحة");
        return ListView.builder(
          padding: EdgeInsets.all(5.w),
          itemCount: docs.length,
          itemBuilder: (context, index) => _buildGiftCard(docs[index]),
        );
      },
    );
  }

  Widget _buildGiftCard(DocumentSnapshot doc) {
    var data = doc.data() as Map<String, dynamic>;
    var trigger = data['trigger'] as Map<String, dynamic>;
    String giftFullName = "${data['giftQuantityPerBase']} ${data['giftUnitName']} من ${data['giftProductName']}";

    return Container(
      margin: EdgeInsets.only(bottom: 2.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12)],
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(vertical: 1.5.h),
            decoration: BoxDecoration(
                color: kGiftColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
            child: Text("عرض هدايا مميز",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 14.sp, fontWeight: FontWeight.w900)),
          ),
          Padding(
            padding: EdgeInsets.all(5.w),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildProductImage(data['imageUrl'] ?? data['giftProductImage']),
                SizedBox(width: 4.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(data['promoName'] ?? '',
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18.sp, color: kSidebarColor)),
                      const Divider(thickness: 1.5),
                      _infoRow(Icons.card_giftcard, "الهدية: $giftFullName", color: kGiftColor, isBold: true),
                      _infoRow(Icons.store, "التاجر: ${data['sellerName'] ?? 'مورد معتمد'}"),
                      _infoRow(Icons.bolt, "الشرط: ${_getTriggerText(trigger)}", color: Colors.redAccent),
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

  // --- دوال المساعدة البصرية ---
  Widget _buildMerchantLogo(String? url) {
    return Container(
      width: 16.w,
      height: 16.w,
      decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.grey.shade100, width: 2)),
      child: (url != null && url.isNotEmpty)
          ? ClipRRect(borderRadius: BorderRadius.circular(100), child: Image.network(url, fit: BoxFit.cover))
          : Icon(Icons.store_mall_directory_outlined, color: Colors.grey, size: 25.sp),
    );
  }

  Widget _buildProductImage(String? url) {
    return Container(
      width: 28.w,
      height: 28.w,
      decoration: BoxDecoration(
          color: const Color(0xFFF1F2F6), borderRadius: BorderRadius.circular(20)),
      child: (url != null && url.isNotEmpty)
          ? ClipRRect(borderRadius: BorderRadius.circular(20), child: Image.network(url, fit: BoxFit.cover))
          : Icon(Icons.redeem_rounded, color: kGiftColor, size: 40.sp),
    );
  }

  Widget _infoRow(IconData icon, String text, {Color color = Colors.blueGrey, bool isBold = false}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 0.8.h),
      child: Row(
        children: [
          Icon(icon, size: 16.sp, color: color),
          SizedBox(width: 3.w),
          Expanded(
              child: Text(text,
                  style: TextStyle(
                      fontSize: 15.sp, // خط واضح جداً للمندوب
                      color: isBold ? Colors.black : kSidebarColor,
                      fontWeight: isBold ? FontWeight.w900 : FontWeight.w700))),
        ],
      ),
    );
  }

  Widget _badge(String text, Color color) {
    return Container(

