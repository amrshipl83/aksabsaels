import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
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

  // --- 🛒 متغيرات سلة المحاكاة ---
  final Map<String, Map<String, dynamic>> _demoCart = {};

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  Future<void> _initializeData() async {
    await Future.wait([
      _getCurrentLocation(),
      _loadGeoJsonData(),
    ]);
    if (mounted) setState(() => _isLoadingLocation = false);
  }

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
      print("Error loading GeoJSON: $e");
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
        appBar: AppBar(
          title: Text(widget.subName),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0.5,
          actions: [
            if (_demoCart.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.red),
                onPressed: () => setState(() => _demoCart.clear()),
              )
          ],
        ),
        body: _isLoadingLocation
            ? const Center(child: CircularProgressIndicator())
            : Stack(
                children: [
                  StreamBuilder<QuerySnapshot>(
                    stream: _db.collection('products')
                        .where('subId', isEqualTo: widget.subId)
                        .where('status', isEqualTo: 'active')
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                      return ListView.builder(
                        padding: EdgeInsets.only(left: 10, right: 10, top: 10, bottom: _demoCart.isNotEmpty ? 100 : 10),
                        itemCount: snapshot.data!.docs.length,
                        itemBuilder: (context, index) {
                          var product = snapshot.data!.docs[index];
                          return _buildProductOffers(product.id, product['name'], product['imageUrls']?[0]);
                        },
                      );
                    },
                  ),
                  // --- بار الإجمالي (المحاكاة) ---
                  if (_demoCart.isNotEmpty)
                    Positioned(
                      bottom: 0, left: 0, right: 0,
                      child: _buildBottomDemoBar(),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _buildProductOffers(String productId, String name, String? imageUrl) {
    return FutureBuilder<QuerySnapshot>(
      future: _db.collection('productOffers')
          .where('productId', isEqualTo: productId)
          .where('status', isEqualTo: 'active')
          .get(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox();

        var filteredOffers = snapshot.data!.docs.where((doc) {
          var data = doc.data() as Map<String, dynamic>;
          List? deliveryAreas = data['deliveryAreas'];
          if (deliveryAreas == null || deliveryAreas.isEmpty) return true;
          if (_currentPosition == null) return false;
          return deliveryAreas.any((areaName) {
            var polygon = _areaCoordinates[areaName];
            if (polygon == null) return false;
            return _isPointInPolygon(_currentPosition!.latitude, _currentPosition!.longitude, polygon);
          });
        }).toList();

        if (filteredOffers.isEmpty) return const SizedBox();

        // ترتيب العروض من الأرخص
        filteredOffers.sort((a, b) {
          var pA = (a.data() as Map)['price'] ?? (a.data() as Map)['units']?[0]['price'] ?? 0;
          var pB = (b.data() as Map)['price'] ?? (b.data() as Map)['units']?[0]['price'] ?? 0;
          return pA.compareTo(pB);
        });

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ExpansionTile(
            leading: imageUrl != null
                ? Image.network(imageUrl, width: 45, height: 45, fit: BoxFit.cover)
                : const Icon(Icons.shopping_bag, color: Colors.grey),
            title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            subtitle: Text("متاح لدى ${filteredOffers.length} تجار", style: const TextStyle(fontSize: 11)),
            children: filteredOffers.map((offerDoc) {
              var offer = offerDoc.data() as Map<String, dynamic>;
              String sellerName = offer['sellerName'] ?? "تاجر";
              var price = offer['price'] ?? offer['units']?[0]['price'];
              String offerId = offerDoc.id;

              return Container(
                color: Colors.grey.shade50,
                child: ListTile(
                  title: Text(sellerName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  subtitle: Text("السعر: $price ج.م", style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                  trailing: _demoCart.containsKey(offerId)
                      ? _buildQtyControl(offerId)
                      : ElevatedButton(
                          onPressed: () => setState(() {
                            _demoCart[offerId] = {
                              'name': "$name - $sellerName",
                              'price': double.parse(price.toString()),
                              'qty': 1
                            };
                          }),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.green, padding: const EdgeInsets.symmetric(horizontal: 12)),
                          child: const Text("إضافة", style: TextStyle(color: Colors.white, fontSize: 12)),
                        ),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Widget _buildQtyControl(String id) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 20),
          onPressed: () => setState(() {
            if (_demoCart[id]!['qty'] > 1) _demoCart[id]!['qty']--;
            else _demoCart.remove(id);
          }),
        ),
        Text("${_demoCart[id]!['qty']}", style: const TextStyle(fontWeight: FontWeight.bold)),
        IconButton(
          icon: const Icon(Icons.add_circle_outline, color: Colors.green, size: 20),
          onPressed: () => setState(() => _demoCart[id]!['qty']++),
        ),
      ],
    );
  }

  Widget _buildBottomDemoBar() {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: const Offset(0, -2))],
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("إجمالي العرض للعميل", style: TextStyle(fontSize: 12, color: Colors.grey)),
              Text("${_calculateTotal().toStringAsFixed(2)} ج.م", 
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.blue)),
            ],
          ),
          ElevatedButton(
            onPressed: () => _showDemoSuccess(),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
            child: const Text("شرح الطلب للعميل", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showDemoSuccess() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.info_outline, size: 50, color: Colors.blue),
            const SizedBox(height: 10),
            const Text("توجيه العميل", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 15),
              child: Text(
                "يا حاج، دي المنتجات اللي اخترناها سوا. دلوقتي تقدر تفتح تطبيقك وتطلبها بنفس السعر ده وهتوصلك فوراً!",
                textAlign: TextAlign.center,
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text("تم")),
            )
          ],
        ),
      ),
    );
  }
}

