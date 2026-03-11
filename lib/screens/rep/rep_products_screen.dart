import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

class RepProductsScreen extends StatefulWidget {
  final String subId;
  final String subName;
  // أضفنا إمكانية استقبال الموقع إذا كان موجوداً مسبقاً لتوفير الوقت والبطارية
  final Position? initialPosition; 

  const RepProductsScreen({
    super.key, 
    required this.subId, 
    required this.subName, 
    this.initialPosition
  });

  @override
  State<RepProductsScreen> createState() => _RepProductsScreenState();
}

class _RepProductsScreenState extends State<RepProductsScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  Position? _currentPosition;
  Map<String, List<Map<String, double>>> _areaCoordinates = {};
  bool _isLoading = true;

  final Map<String, Map<String, dynamic>> _demoCart = {};

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  Future<void> _initializeData() async {
    // 1. تحميل الـ GeoJson دائمًا في الخلفية
    await _loadGeoJsonData();

    // 2. فحص الموقع: هل تم تمريره؟
    if (widget.initialPosition != null) {
      _currentPosition = widget.initialPosition;
    } else {
      // إذا لم يتم تمريره، نفحص الإذن بهدوء أولاً
      LocationPermission permission = await Geolocator.checkPermission();
      
      if (permission == LocationPermission.always || permission == LocationPermission.whileInUse) {
        _currentPosition = await Geolocator.getCurrentPosition();
      } else {
        // الإذن ليس معنا، نطلب الإفصاح ثم الإذن (فقط هنا تظهر الرسالة)
        await _showLocationDisclosure();
        await _getCurrentLocation();
      }
    }

    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _showLocationDisclosure() async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: const Row(
            children: [
              Icon(Icons.location_on, color: Color(0xFF43B97F)),
              SizedBox(width: 10),
              Text("تصفية العروض القريبة"),
            ],
          ),
          content: const Text("لعرض العروض المتاحة في منطقة العميل الذي تخدمه الآن، نحتاج لتحديد موقعك الحالي."),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("حسناً، استمر", style: TextStyle(color: Color(0xFF43B97F), fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _getCurrentLocation() async {
    try {
      LocationPermission permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.always || permission == LocationPermission.whileInUse) {
        _currentPosition = await Geolocator.getCurrentPosition();
      }
    } catch (e) {
      debugPrint("Location Error: $e");
    }
  }

  Future<void> _loadGeoJsonData() async {
    try {
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
      debugPrint("GeoJSON Error: $e");
    }
  }

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

  double _calculateTotal() {
    double total = 0;
    _demoCart.forEach((key, value) => total += value['price'] * value['qty']);
    return total;
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F9FA),
        appBar: AppBar(
          title: Text(widget.subName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0.5,
          actions: [
            if (_demoCart.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.delete_sweep, color: Colors.red),
                onPressed: () => setState(() => _demoCart.clear()),
              )
          ],
        ),
        // استخدام SafeArea هنا يضمن عدم نزول الـ FAB تحت شريط التنقل
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
        floatingActionButton: _demoCart.isNotEmpty ? _buildFabCart() : null,
        body: SafeArea(
          // التأكد من أن الـ SafeArea تشمل الجسم بالكامل
          bottom: true, 
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF43B97F)))
              : _buildProductsList(),
        ),
      ),
    );
  }

  Widget _buildFabCart() {
    return FloatingActionButton.extended(
      onPressed: () => _showDemoSuccess(),
      backgroundColor: const Color(0xFF43B97F),
      elevation: 4,
      icon: const Icon(Icons.shopping_cart, color: Colors.white),
      label: Text(
        "عرض السعر: ${_calculateTotal().toStringAsFixed(0)} ج.م",
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildProductsList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _db.collection('products')
          .where('subId', isEqualTo: widget.subId)
          .where('status', isEqualTo: 'active')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        if (snapshot.data!.docs.isEmpty) return const Center(child: Text("لا توجد منتجات حالياً في هذا القسم"));

        return ListView.builder(
          // Padding سفلي كبير (100) عشان الـ FAB ميغطيش آخر منتج
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            var product = snapshot.data!.docs[index];
            return _buildProductOffers(product.id, product['name'], product['imageUrls']?[0]);
          },
        );
      },
    );
  }

  // ... (باقي دوال _buildProductOffers و _buildQtyControl و _showDemoSuccess كما هي)
}

