import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:sizer/sizer.dart';
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import '../../utils/geo_areas.dart';
import '../../utils/rep_location.dart';
import '../../utils/gift_eligibility.dart';
import '../../utils/bundle_eligibility.dart';

class OffersScreen extends StatefulWidget {
  const OffersScreen({super.key});

  @override
  State<OffersScreen> createState() => _OffersScreenState();
}

class _OffersScreenState extends State<OffersScreen> {
  // الألوان المعتمدة للهوية البصرية
  final Color kPrimaryColor = const Color(0xFF1ABC9C); // كاش باك
  final Color kGiftColor = const Color(0xFF6C5CE7);    // الهدايا
  final Color kBundleColor = const Color(0xFF0984E3);  // البنادل
  final Color kTargetColor = const Color(0xFFE67E22);  // التارجت
  final Color kSidebarColor = const Color(0xFF2F3542);

  // --- حالة الفلترة الجغرافية (BUYER productOffers context) ---
  // نفس القواعد الأصلية: مناطق العرض (deliveryZones أولًا ثم deliveryAreas)،
  // المضلعات من ملف GeoJSON، بلا موقع صالح = العروض العامة فقط.
  Map<String, List<List<AreaPoint>>> _areaPolygons = {};
  // صناديق الإحاطة المبنية مرة واحدة (نفس قرار BUYER، بدون تغيير النتيجة).
  Map<String, GeoBBox> _areaBoxes = {};
  // مستندات التجار النشطين (sellers) — المرجع الحي للمناطق والتغطية.
  Map<String, Map<String, dynamic>> _sellerDocs = {};
  double? _repLat;
  double? _repLng;
  bool _geoReady = false;
  bool _repHasFix = false;
  // Cached gift-offer fetch, keyed by the needed ids: avoids refetching
  // the same productOffers on every unrelated rebuild.
  String _giftIdsKey = '';
  Future<Map<String, Map<String, dynamic>>>? _giftOffersFuture;

  @override
  void initState() {
    super.initState();
    _initGeo();
  }

  /// تحميل المضلعات + آخر موقع مؤكد للمندوب + مناطق التجار الحية.
  /// قراءة فقط؛ أي فشل يبقي العروض العامة ظاهرة ولا يخفيها.
  Future<void> _initGeo() async {
    try {
      final String jsonString = await rootBundle
          .loadString('assets/OSMB-bc319d822a17aa9ad1089fc05e7d4e752460f877.geojson');
      _areaPolygons = parseAreaPolygons(json.decode(jsonString));
      _areaBoxes = buildAreaBBoxes(_areaPolygons);
    } catch (_) {}
    try {
      final repCode = await readStoredRepCode();
      if (repCode != null && repCode.isNotEmpty) {
        final point = await fetchUnifiedRepPoint(
            FirebaseFirestore.instance, repCode);
        if (point != null) {
          _repLat = point.lat;
          _repLng = point.lng;
          _repHasFix = true;
        }
      }
    } catch (_) {}
    // مستندات التجار النشطين (المرجع الحي للمناطق والتغطية).
    try {
      final sellers = await FirebaseFirestore.instance
          .collection('sellers')
          .where('status', isEqualTo: 'active')
          .get();
      for (final doc in sellers.docs) {
        _sellerDocs[doc.id] = doc.data();
      }
    } catch (_) {}
    if (mounted) setState(() => _geoReady = true);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
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
            labelStyle: TextStyle(fontWeight: FontWeight.w900, fontSize: 15.sp),
            tabs: const [
              Tab(text: "كاش باك مالي", icon: Icon(Icons.monetization_on)),
              Tab(text: "هدايا عينية", icon: Icon(Icons.card_giftcard)),
              Tab(text: "بنادل", icon: Icon(Icons.inventory_2_outlined)),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildCashbackTab(),
            _buildGiftsTab(),
            _buildBundlesTab(),
          ],
        ),
      ),
    );
  }

  // --- تبويب الكاش باك المالي (مؤقتًا بلا فلترة جغرافية) ---
  // ملاحظة: وثائق cashbackRules لا تحمل sellerId/مناطق مثبتة، لذا يُترك
  // التبويب كما هو عمدًا ولا يُدَّعى أنه مفلتر جغرافيًا (فجوة معلنة).
  Widget _buildCashbackTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('cashbackRules')
          .where('status', isEqualTo: 'active')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        var docs = snapshot.data!.docs.where((doc) {
          var d = doc.data() as Map<String, dynamic>;
          DateTime now = DateTime.now();
          if (d['startDate'] != null && now.isBefore((d['startDate'] as Timestamp).toDate())) return false;
          if (d['endDate'] != null && now.isAfter((d['endDate'] as Timestamp).toDate())) return false;
          return true;
        }).toList();

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

  Widget _buildCashbackCard(DocumentSnapshot doc) {
    var data = doc.data() as Map<String, dynamic>;
    bool hasTarget = data['targetType'] != 'none' && data['targetType'] != null;

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
                        fontSize: 22.sp)),
              ],
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.all(5.w),
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

  /// أهلية الهدية الكاملة (BUYER GiftEligibilityService):
  /// حياة العرض (status/expiry/budget — والمنتهي غير القابل للتحليل مرفوض)،
  /// sellerId صالح ومستند مقروء، تغطية التاجر الحية لمناطق المستند،
  /// صلاحية عرض الهدية، وصلاحية عروض كل سطر محفز. بطاقة العرض ثابتة.
  bool _isGiftEligible(
    String promoId,
    Map<String, dynamic> promo,
    Map<String, Map<String, dynamic>> offers,
    DateTime now,
  ) {
    if (!isGiftPromoLive(promo, now)) return false;
    final sellerId = (promo['sellerId']?.toString() ?? '').trim();
    if (sellerId.isEmpty) return false;
    final sellerDoc = _sellerDocs[sellerId];
    if (sellerDoc == null) return false;
    final sellerZones = (sellerDoc['deliveryAreas'] is List)
        ? (sellerDoc['deliveryAreas'] as List).whereType<String>().toList()
        : const <String>[];
    if (!isOfferVisibleByCoords(
      offerData: <String, dynamic>{'deliveryAreas': sellerZones},
      lat: _repLat,
      lng: _repLng,
      areaPolygons: _areaPolygons,
      bboxes: _areaBoxes,
    )) {
      return false;
    }
    final giftOfferId = (promo['giftOfferId']?.toString() ?? '').trim();
    if (giftOfferId.isEmpty) return false;
    final giftDoc = offers[giftOfferId];
    if (giftDoc == null || !isOfferActive(giftDoc)) return false;
    final trigger = promo['trigger'];
    final triggerMap =
        trigger is Map ? Map<String, dynamic>.from(trigger) : <String, dynamic>{};
    if (triggerMap['type'] == 'min_order') return true;
    final lines = giftTriggerLines(promo);
    if (lines.isEmpty) return false;
    for (final line in lines) {
      final offerId = (line['offerId']?.toString() ?? '').trim();
      if (offerId.isEmpty) return false;
      final offerDoc = offers[offerId];
      if (offerDoc == null || !isOfferActive(offerDoc)) return false;
      if (((line['triggerQuantityBase'] as num?)?.toInt() ?? 0) <= 0) {
        return false;
      }
    }
    return true;
  }

  /// يجمع معرفات عروض المنتجات اللازمة لفحص الهدايا (الهدية + المحفزات).
  Set<String> _collectGiftOfferIds(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> promos) {
    final ids = <String>{};
    for (final doc in promos) {
      final data = doc.data();
      final giftId = (data['giftOfferId']?.toString() ?? '').trim();
      if (giftId.isNotEmpty) ids.add(giftId);
      for (final line in giftTriggerLines(data)) {
        final oid = (line['offerId']?.toString() ?? '').trim();
        if (oid.isNotEmpty) ids.add(oid);
      }
    }
    return ids;
  }

  /// جلب عروض المنتجات المرتبطة بالهدايا (قراءة فقط، دفعة واحدة).
  Future<Map<String, Map<String, dynamic>>> _fetchOfferDocs(
      Set<String> ids) async {
    final out = <String, Map<String, dynamic>>{};
    if (ids.isEmpty) return out;
    final snaps = await Future.wait(
        ids.map((id) => FirebaseFirestore.instance.collection('productOffers').doc(id).get()));
    for (final s in snaps) {
      if (s.exists && s.data() != null) out[s.id] = s.data()!;
    }
    return out;
  }

  Widget _buildGiftsTab() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('giftPromos')
          .where('status', isEqualTo: 'active')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || !_geoReady) {
          return const Center(child: CircularProgressIndicator());
        }
        final promos = snapshot.data!.docs;
        final ids = _collectGiftOfferIds(promos);
        final key = (ids.toList()..sort()).join(',');
        if (_giftOffersFuture == null || _giftIdsKey != key) {
          _giftIdsKey = key;
          _giftOffersFuture = _fetchOfferDocs(ids);
        }
        return FutureBuilder<Map<String, Map<String, dynamic>>>(
          future: _giftOffersFuture,
          builder: (context, osnap) {
            if (!osnap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final now = DateTime.now();
            final docs = promos
                .where((doc) =>
                    _isGiftEligible(doc.id, doc.data(), osnap.data!, now))
                .toList();

            if (docs.isEmpty) {
              return _repHasFix
                  ? _buildEmptyState("لا توجد هدايا متاحة في نطاقك حاليًا")
                  : _buildEmptyState(
                      "الموقع غير متاح — تُعرض الهدايا العامة فقط ولا توجد حاليًا");
            }
            return Column(
              children: [
                if (!_repHasFix) _buildNoLocationBanner(),
                Expanded(
                  child: ListView.builder(
                    padding: EdgeInsets.all(5.w),
                    itemCount: docs.length,
                    itemBuilder: (context, index) => _buildGiftCard(docs[index]),
                  ),
                ),
              ],
            );
          },
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

  // --- تبويب البنادل: sellerBundles النشطة بفلترة BUYER ---
  // نفس منطق loadActiveBundlesForBuyer: الوحدات القابلة للبيع أولًا، ثم
  // مناطق التاجر الحية هي المرجع، ولقطة البندل احتياطي فقط عند غياب
  // مستند التاجر أو فراغ مناطقه الحية (ليست القائمة الفارغة تغطية عامة).
  List<String> _liveBundleZones(
      String sellerId, Map<String, dynamic> bundleData) {
    final sellerDoc = _sellerDocs[sellerId];
    if (sellerDoc != null) {
      final raw = sellerDoc['deliveryAreas'];
      if (raw is List && raw.isNotEmpty) {
        return raw.whereType<String>().toList();
      }
    }
    final fallback = readOfferZones(bundleData);
    return fallback;
  }

  Widget _buildBundlesTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('sellerBundles')
          .where('status', isEqualTo: 'active')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || !_geoReady) {
          return const Center(child: CircularProgressIndicator());
        }
        final visible = <DocumentSnapshot>[];
        for (final doc in snapshot.data!.docs) {
          final data = doc.data() as Map<String, dynamic>;
          if (bundleSellableNow(data) <= 0) continue;
          final sellerId = data['sellerId']?.toString() ?? '';
          final zones = _liveBundleZones(sellerId, data);
          if (isOfferVisibleByCoords(
            offerData: <String, dynamic>{'deliveryZones': zones},
            lat: _repLat,
            lng: _repLng,
            areaPolygons: _areaPolygons,
            bboxes: _areaBoxes,
          )) {
            visible.add(doc);
          }
        }

        if (visible.isEmpty) {
          return _repHasFix
              ? _buildEmptyState("لا توجد بنادل متاحة في نطاقك حاليًا")
              : _buildEmptyState("الموقع غير متاح — تُعرض البنادل العامة فقط ولا توجد حاليًا");
        }
        return Column(
          children: [
            if (!_repHasFix) _buildNoLocationBanner(),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.all(5.w),
                itemCount: visible.length,
                itemBuilder: (context, index) => _buildBundleCard(visible[index]),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBundleCard(DocumentSnapshot doc) {
    var data = doc.data() as Map<String, dynamic>;
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
                color: kBundleColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
            child: Text("بندل مميز",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 14.sp, fontWeight: FontWeight.w900)),
          ),
          Padding(
            padding: EdgeInsets.all(5.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(data['description']?.toString() ?? '',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18.sp, color: kSidebarColor)),
                const Divider(thickness: 1.5),
                _infoRow(Icons.store, "التاجر: ${data['sellerName'] ?? 'مورد معتمد'}", isBold: true),
                if (data['sellerPhone'] != null && data['sellerPhone'].toString().isNotEmpty)
                  _infoRow(Icons.phone_android, "تواصل: ${data['sellerPhone']}"),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoLocationBanner() {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.fromLTRB(5.w, 2.h, 5.w, 0),
      padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 1.5.h),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.location_off_outlined, color: Colors.amber.shade800),
          SizedBox(width: 3.w),
          Expanded(
            child: Text("تعذر تحديد موقعك — تُعرض العروض العامة فقط.",
                style: TextStyle(fontSize: 14.sp, color: Colors.amber.shade900)),
          ),
        ],
      ),
    );
  }

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
                      fontSize: 15.sp,
                      color: isBold ? Colors.black : kSidebarColor,
                      fontWeight: isBold ? FontWeight.w900 : FontWeight.w700))),
        ],
      ),
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 0.8.h),
      decoration: BoxDecoration(
          color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
      child: Text(text,
          style: TextStyle(color: color, fontSize: 13.sp, fontWeight: FontWeight.w900)),
    );
  }

  String _getTriggerText(Map trigger) {
    if (trigger['type'] == 'min_order') return "طلب بـ ${trigger['value']} ج.م";
    return "شراء ${trigger['triggerQuantityBase']} من ${trigger['productName']}";
  }

  String _formatTS(dynamic ts) =>
      ts != null ? DateFormat('yyyy/MM/dd').format(ts.toDate()) : "مفتوح";

  Widget _buildEmptyState(String msg) => Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.layers_clear_outlined, size: 60.sp, color: Colors.grey.shade300),
        SizedBox(height: 2.h),
        Text(msg, style: TextStyle(color: Colors.grey, fontSize: 16.sp, fontWeight: FontWeight.bold))
      ]));
}
