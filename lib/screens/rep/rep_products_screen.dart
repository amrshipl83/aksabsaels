import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart'; // مكتبة تحديد الموقع
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

class RepProductsScreen extends StatefulWidget {
  final String subId;
  final String subName;

  const RepProductsScreen({super.key, required this.subId, required this.subName});

  @override
  State<RepProductsScreen> createState() => _RepProductsScreenState();
}

class _RepProductsScreenState extends State<RepProductsScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  Position? _currentPosition;
  Map<String, List<Map<String, double>>> _areaCoordinates = {};
  bool _isLoadingLocation = true;

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  // 1. تشغيل جلب الموقع وتحميل ملف المناطق معاً
  Future<void> _initializeData() async {
    await Future.wait([
      _getCurrentLocation(),
      _loadGeoJsonData(),
    ]);
    if (mounted) setState(() => _isLoadingLocation = false);
  }

  // 2. جلب إحداثيات المندوب الحالية (اللوكيشن اللحظي)
  Future<void> _getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    _currentPosition = await Geolocator.getCurrentPosition();
  }

  // 3. تحميل ملف GeoJSON (نفس المنطق في الويب)
  Future<void> _loadGeoJsonData() async {
    try {
      // تأكد من وضع الملف في assets/data/ areas.json
      String jsonString = await rootBundle.loadString('assets/OSMB-bc319d822a17aa9ad1089fc05e7d4e752460f877.geojson');
      final data = json.decode(jsonString);
      
      var features = data['features'] as List;
      for (var feature in features) {
        String name = feature['properties']['name'];
        var coords = feature['geometry']['coordinates'][0][0] as List;
        
        _areaCoordinates[name] = coords.map((c) => {
          'lat': (c[1] as num).toDouble(),
          'lng': (c[0] as num).toDouble(),
        }).toList();
      }
    } catch (e) {
      print("Error loading GeoJSON: $e");
    }
  }

  // 4. دالة التحقق: هل إحداثيات المندوب داخل المضلع؟
  bool _isPointInPolygon(double lat, double lng, List<Map<String, double>> polygon) {
    bool inside = false;
    int j = polygon.length - 1;
    for (int i = 0; i < polygon.length; j = i++) {
      if (((polygon[i]['lat']! > lat) != (polygon[j]['lat']! > lat)) &&
          (lng < (polygon[j]['lng']! - polygon[i]['lng']!) * (lat - polygon[i]['lat']!) / (polygon[j]['lat']! - polygon[i]['lat']!) + polygon[i]['lng']!)) {
        inside = !inside;
      }
    }
    return inside;
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.subName),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0.5,
        ),
        body: _isLoadingLocation 
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<QuerySnapshot>(
              stream: _db.collection('products')
                  .where('subId', isEqualTo: widget.subId)
                  .where('status', isEqualTo: 'active')
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                
                return ListView.builder(
                  padding: const EdgeInsets.all(10),
                  itemCount: snapshot.data!.docs.length,
                  itemBuilder: (context, index) {
                    var product = snapshot.data!.docs[index];
                    return _buildProductOffers(product.id, product['name'], product['imageUrls']?[0]);
                  },
                );
              },
            ),
      ),
    );
  }

  // 5. جلب عروض المنتج وفلترتها جغرافياً بموقع المندوب
  Widget _buildProductOffers(String productId, String name, String? imageUrl) {
    return FutureBuilder<QuerySnapshot>(
      future: _db.collection('productOffers')
          .where('productId', isEqualTo: productId)
          .where('status', isEqualTo: 'active')
          .get(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox();

        // الفلترة الجغرافية بموقع المندوب الحالية
        var filteredOffers = snapshot.data!.docs.where((doc) {
          var data = doc.data() as Map<String, dynamic>;
          List? deliveryAreas = data['deliveryAreas'];

          // إذا كان العرض عام (لا توجد مناطق محددة) يظهر للكل
          if (deliveryAreas == null || deliveryAreas.isEmpty) return true;
          
          // إذا كان المندوب لم يسمح بتحديد موقعه، لا نُظهر العروض المقيدة مناطقياً
          if (_currentPosition == null) return false;

          // التحقق هل موقع المندوب الحالي داخل أحد مضلعات مناطق العرض
          return deliveryAreas.any((areaName) {
            var polygon = _areaCoordinates[areaName];
            if (polygon == null) return false;
            return _isPointInPolygon(_currentPosition!.latitude, _currentPosition!.longitude, polygon);
          });
        }).toList();

        if (filteredOffers.isEmpty) return const SizedBox(); // إخفاء المنتج لو ملوش عروض في منطقة المندوب

        var bestOffer = filteredOffers.first.data() as Map<String, dynamic>;

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: ListTile(
            leading: imageUrl != null 
              ? Image.network(imageUrl, width: 50, height: 50, fit: BoxFit.cover)
              : const Icon(Icons.shopping_bag),
            title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text("السعر: ${bestOffer['price'] ?? bestOffer['units']?[0]['price']} ج.م"),
            trailing: ElevatedButton(
              onPressed: () {
                // منطق الإضافة للسلة الوهمية
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              child: const Text("إضافة", style: TextStyle(color: Colors.white)),
            ),
          ),
        );
      },
    );
  }
}

