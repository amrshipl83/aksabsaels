import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:url_launcher/url_launcher.dart';
import '../../utils/firestore_error_helpers.dart';
import '../../utils/geo_areas.dart';

class RepProductsScreen extends StatefulWidget {
  final String subId;
  final String subName;
  final Position? initialPosition;

  const RepProductsScreen({
    super.key,
    required this.subId,
    required this.subName,
    this.initialPosition,
  });

  @override
  State<RepProductsScreen> createState() => _RepProductsScreenState();
}

class _RepProductsScreenState extends State<RepProductsScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  Position? _currentPosition;
  Map<String, List<List<AreaPoint>>> _areaPolygons = {};
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
      _areaPolygons = parseAreaPolygons(data);
      if (_areaPolygons.isEmpty) debugPrint('GeoAreas: no valid polygons parsed');
    } catch (e) {
      debugPrint("GeoJSON Error: $e");
    }
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

  Future<void> _openIndexUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر فتح الرابط — انسخه من الرسالة')));
    }
  }

  Widget _buildQueryError({required String title, required Object? error, required String debugInfo, bool compact = false}) {
    final url = extractFirestoreIndexUrl(error);
    final needsIndex = isMissingIndexError(error);
    final posLine = _currentPosition == null ? 'الموقع: غير متاح' : 'الموقع: ${_currentPosition!.latitude.toStringAsFixed(5)}, ${_currentPosition!.longitude.toStringAsFixed(5)}';
    return Card(
      margin: const EdgeInsets.all(12),
      color: const Color(0xFFFFF3E0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Color(0xFFFFB74D))),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [const Icon(Icons.warning_amber_rounded, color: Color(0xFFE65100)), const SizedBox(width: 8), Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)))]),
            const SizedBox(height: 8),
            SelectableText(error?.toString() ?? 'خطأ غير معروف', style: const TextStyle(fontSize: 11, color: Colors.black87)),
            const SizedBox(height: 6),
            SelectableText('$debugInfo | $posLine | مناطق محملة: ${_areaPolygons.length}', style: const TextStyle(fontSize: 10, color: Colors.grey)),
            if (needsIndex && url != null) ...[
              const SizedBox(height: 8),
              const Text('الكويري يحتاج فهرس مركب — افتح الرابط لإنشائه:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFE65100))),
              const SizedBox(height: 4),
              SelectableText(url, style: const TextStyle(fontSize: 11, color: Colors.blue)),
              const SizedBox(height: 8),
              ElevatedButton.icon(onPressed: () => _openIndexUrl(url), icon: const Icon(Icons.open_in_new, size: 16, color: Colors.white), label: const Text('فتح رابط الفهرس', style: TextStyle(color: Colors.white, fontSize: 12)), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE65100))),
            ],
            if (!compact) ...[
              const SizedBox(height: 8),
              const Text('تلميح: عروض التاجر بتفتح لكن المنتجات فاضية؟ غالبا أسماء deliveryAreas غير مطابقة لأسماء مناطق ملف GeoJSON.', style: TextStyle(fontSize: 11, color: Colors.black54)),
            ],
          ],
        ),
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
        if (snapshot.hasError) { return _buildQueryError(title: 'تعذر تحميل المنتجات', error: snapshot.error, debugInfo: 'subId: ${widget.subId}'); }
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
              imageUrl,
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
        if (snapshot.hasError) { return _buildQueryError(title: 'تعذر تحميل عروض: $name', error: snapshot.error, debugInfo: 'productId: $productId', compact: true); }
        if (!snapshot.hasData) return const SizedBox();

        var filteredOffers = snapshot.data!.docs.where((doc) {
          var data = doc.data() as Map<String, dynamic>;
          return offerCoversLocation(
            deliveryAreas: data['deliveryAreas'],
            lat: _currentPosition?.latitude,
            lng: _currentPosition?.longitude,
            areaPolygons: _areaPolygons,
          );
        }).toList();

        if (filteredOffers.isEmpty) { final hiddenTotal = snapshot.data!.docs.length; if (hiddenTotal == 0) return const SizedBox(); return _buildGeoHiddenNote(name, hiddenTotal); }

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
              
              // **منطق استخراج السعر والسعر المخفض (Offer Price)**
              double originalPrice = 0.0;
              if (offer['units'] != null && (offer['units'] as List).isNotEmpty) {
                originalPrice = double.tryParse(offer['units'][0]['price'].toString()) ?? 0.0;
              } else if (offer['price'] != null) {
                originalPrice = double.tryParse(offer['price'].toString()) ?? 0.0;
              }

              double? offerPrice;
              if (offer['offerPrice'] != null) {
                offerPrice = double.tryParse(offer['offerPrice'].toString());
              }

              // التحقق من وجود عرض تخفيض حقيقي
              bool hasDiscount = offerPrice != null && offerPrice > 0 && offerPrice < originalPrice;
              double finalPrice = hasDiscount ? offerPrice! : originalPrice;

              String offerId = offerDoc.id;

              return Container(
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: Colors.grey.shade200),
                    right: BorderSide(
                      color: hasDiscount ? Colors.orange.shade600 : Colors.transparent, 
                      width: hasDiscount ? 4 : 0,
                    ),
                  ),
                  color: hasDiscount ? Colors.amber.shade50.withOpacity(0.4) : Colors.grey.shade50,
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  title: Row(
                    children: [
                      Text(sellerName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                      if (hasDiscount) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade700,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            "عرض خاص",
                            style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ],
                  ),
                  subtitle: Row(
                    children: [
                      if (hasDiscount) ...[
                        Text(
                          "$originalPrice ج.م",
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        "السعر: $finalPrice ج.م",
                        style: TextStyle(
                          color: hasDiscount ? Colors.green.shade700 : Colors.green,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  trailing: _demoCart.containsKey(offerId)
                      ? _buildQtyControl(offerId, isInsideModal: false)
                      : ElevatedButton(
                          onPressed: () => setState(() {
                            _demoCart[offerId] = {
                              'id': offerId,
                              'name': "$name - $sellerName",
                              'price': finalPrice,
                              'qty': 1
                            };
                          }),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: hasDiscount ? Colors.orange.shade700 : const Color(0xFF43B97F),
                            elevation: hasDiscount ? 2 : 0,
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

  Widget _buildGeoHiddenNote(String name, int totalOffers) {
    final hasLocation = _currentPosition != null;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: const Color(0xFFFFF8E1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.amber.shade200)),
      child: ListTile(
        dense: true,
        leading: Icon(hasLocation ? Icons.location_on_outlined : Icons.location_off_outlined, color: Colors.amber.shade800),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        subtitle: Text(geoHiddenMessage(totalOffers: totalOffers, hasLocation: hasLocation), style: const TextStyle(fontSize: 11)),
      ),
    );
  }

  Widget _buildQtyControl(String id, {required bool isInsideModal, StateSetter? modalState}) {
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
              if (modalState != null) modalState(() {});
            },
          ),
          Text("${_demoCart[id]!['qty']}", style: const TextStyle(fontWeight: FontWeight.bold)),
          IconButton(
            icon: const Icon(Icons.add, color: Colors.green, size: 18),
            onPressed: () {
              setState(() {
                _demoCart[id]!['qty']++;
              });
              if (modalState != null) modalState(() {});
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
            child: SafeArea(
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
                          trailing: _buildQtyControl(id, isInsideModal: true, modalState: setModalState),
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
                    ),
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