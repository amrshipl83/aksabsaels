import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'RepTraderOffersScreen.dart';
import '../../utils/geo_areas.dart';
import '../../utils/offer_pricing.dart';
import '../../utils/rep_location.dart';

class RepTradersLiteScreen extends StatefulWidget {
  const RepTradersLiteScreen({super.key});

  @override
  State<RepTradersLiteScreen> createState() => _RepTradersLiteScreenState();
}

class _RepTradersLiteScreenState extends State<RepTradersLiteScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  String _searchQuery = '';
  String _currentFilter = 'all';
  List<DocumentSnapshot> _activeSellers = [];
  List<DocumentSnapshot> _filteredTraders = [];
  List<String> _categories = [];
  bool _isLoading = true;

  // Unified rep position (newest visit by startTime, else workday start).
  // null = unknown location: only global sellers are shown, never guesses.
  double? _repLat;
  double? _repLng;
  bool _repHasFix = false;
  Map<String, List<List<AreaPoint>>> _areaCoordinatesMap = {};
  Map<String, GeoBBox> _areaBoxes = {};

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    await _fetchAndProcessGeoJson();
    _areaBoxes = buildAreaBBoxes(_areaCoordinatesMap);
    try {
      final repCode = await readStoredRepCode();
      if (repCode != null && repCode.isNotEmpty) {
        final point = await fetchUnifiedRepPoint(_db, repCode);
        if (point != null) {
          _repLat = point.lat;
          _repLng = point.lng;
          _repHasFix = true;
        }
      }
    } catch (_) {}
    await _loadTraders();
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _fetchAndProcessGeoJson() async {
    try {
      final String jsonString = await rootBundle.loadString('assets/OSMB-bc319d822a17aa9ad1089fc05e7d4e752460f877.geojson');
      final data = json.decode(jsonString);
      _areaCoordinatesMap = parseAreaPolygons(data);
      if (_areaCoordinatesMap.isEmpty) debugPrint('GeoAreas: no valid polygons parsed');
    } catch (e) { debugPrint("GeoJSON Error: $e"); }
  }

  /// Supplier list filtered like BUYER TradersScreen:
  /// 1. sellers with at least one active, geo-visible productOffer win;
  /// 2. if that offers read fails, fall back to the seller's own coverage
  ///    (empty zones = global; unknown location = globals only).
  /// Identity is the seller document id only — never the name.
  Future<void> _loadTraders() async {
    try {
      Set<String> visibleIds = {};
      var offersCheckOk = false;
      try {
        final offersSnap = await _db
            .collection('productOffers')
            .where('status', isEqualTo: 'active')
            .get();
        visibleIds = visibleOfferSellerIdsByCoords(
          // Priced offers only (mirrors BUYER traders_screen): a seller
          // with no purchasable offer must not appear in the store.
          offerDocs: offersSnap.docs
              .map((d) => d.data() as Map<String, dynamic>)
              .where(hasPricedOfferDoc),
          lat: _repLat,
          lng: _repLng,
          areaPolygons: _areaCoordinatesMap,
          bboxes: _areaBoxes,
        );
        offersCheckOk = true;
      } catch (e) {
        debugPrint('Traders offers gate unavailable: $e');
      }
      final snapshot = await _db.collection("sellers").where("status", isEqualTo: "active").get();
      List<DocumentSnapshot> availableSellers = [];
      for (var doc in snapshot.docs) {
        if (offersCheckOk) {
          if (visibleIds.contains(doc.id)) availableSellers.add(doc);
          continue;
        }
        final data = doc.data() as Map<String, dynamic>;
        if (isOfferVisibleByCoords(
          offerData: data,
          lat: _repLat,
          lng: _repLng,
          areaPolygons: _areaCoordinatesMap,
          bboxes: _areaBoxes,
        )) {
          availableSellers.add(doc);
        }
      }
      _activeSellers = availableSellers;
      _categories = _getUniqueCategories(_activeSellers);
      _applyFilters();
    } catch (e) { debugPrint("Load Error: $e"); }
  }

  void _applyFilters() {
    setState(() {
      _filteredTraders = _activeSellers.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        final name = (data['merchantName'] ?? data['name'] ?? "").toString().toLowerCase();
        final type = data['businessType']?.toString() ?? 'أخرى';
        return name.contains(_searchQuery.toLowerCase()) && (_currentFilter == 'all' || type == _currentFilter);
      }).toList();
    });
  }

  // Point-in-polygon math lives in lib/utils/geo_areas.dart (shared chain).

  List<String> _getUniqueCategories(List<DocumentSnapshot> sData) {
    final categories = <String>{};
    for (var doc in sData) {
      final type = (doc.data() as Map)['businessType'];
      if (type != null) categories.add(type.toString().trim());
    }
    return categories.toList()..sort();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F9FA),
        appBar: AppBar(
          title: const Text("الموردين حولك", style: TextStyle(fontWeight: FontWeight.bold)),
          centerTitle: true,
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0.5,
        ),
        body: SafeArea(
          child: Column(
            children: [
              if (!_repHasFix && !_isLoading) _buildNoLocationBanner(),
              _buildSearchBox(),
              _buildCategoryFilter(),
              Expanded(
                child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF43B97F)))
                : _filteredTraders.isEmpty
                  ? const Center(child: Text("لا يوجد موردين متاحين في منطقتك حالياً"))
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _filteredTraders.length,
                      itemBuilder: (context, index) => _buildTraderCard(_filteredTraders[index]),
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNoLocationBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.location_off_outlined, color: Colors.amber.shade800),
          const SizedBox(width: 8),
          const Expanded(
            child: Text("تعذر تحديد موقعك — يُعرض الموردون العامون فقط.",
                style: TextStyle(fontSize: 13, color: Colors.black87)),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBox() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: TextField(
        onChanged: (v) { _searchQuery = v; _applyFilters(); },
        decoration: InputDecoration(
          hintText: "بحث باسم المورد...",
          prefixIcon: const Icon(Icons.search),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
        ),
      ),
    );
  }

  Widget _buildCategoryFilter() {
    return SizedBox(
      height: 50,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: ActionChip(
              label: const Text("الكل"),
              onPressed: () { setState(() => _currentFilter = 'all'); _applyFilters(); },
              backgroundColor: _currentFilter == 'all' ? const Color(0xFF43B97F) : Colors.white,
              labelStyle: TextStyle(color: _currentFilter == 'all' ? Colors.white : Colors.black),
            ),
          ),
          ..._categories.map((c) => Padding(
            padding: const EdgeInsets.only(left: 8),
            child: ActionChip(
              label: Text(c),
              onPressed: () { setState(() => _currentFilter = c); _applyFilters(); },
              backgroundColor: _currentFilter == c ? const Color(0xFF43B97F) : Colors.white,
              labelStyle: TextStyle(color: _currentFilter == c ? Colors.white : Colors.black),
            ),
          )),
        ],
      ),
    );
  }

  Widget _buildTraderCard(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final String name = data['merchantName'] ?? data['name'] ?? 'تاجر غير مسمى';
    final String? logo = data['logoUrl'] ?? data['merchantLogoUrl'];
    final String type = data['businessType'] ?? 'أخرى';
    final double minOrder = (data['minOrderTotal'] ?? 0.0).toDouble();
    final String address = data['address'] ?? 'العنوان غير محدد';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => RepTraderOffersScreen(sellerId: doc.id, sellerName: name))
        ),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              Container(
                width: 65, height: 65,
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: (logo != null && logo.isNotEmpty)
                      ? Image.network(logo, fit: BoxFit.cover, errorBuilder: (c, e, s) => const Icon(Icons.store))
                      : const Icon(Icons.store, color: Colors.grey),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Text(type, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.location_on_outlined, size: 14, color: Colors.green),
                        Expanded(child: Text(address, style: const TextStyle(fontSize: 11, color: Colors.grey), maxLines: 1, overflow: TextOverflow.ellipsis)),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text("أقل طلب", style: TextStyle(fontSize: 10, color: Colors.grey)),
                  Text("$minOrder ج.م", style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF43B97F), fontSize: 12)),
                  const Icon(Icons.arrow_forward_ios, size: 12, color: Colors.grey),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
