import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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
        backgroundColor: const Color(0xFFF8F9FA),
        appBar: AppBar(
          title: const Text("متجر أكسب (نسخة المندوب)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF2c3e50),
          elevation: 0.5,
          bottom: TabBar(
            controller: _tabController,
            labelColor: const Color(0xFF3498db),
            unselectedLabelColor: Colors.grey,
            indicatorColor: const Color(0xFF3498db),
            tabs: const [
              Tab(icon: Icon(Icons.category_outlined), text: "الأقسام"),
              Tab(icon: Icon(Icons.storefront_outlined), text: "التجار"),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildCategoriesGrid(),
            _buildTradersList(),
          ],
        ),
      ),
    );
  }

  // 1. عرض الأقسام بشكل شبكي بسيط
  Widget _buildCategoriesGrid() {
    return StreamBuilder<QuerySnapshot>(
      stream: _db.collection('categories').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const Center(child: Text("حدث خطأ ما"));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        final docs = snapshot.data!.docs;

        return GridView.builder(
          padding: const EdgeInsets.all(15),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3, // 3 أعمدة ليكون خفيفاً
            childAspectRatio: 0.8,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            var cat = docs[index].data() as Map<String, dynamic>;
            return InkWell(
              onTap: () {
                // هنا مستقبلاً نفتح منتجات القسم
              },
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 5)],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    cat['imageUrl'] != null 
                        ? Image.network(cat['imageUrl'], height: 50, width: 50, fit: BoxFit.contain)
                        : const Icon(Icons.image_not_supported, size: 40, color: Colors.grey),
                    const SizedBox(height: 8),
                    Text(
                      cat['name'] ?? '',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
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

  // 2. عرض قائمة التجار
  Widget _buildTradersList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _db.collection('users').where('role', isEqualTo: 'merchant').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        
        final traders = snapshot.data!.docs;

        return ListView.builder(
          padding: const EdgeInsets.all(10),
          itemCount: traders.length,
          itemBuilder: (context, index) {
            var trader = traders[index].data() as Map<String, dynamic>;
            return Card(
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.blue.shade50,
                  child: const Icon(Icons.store, color: Color(0xFF3498db)),
                ),
                title: Text(trader['fullname'] ?? 'تاجر غير مسمى', style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text("كود التاجر: ${trader['repCode'] ?? '---'}"),
                trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                onTap: () {
                  // فتح ملف التاجر ومنتجاته
                },
              ),
            );
          },
        );
      },
    );
  }
}

