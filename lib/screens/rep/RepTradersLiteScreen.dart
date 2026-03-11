import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart'; 
import 'package:flutter/services.dart' show rootBundle;

// تعريف كلاس الإحداثيات محلياً لسهولة الاستخدام
class Coordinates {
  final double lat;
  final double lng;
  Coordinates({required this.lat, required this.lng});
}

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

  Coordinates? _currentPosition;
  Map<String, List<Coordinates>> _areaCoordinatesMap = {};

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    // 1. تحميل المناطق الجغرافية من ملف الـ GeoJSON
    await _fetchAndProcessGeoJson();
    // 2. جلب موقع المندوب الحالي (GPS)
    _currentPosition = await _getCurrentLocation();
    // 3. تحميل التجار المتاحين في هذه المنطقة
    await _loadTraders();

    if (mounted) setState(() => _isLoading = false);
  }

  Future<Coordinates?> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return null;
      }
      
      Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      return Coordinates(lat: pos.latitude, lng: pos.longitude);
    } catch (e) {
      debugPrint("Location Error: $e");
      return null;
    }
  }

  Future<void> _fetchAndProcessGeoJson() async {
    try {
      final String jsonString = await rootBundle.loadString('assets/OSMB-bc319d822a17aa9ad1089fc05e7d4e752460f877.geojson');
      final data = json.decode(jsonString);
      if (data['features'] != null) {
        for (var feature in data['features']) {
          final areaName = feature['properties']?['name'];
          final geometry = feature['geometry'];
          if (areaName != null && geometry != null) {
            List polygonCoords = geometry['type'] == 'MultiPolygon' 
                ? geometry['coordinates'][0][0] 
                : geometry['coordinates'][0];
            
            _areaCoordinatesMap[areaName] = polygonCoords.map<Coordinates>((coord) => 
                Coordinates(lat: coord[1].toDouble(), lng: coord[0].toDouble())).toList();
          }
        }
      }
    } catch (e) { debugPrint("GeoJSON Error: $e"); }
  }

  Future<void> _loadTraders() async {
    try {
      final snapshot = await _db.collection("sellers").where("status", isEqualTo: "active").get();
      List<DocumentSnapshot> availableSellers = [];

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final List? deliveryAreas = data['deliveryAreas'] as List?;

        if (_currentPosition == null) {
          if (deliveryAreas == null || deliveryAreas.isEmpty) availableSellers.add(doc);
          continue;
        }

        if (deliveryAreas == null || deliveryAreas.isEmpty) {
          availableSellers.add(doc);
          continue;
        }

        bool isCovered = deliveryAreas.any((areaName) {
          final polygon = _areaCoordinatesMap[areaName];
          return (polygon != null) ? _isPointInPolygon(_currentPosition!, polygon) : false;
        });

        if (isCovered) availableSellers.add(doc);
      }

      _activeSellers = availableSellers;
      _categories = _getUniqueCategories(_activeSellers);
      _applyFilters();
    } catch (e) { debugPrint("Load Error: $e"); }
  }

  void _applyFilters() {
    if (!mounted) return;
    setState(() {
      _filteredTraders = _activeSellers.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        final name = (data['name'] ?? data['merchantName'] ?? "").toString().toLowerCase();
        final type = data['businessType']?.toString() ?? 'أخرى';
        return name.contains(_searchQuery.toLowerCase()) && 
               (_currentFilter == 'all' || type == _currentFilter);
      }).toList();
    });
  }

  bool _isPointInPolygon(Coordinates point, List<Coordinates> polygon) {
    final x = point.lng; final y = point.lat;
    bool inside = false;
    for (int i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final xi = polygon[i].lng; final yi = polygon[i].lat;
      final xj = polygon[j].lng; final yj = polygon[j].lat;
      if (((yi > y) != (yj > y)) && (x < (xj - xi) * (y - yi) / (yj - yi) + xi)) inside = !inside;
    }
    return inside;
  }

  List<String> _getUniqueCategories(List<DocumentSnapshot> sData) {
    final categories = <String>{};
    for (var doc in sData) {
      final type = (doc.data() as Map)['businessType'];
      if (type != null && type.toString().trim().isNotEmpty) {
        categories.add(type.toString().trim());
      }
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
          title: const Text("الموردين المتاحين حولك", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          centerTitle: true,
          elevation: 0.5,
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
        ),
        body: Column(
          children: [
            _buildSearchBox(),
            _buildCategoryFilter(),
            Expanded(
              child: _isLoading 
                ? const Center(child: CircularProgressIndicator(color: Colors.green))
                : _filteredTraders.isEmpty 
                  ? _buildEmptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _filteredTraders.length,
                      itemBuilder: (context, index) => _buildTraderCard(_filteredTraders[index]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBox() {
    return Container(
      padding: const EdgeInsets.all(12),
      color: Colors.white,
      child: TextField(
        onChanged: (v) { _searchQuery = v; _applyFilters(); },
        decoration: InputDecoration(
          hintText: "بحث باسم المورد...",
          prefixIcon: const Icon(Icons.search, color: Colors.green),
          filled: true,
          fillColor: Colors.grey.shade100,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        ),
      ),
    );
  }

  Widget _buildCategoryFilter() {
    return Container(
      height: 60,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        children: [
          _filterChip("الكل", "all"),
          ..._categories.map((c) => _filterChip(c, c)),
        ],
      ),
    );
  }

  Widget _filterChip(String label, String value) {
    bool isSelected = _currentFilter == value;
    return GestureDetector(
      onTap: () { setState(() => _currentFilter = value); _applyFilters(); },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 5),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: isSelected ? Colors.green : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(25),
          border: Border.all(color: isSelected ? Colors.green : Colors.transparent),
        ),
        child: Center(
          child: Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.black54, fontSize: 13, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  Widget _buildTraderCard(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final String? deliveryTime = data['deliveryTime'];
    final String sellerId = doc.id;
    final String sellerName = data['name'] ?? data['merchantName'] ?? 'تاجر';

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: Colors.grey.shade200)),
      child: Column(
        children: [
          ListTile(
            contentPadding: const EdgeInsets.all(12),
            leading: Container(
              width: 50, height: 50,
              decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.storefront_rounded, color: Colors.green),
            ),
            title: Text(sellerName, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(data['businessType'] ?? 'نشاط تجاري', style: const TextStyle(fontSize: 12)),
            trailing: const Icon(Icons.check_circle, color: Colors.green, size: 18),
          ),
          if (deliveryTime != null && deliveryTime.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
              color: Colors.orange.shade50,
              child: Row(
                children: [
                  const Icon(Icons.local_shipping_outlined, size: 14, color: Colors.orange),
                  const SizedBox(width: 8),
                  Text("التوصيل خلال: $deliveryTime", style: const TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () {
                    // هنا نفتح صفحة عروض التاجر التي سنبنيها لاحقاً
                  },
                  icon: const Icon(Icons.local_offer_outlined, size: 18),
                  label: const Text("رؤية العروض", style: TextStyle(fontWeight: FontWeight.bold)),
                  style: TextButton.styleFrom(foregroundColor: Colors.green),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.location_off_outlined, size: 60, color: Colors.grey.shade300),
          const SizedBox(height: 10),
          const Text("لا يوجد موردين يغطون موقعك الحالي", style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}

