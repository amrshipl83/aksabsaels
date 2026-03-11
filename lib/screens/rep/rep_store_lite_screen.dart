import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'rep_sub_categories_screen.dart';
// 1. استيراد صفحة التجار الجديدة
import 'RepTradersLiteScreen.dart'; 

class RepStoreLiteScreen extends StatefulWidget {
  const RepStoreLiteScreen({super.key});

  @override
  State<RepStoreLiteScreen> createState() => _RepStoreLiteScreenState();
}

// قمنا بإزالة SingleTickerProviderStateMixin لعدم الحاجة للـ TabController
class _RepStoreLiteScreenState extends State<RepStoreLiteScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        appBar: AppBar(
          title: const Text("متجر أكسب - الأقسام", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF2c3e50),
          elevation: 0.5,
          centerTitle: true,
          // أضفنا أيقونة سريعة في الـ AppBar كخيار إضافي
          actions: [
            IconButton(
              icon: const Icon(Icons.storefront_rounded, color: Color(0xFF4CAF50)),
              onPressed: () => _navigateToTraders(context),
            )
          ],
        ),
        
        // الجسم يحتوي الآن على الأقسام فقط بشكل مباشر
        body: _buildMainCategoriesGrid(),

        // 2. إضافة الزر العائم للوصول السريع للموردين
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _navigateToTraders(context),
          backgroundColor: const Color(0xFF4CAF50),
          icon: const Icon(Icons.location_on, color: Colors.white),
          label: const Text("الموردين المتاحين حولك", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  // دالة الانتقال لصفحة التجار
  void _navigateToTraders(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const RepTradersLiteScreen()),
    );
  }

  Widget _buildMainCategoriesGrid() {
    return StreamBuilder<QuerySnapshot>(
      stream: _db.collection('mainCategory')
          .where('status', isEqualTo: 'active')
          .orderBy('order', descending: false)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const Center(child: Text("حدث خطأ في تحميل الأقسام"));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Color(0xFF4CAF50)));

        final docs = snapshot.data!.docs;

        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(15, 15, 15, 80), // زيادة الـ padding السفلي عشان الزر العائم ميغطيش الأقسام
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 1.1,
            crossAxisSpacing: 15,
            mainAxisSpacing: 15,
          ),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            var cat = docs[index].data() as Map<String, dynamic>;
            String catId = docs[index].id;

            return InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => RepSubCategoriesScreen(
                      mainCategoryId: catId,
                      mainCategoryName: cat['name'] ?? 'الأقسام',
                    ),
                  ),
                );
              },
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    )
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: cat['imageUrl'] != null
                            ? Image.network(cat['imageUrl'], fit: BoxFit.contain)
                            : const Icon(Icons.category_outlined, size: 50, color: Colors.grey),
                      ),
                    ),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: const BoxDecoration(
                        color: Color(0xFFF8F9FA),
                        borderRadius: BorderRadius.only(
                          bottomLeft: Radius.circular(15),
                          bottomRight: Radius.circular(15),
                        ),
                      ),
                      child: Text(
                        cat['name'] ?? '',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

