import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/services.dart' show rootBundle;
// استيراد صفحة العروض للربط
import 'RepTraderOffersScreen.dart'; 

class Coordinates {
  final double lat;
  final double lng;
  Coordinates({required this.lat, required this.lng});
}

class RepTradersLiteScreen extends StatefulWidget {
  // استقبال الموقع من الصفحة السابقة لتجنب إعادة الفحص
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

    // 1. معالجة الـ GeoJSON دائمًا
    await _fetchAndProcessGeoJson();

    // 2. التأمين الذكي للموقع
    if (widget.initialPosition != null) {
      _currentPosition = Coordinates(
        lat: widget.initialPosition!.latitude, 
        lng: widget.initialPosition!.longitude
      );
    } else {
      // فحص صامت أولاً
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.always || permission == LocationPermission.whileInUse) {
        Position pos = await Geolocator.getCurrentPosition();
        _currentPosition = Coordinates(lat: pos.latitude, lng: pos.longitude);
      } else {
        // إذا لم يكن لدينا إذن، نطلب الموقع (الإفصاح تم في الصفحة السابقة ولكن كزيادة تأمين)
        Position? pos = await _requestLocationSafely();
        if (pos != null) {
          _currentPosition = Coordinates(lat: pos.latitude, lng: pos.longitude);
        }
      }
    }

    // 3. تحميل التجار بناءً على النتيجة
    await _loadTraders();
    if (mounted) setState(() => _isLoading = false);
  }

  Future<Position?> _requestLocationSafely() async {
    try {
      LocationPermission permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.always || permission == LocationPermission.whileInUse) {
        return await Geolocator.getCurrentPosition();
      }
    } catch (e) {
      debugPrint("Location Error: $e");
    }
    return null;
  }

  // ... (باقي دوال _fetchAndProcessGeoJson و _isPointInPolygon و _loadTraders كما هي بدون تغيير فني)

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F9FA),
        appBar: AppBar(
          title: const Text("الموردين المتاحين حولك",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          centerTitle: true,
          elevation: 0.5,
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
        ),
        // استخدام SafeArea لضمان أن المحتوى لا يختفي تحت النوتش أو أزرار النظام
        body: SafeArea(
          child: Column(
            children: [
              _buildSearchBox(),
              _buildCategoryFilter(),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: Colors.green))
                    : _filteredTraders.isEmpty
                        ? _buildEmptyState()
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
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

  // ... (دوال _buildSearchBox و _buildCategoryFilter و _filterChip كما هي)

  Widget _buildTraderCard(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final String? deliveryTime = data['deliveryTime'];
    final String sellerId = doc.id;
    final String sellerName = data['name'] ?? data['merchantName'] ?? 'تاجر';

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0.5,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15), 
          side: BorderSide(color: Colors.grey.shade200)),
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
            _buildDeliveryBadge(deliveryTime),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () {
                    // 🟢 الربط بصفحة العروض
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => RepTraderOffersScreen(
                          sellerId: sellerId,
                          sellerName: sellerName,
                        ),
                      ),
                    );
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

  Widget _buildDeliveryBadge(String time) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
      color: Colors.orange.shade50,
      child: Row(
        children: [
          const Icon(Icons.local_shipping_outlined, size: 14, color: Colors.orange),
          const SizedBox(width: 8),
          Text("التوصيل خلال: $time", 
               style: const TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.bold)),
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
          const SizedBox(height: 15),
          if (_currentPosition == null)
            ElevatedButton(
              onPressed: () => _initData(),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              child: const Text("تفعيل الموقع لرؤية الموردين", style: TextStyle(color: Colors.white)),
            )
        ],
      ),
    );
  }
}

