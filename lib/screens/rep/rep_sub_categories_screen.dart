import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class RepSubCategoriesScreen extends StatelessWidget {
  final String mainCategoryId;
  final String mainCategoryName;

  const RepSubCategoriesScreen({
    super.key,
    required this.mainCategoryId,
    required this.mainCategoryName,
  });

  @override
  Widget build(BuildContext context) {
    final FirebaseFirestore db = FirebaseFirestore.instance;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        appBar: AppBar(
          title: Text(mainCategoryName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF2c3e50),
          elevation: 0.5,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: StreamBuilder<QuerySnapshot>(
          // جلب الأقسام الفرعية المرتبطة بالقسم الرئيسي المختار
          stream: db.collection('subCategory')
              .where('mainId', isEqualTo: mainCategoryId)
              .where('status', isEqualTo: 'active')
              .orderBy('order', descending: false)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) return const Center(child: Text("حدث خطأ ما"));
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Color(0xFF4a6491)));
            
            final docs = snapshot.data!.docs;

            if (docs.isEmpty) {
              return const Center(child: Text("لا توجد أقسام فرعية متاحة حالياً"));
            }

            return GridView.builder(
              padding: const EdgeInsets.all(15),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2, // عمودين كما في الويب
                childAspectRatio: 1.1,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: docs.length,
              itemBuilder: (context, index) {
                var subCat = docs[index].data() as Map<String, dynamic>;
                String subId = docs[index].id;

                return InkWell(
                  onTap: () {
                    // الخطوة القادمة: الانتقال لصفحة المنتجات الخاصة بهذا القسم الفرعي
                    print("فتح القسم الفرعي: $subId");
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(15),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 6,
                          offset: const Offset(0, 3),
                        )
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: subCat['imageUrl'] != null
                                ? Image.network(subCat['imageUrl'], fit: BoxFit.contain)
                                : const Icon(Icons.category_outlined, size: 40, color: Colors.grey),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12, left: 8, right: 8),
                          child: Text(
                            subCat['name'] ?? '',
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

