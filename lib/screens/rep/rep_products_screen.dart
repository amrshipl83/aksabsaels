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

  // --- 🛒 سلة المحاكاة ---
  final Map<String, Map<String, dynamic>> _demoCart = {};

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  Future<void> _initializeData() async {
    // البدء بعرض رسالة الإفصاح أولاً قبل محاولة جلب الموقع
    await _showLocationDisclosure();
    
    await Future.wait([
      _getCurrentLocation(),
      _loadGeoJsonData(),
    ]);
    if (mounted) setState(() => _isLoadingLocation = false);
  }

  // 📢 رسالة إفصاح للمستخدم عن سبب استخدام الموقع
  Future<void> _showLocationDisclosure() async {
    return showDialog(
      context: context,
      barrierDismissible: false, // يجب أن يوافق أو يرفض
      builder: (BuildContext context) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            title: const Row(
              children: [
                Icon(Icons.location_on, color: Color(0xFF43B97F)),
                SizedBox(width: 10),
                Text("الوصول إلى الموقع"),
              ],
            ),
            content: const Text(
                "نحتاج الوصول إلى موقعك الجغرافي لنتمكن من عرض المنتجات والأسعار المتاحة في منطقتك الحالية فقط، ولضمان دقة العروض التي تقدمها للعملاء."),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text("موافق، ابدأ الآن", style: TextStyle(color: Color(0xFF43B97F), fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("يرجى تفعيل خدمة الموقع (GPS) في هاتفك")),
        );
      }
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    if (permission == LocationPermission.deniedForever) return;

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
      debugPrint("Error loading GeoJSON: $e");
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

  int _calculateTotalQty() {
    int count = 0;
    _demoCart.forEach((key, value) => count += (value['qty'] as int));
    return count;
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.subName, style: const TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0.5,
          actions: [
            if (_demoCart.isNotEmpty)
              TextButton.icon(
                onPressed: () {
                  setState(() => _demoCart.clear());
                },
                icon: const Icon(Icons.delete_sweep, color: Colors.red),
                label: const Text("تفريغ", style: TextStyle(color: Colors.red)),
              )
          ],
        ),
        floatingActionButton: _demoCart.isNotEmpty ? FloatingActionButton.extended(
          onPressed: () => _showDemoSuccess(),
          backgroundColor: const Color(0xFF43B97F),
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(Icons.shopping_cart, color: Colors.white),
              Positioned(
                right: -5, top: -5,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                  child: Text("${_calculateTotalQty()}", style: const TextStyle(fontSize: 10, color: Colors.white)),
                ),
              )
            ],
          ),
          label: Text("إجمالي العرض: ${_calculateTotal().toStringAsFixed(0)} ج.م",
                 style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ) : null,
        body: SafeArea(
          child: _isLoadingLocation
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF43B97F)))
              : StreamBuilder<QuerySnapshot>(
                  stream: _db.collection('products')
                      .where('subId', isEqualTo: widget.subId)
                      .where('status', isEqualTo: 'active')
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                    return ListView.builder(
                      padding: const EdgeInsets.fromLTRB(10, 10, 10, 80),
                      itemCount: snapshot.data!.docs.length,
                      itemBuilder: (context, index) {
                        var product = snapshot.data!.docs[index];
                        return _buildProductOffers(product.id, product['name'], product['imageUrls']?[0]);
                      },
                    );
                  },
                ),
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

        filteredOffers.sort((a, b) {
          var pA = (a.data() as Map)['price'] ?? (a.data() as Map)['units']?[0]['price'] ?? 0;
          var pB = (b.data() as Map)['price'] ?? (b.data() as Map)['units']?[0]['price'] ?? 0;
          return pA.compareTo(pB);
        });

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
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: Colors.grey.shade200)),
                  color: Colors.grey.shade50,
                ),
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
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF43B97F),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
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

  // التحكم في الكمية مع دعم التحديث داخل المودال وخارجه
  Widget _buildQtyControl(String id, {required bool isInsideModal}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade300),
      ),
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
              if (isInsideModal) (context as Element).markNeedsBuild();
            },
          ),
          Text("${_demoCart[id]!['qty']}", style: const TextStyle(fontWeight: FontWeight.bold)),
          IconButton(
            icon: const Icon(Icons.add, color: Colors.green, size: 18),
            onPressed: () {
              setState(() {
                _demoCart[id]!['qty']++;
              });
              if (isInsideModal) (context as Element).markNeedsBuild();
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
        builder: (context, setModalState) {
          return Directionality(
            textDirection: TextDirection.rtl,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("سلة العرض المؤقتة", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      TextButton(
                        onPressed: () {
                          setState(() => _demoCart.clear());
                          Navigator.pop(context);
                        },
                        child: const Text("تفريغ الكل", style: TextStyle(color: Colors.red)),
                      )
                    ],
                  ),
                  const Divider(),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.4),
                    child: ListView(
                      shrinkWrap: true,
                      children: _demoCart.keys.map((id) {
                        final item = _demoCart[id]!;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(item['name'], style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                                    Text("${item['price']} ج.م", style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                  ],
                                ),
                              ),
                              _buildQtyControl(id, isInsideModal: true),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const Divider(thickness: 2),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("الإجمالي النهائي", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        Text("${_calculateTotal().toStringAsFixed(2)} ج.م", 
                             style: const TextStyle(fontSize: 20, color: Color(0xFF43B97F), fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 15),
                  const Text(
                    "هذه الأسعار تقديرية بناءً على منطقتك الآن، اطلب من العميل تنفيذ الطلب من تطبيقه لضمان هذه العروض.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF43B97F),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text("إغلاق العرض", style: TextStyle(color: Colors.white, fontSize: 16)),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
          );
        }
      ),
    );
  }
}

