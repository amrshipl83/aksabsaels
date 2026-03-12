import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class RepTraderOffersScreen extends StatefulWidget {
  final String sellerId;
  final String sellerName;

  const RepTraderOffersScreen({
    super.key,
    required this.sellerId,
    required this.sellerName
  });

  @override
  State<RepTraderOffersScreen> createState() => _RepTraderOffersScreenState();
}

class _RepTraderOffersScreenState extends State<RepTraderOffersScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // سلة المحاكاة
  final Map<String, int> _demoCart = {};
  double _totalAmount = 0.0;

  void _updateCart(String productId, double price, int change) {
    setState(() {
      int currentQty = _demoCart[productId] ?? 0;
      int newQty = currentQty + change;

      if (newQty <= 0) {
        _demoCart.remove(productId);
      } else {
        _demoCart[productId] = newQty;
      }
      _totalAmount += (change * price);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F9FA),
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.sellerName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const Text("العروض المتاحة حالياً", style: TextStyle(fontSize: 11, color: Colors.green)),
            ],
          ),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0.5,
        ),
        body: Column(
          children: [
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _db.collection('productOffers')
                    .where('sellerId', isEqualTo: widget.sellerId)
                    .where('status', isEqualTo: 'active')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) return Center(child: Text("خطأ: ${snapshot.error}"));
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Color(0xFF43B97F)));

                  var offers = snapshot.data!.docs;

                  if (offers.isEmpty) {
                    return const Center(child: Text("لا توجد عروض نشطة لهذا المورد"));
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: offers.length,
                    itemBuilder: (context, index) {
                      var offer = offers[index].data() as Map<String, dynamic>;
                      String oId = offers[index].id;
                      String? productId = offer['productId']; // 💡 مفتاح الربط مع المنتج الأصلي

                      // استخراج السعر والوحدات
                      List units = offer['units'] ?? [];
                      double price = 0.0;
                      String unitName = "قطعة";
                      if (units.isNotEmpty) {
                        price = (units[0]['price'] ?? 0.0).toDouble();
                        unitName = units[0]['unitName'] ?? "وحدة";
                      }

                      int qty = _demoCart[oId] ?? 0;

                      // 🛠️ استخدام FutureBuilder لجلب الصورة من مجموعة المنتجات الأصلية
                      return FutureBuilder<DocumentSnapshot>(
                        future: productId != null 
                            ? _db.collection('products').doc(productId).get() 
                            : null,
                        builder: (context, prodSnapshot) {
                          String? finalImageUrl;
                          
                          // محاولة جلب الصورة من بيانات المنتج الأصلي
                          if (prodSnapshot.hasData && prodSnapshot.data!.exists) {
                            var prodData = prodSnapshot.data!.data() as Map<String, dynamic>;
                            if (prodData.containsKey('imageUrls') && prodData['imageUrls'] != null && (prodData['imageUrls'] as List).isNotEmpty) {
                              finalImageUrl = prodData['imageUrls'][0];
                            } else if (prodData['imageUrl'] != null) {
                              finalImageUrl = prodData['imageUrl'];
                            }
                          }

                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                            child: ListTile(
                              contentPadding: const EdgeInsets.all(12),
                              leading: Container(
                                width: 60, height: 60,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.grey.shade100),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: (finalImageUrl != null && finalImageUrl.startsWith('http'))
                                      ? Image.network(
                                          finalImageUrl,
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) =>
                                              const Icon(Icons.broken_image_outlined, color: Colors.grey),
                                        )
                                      : const Icon(Icons.shopping_bag_outlined, color: Colors.grey),
                                ),
                              ),
                              title: Text(offer['productName'] ?? 'عرض بدون اسم',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text("سعر ال$unitName", style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                  Text("${price.toStringAsFixed(2)} ج.م",
                                      style: const TextStyle(color: Color(0xFF43B97F), fontWeight: FontWeight.bold)),
                                ],
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (qty > 0) ...[
                                    _cartButton(Icons.remove, () => _updateCart(oId, price, -1)),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 10),
                                      child: Text("$qty", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                    ),
                                  ],
                                  _cartButton(Icons.add, () => _updateCart(oId, price, 1)),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
            if (_demoCart.isNotEmpty)
              SafeArea(
                top: false,
                child: _buildCartSummary(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _cartButton(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF43B97F).withOpacity(0.1),
          borderRadius: BorderRadius.circular(10)
        ),
        child: Icon(icon, size: 20, color: const Color(0xFF43B97F)),
      ),
    );
  }

  Widget _buildCartSummary() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 25),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 15, offset: const Offset(0, -5))],
        borderRadius: const BorderRadius.only(topLeft: Radius.circular(30), topRight: Radius.circular(30)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("إجمالي الفاتورة التقريبية", style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              Text("${_totalAmount.toStringAsFixed(2)} ج.م",
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF43B97F))),
            ],
          ),
          ElevatedButton(
            onPressed: () {
              setState(() { _demoCart.clear(); _totalAmount = 0.0; });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade50,
              foregroundColor: Colors.red,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
            ),
            child: const Text("مسح", style: TextStyle(fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }
}

