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
  
  // سلة الديمو (Demo Cart)
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
      
      // تحديث الإجمالي اللحظي
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
              const Text("عروض المورد في منطقتك", style: TextStyle(fontSize: 11, color: Colors.green)),
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
                // فلترة المنتجات حسب الـ sellerId وحالة المنتج
                stream: _db.collection('products')
                    .where('sellerId', isEqualTo: widget.sellerId)
                    .where('status', isEqualTo: 'active')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                  
                  var products = snapshot.data!.docs;
                  
                  if (products.isEmpty) {
                    return const Center(child: Text("لا توجد منتجات متاحة لهذا المورد حالياً"));
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: products.length,
                    itemBuilder: (context, index) {
                      var product = products[index].data() as Map<String, dynamic>;
                      String pId = products[index].id;
                      double price = (product['price'] ?? 0.0).toDouble();
                      int qty = _demoCart[pId] ?? 0;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(10),
                          leading: Container(
                            width: 60, height: 60,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: product['imageUrl'] != null 
                                ? Image.network(product['imageUrl'], fit: BoxFit.contain)
                                : const Icon(Icons.image_not_supported, color: Colors.grey),
                          ),
                          title: Text(product['name'] ?? 'منتج غير مسمى', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          subtitle: Text("${price.toStringAsFixed(2)} ج.م", style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (qty > 0) ...[
                                _cartButton(Icons.remove, () => _updateCart(pId, price, -1)),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  child: Text("$qty", style: const TextStyle(fontWeight: FontWeight.bold)),
                                ),
                              ],
                              _cartButton(Icons.add, () => _updateCart(pId, price, 1)),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            
            // شريط إجمالي السلة (Demo Cart Bar)
            if (_demoCart.isNotEmpty) _buildCartSummary(),
          ],
        ),
      ),
    );
  }

  Widget _cartButton(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, size: 20, color: Colors.green),
      ),
    );
  }

  Widget _buildCartSummary() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, -2))],
        borderRadius: const BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("إجمالي محاكاة الطلب (${_demoCart.length} منتجات)", style: const TextStyle(fontSize: 12, color: Colors.grey)),
              Text("${_totalAmount.toStringAsFixed(2)} ج.م", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green)),
            ],
          ),
          ElevatedButton(
            onPressed: () {
              // مسح السلة (Reset)
              setState(() { _demoCart.clear(); _totalAmount = 0.0; });
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("تم مسح محاكاة الطلب")));
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade50, foregroundColor: Colors.red, elevation: 0),
            child: const Text("مسح"),
          )
        ],
      ),
    );
  }
}

