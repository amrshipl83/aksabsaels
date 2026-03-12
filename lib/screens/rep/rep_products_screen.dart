import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

class RepProductsScreen extends StatefulWidget {
  final String subId;
  final String subName;
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
    await _loadGeoJsonData();
    if (widget.initialPosition != null) {
      _currentPosition = widget.initialPosition;
    } else {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.always || permission == LocationPermission.whileInUse) {
        _currentPosition = await Geolocator.getCurrentPosition();
      } else {
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
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
        floatingActionButton: _demoCart.isNotEmpty ? _buildFabCart() : null,
        body: SafeArea(
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
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            var productDoc = snapshot.data!.docs[index];
            var productData = productDoc.data() as Map<String, dynamic>;

            String? imageUrl;
            if (productData.containsKey('imageUrls') && productData['imageUrls'] != null && (productData['imageUrls'] as List).isNotEmpty) {
              imageUrl = productData['imageUrls'][0];
            }

            return _buildProductOffers(
              productDoc.id,
              productData['name'] ?? '',
              imageUrl
            );
          },
        );
      },
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

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ExpansionTile(
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: imageUrl != null
                  ? Image.network(imageUrl, width: 45, height: 45, fit: BoxFit.cover)
                  : const Icon(Icons.shopping_bag, color: Colors.grey),
            ),
            title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            subtitle: Text("متاح لدى ${filteredOffers.length} تجار في منطقتك", style: const TextStyle(fontSize: 11)),
            children: filteredOffers.map((offerDoc) {
              var offer = offerDoc.data() as Map<String, dynamic>;
              String sellerName = offer['sellerName'] ?? "تاجر";
              var price = offer['price'] ?? offer['units']?[0]['price'];
              String offerId = offerDoc.id;
              return Container(
                decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.grey.shade200)), color: Colors.grey.shade50),
                child: ListTile(
                  title: Text(sellerName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  subtitle: Text("السعر: $price ج.م", style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                  trailing: _demoCart.containsKey(offerId)
                      ? _buildQtyControl(offerId, isInsideModal: false)
                      : ElevatedButton(
                          onPressed: () => setState(() {
                            _demoCart[offerId] = {
                              'id': offerId,
                              'name': "$name - $sellerName",
                              'price': double.parse(price.toString()),
                              'qty': 1
                            };
                          }),
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF43B97F)),
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

  // 💡 إضافة StateSetter لتحديث واجهة السلة (Modal) عند الضغط
  Widget _buildQtyControl(String id, {required bool isInsideModal, StateSetter? modalState}) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.grey.shade300)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.remove, color: Colors.red, size: 18),
            onPressed: () {
              setState(() {
                if (_demoCart[id]!['qty'] > 1) {
                  _demoCart[id]!['qty']--;
                } else {
                  _demoCart.remove(id);
                  if (isInsideModal && _demoCart.isEmpty) Navigator.pop(context);
                }
              });
              if (modalState != null) modalState(() {}); // تحديث السلة
            },
          ),
          Text("${_demoCart[id]!['qty']}", style: const TextStyle(fontWeight: FontWeight.bold)),
          IconButton(
            icon: const Icon(Icons.add, color: Colors.green, size: 18),
            onPressed: () {
              setState(() {
                _demoCart[id]!['qty']++;
              });
              if (modalState != null) modalState(() {}); // تحديث السلة
            },
          ),
        ],
      ),
    );
  }

  void _showDemoSuccess() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Directionality(
          textDirection: TextDirection.rtl,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: Colors.white, 
              borderRadius: BorderRadius.vertical(top: Radius.circular(25))
            ),
            child: SafeArea( // 🔥 مساحة آمنة لضبط السلة في شاشات الموبايل الحديثة
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
                  const SizedBox(height: 10),
                  const Text("سلة العرض المؤقتة", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Divider(),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.4),
                    child: ListView(
                      shrinkWrap: true,
                      children: _demoCart.keys.map((id) {
                        final item = _demoCart[id]!;
                        return ListTile(
                          title: Text(item['name'], style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                          subtitle: Text("${item['price']} ج.م"),
                          trailing: _buildQtyControl(id, isInsideModal: true, modalState: setModalState), // مررنا الستيت هنا
                        );
                      }).toList(),
                    ),
                  ),
                  const Divider(),
                  Text(
                    "الإجمالي: ${_calculateTotal().toStringAsFixed(2)} ج.م", 
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF43B97F))
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity, 
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context), 
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF43B97F)),
                      child: const Text("إغلاق", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
                    )
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

