import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'RepTraderOffersScreen.dart';

class Coordinates {
  final double lat;
  final double lng;
  Coordinates({required this.lat, required this.lng});
}

class RepTradersLiteScreen extends StatefulWidget {
  final Position? initialPosition;
  const RepTradersLiteScreen({super.key, this.initialPosition});

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
    await _fetchAndProcessGeoJson();
    if (widget.initialPosition != null) {
      _currentPosition = Coordinates(lat: widget.initialPosition!.latitude, lng: widget.initialPosition!.longitude);
    } else {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.always || permission == LocationPermission.whileInUse) {
        Position pos = await Geolocator.getCurrentPosition();
        _currentPosition = Coordinates(lat: pos.latitude, lng: pos.longitude);
      }
    }
    await _loadTraders();
    if (mounted) setState(() => _isLoading = false);
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
            List polygonCoords = geometry['type'] == 'MultiPolygon' ? geometry['coordinates'][0][0] : geometry['coordinates'][0];
            _areaCoordinatesMap[areaName] = polygonCoords.map<Coordinates>((coord) => Coordinates(lat: coord[1].toDouble(), lng: coord[0].toDouble())).toList();
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
        final data = doc.data() as Map<String, dynamic>;
        final List? deliveryAreas = data['deliveryAreas'] as List?;
        if (_currentPosition == null || deliveryAreas == null || deliveryAreas.isEmpty) {
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
    setState(() {
      _filteredTraders = _activeSellers.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        final name = (data['merchantName'] ?? data['name'] ?? "").toString().toLowerCase();
        final type = data['businessType']?.toString() ?? 'أخرى';
        return name.contains(_searchQuery.toLowerCase()) && (_currentFilter == 'all' || type == _currentFilter);
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

