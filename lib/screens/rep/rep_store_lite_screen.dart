import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
// استيراد الصفحة الجديدة للربط
import 'rep_sub_categories_screen.dart'; 

class RepStoreLiteScreen extends StatefulWidget {
  const RepStoreLiteScreen({super.key});

  @override
  State<RepStoreLiteScreen> createState() => _RepStoreLiteScreenState();
}

class _RepStoreLiteScreenState extends State<RepStoreLiteScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        appBar: AppBar(
          title: const Text("متجر أكسب", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF2c3e50),
          elevation: 0.5,
          bottom: TabBar(
            controller: _tabController,
            labelColor: const Color(0xFF4CAF50),
            unselectedLabelColor: Colors.grey,
            indicatorColor: const Color(0xFF4CAF50),
            tabs: const [
              Tab(icon: Icon(Icons.grid_view_rounded), text: "الأقسام الرئيسية"),
              Tab(icon: Icon(Icons.storefront_rounded), text: "التجار"),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildMainCategoriesGrid(),
            _buildTradersList(),
          ],
        ),
      ),
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
          padding: const EdgeInsets.all(15),
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
                // 🟢 الربط هنا: الانتقال لصفحة الأقسام الفرعية
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
                        padding: const EdgeInsets.all(10.0),
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

  Widget _buildTradersList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _db.collection('users').where('role', isEqualTo: 'merchant').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final traders = snapshot.data!.docs;

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: traders.length,
          itemBuilder: (context, index) {
            var trader = traders[index].data() as Map<String, dynamic>;
            return Card(
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFFE8F5E9),
                  child: const Icon(Icons.store, color: Color(0xFF4CAF50)),
                ),
                title: Text(trader['fullname'] ?? 'تاجر غير مسمى', 
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text("كود التاجر: ${trader['repCode'] ?? '---'}", 
                    style: const TextStyle(fontSize: 12)),
                trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
                onTap: () {
                  // مستقبلاً: فتح قائمة منتجات هذا التاجر فقط
                },
              ),
            );
          },
        );
      },
    );
  }
}

