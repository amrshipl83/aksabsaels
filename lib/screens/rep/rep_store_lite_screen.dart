import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart'; // تأكد من إضافة المكتبة في pubspec.yaml
import 'rep_sub_categories_screen.dart';
import 'RepTradersLiteScreen.dart';

class RepStoreLiteScreen extends StatefulWidget {
  const RepStoreLiteScreen({super.key});

  @override
  State<RepStoreLiteScreen> createState() => _RepStoreLiteScreenState();
}

class _RepStoreLiteScreenState extends State<RepStoreLiteScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  Position? _userPosition; // تخزين الموقع لتمريره للطلبات الفرعية

  @override
  void initState() {
    super.initState();
    // نفحص الإذن فور الدخول لتهيئة البيانات
    _handleLocationPermission();
  }

  // دالة فحص وطلب الإذن مع رسالة الإفصاح
  Future<void> _handleLocationPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      // 🟢 رسالة الإفصاح الاحترافية (Prominent Disclosure)
      bool? proceed = await _showDisclosureDialog();
      if (proceed != true) return;

      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    if (permission == LocationPermission.deniedForever) {
      _showErrorSnackBar("إذن الموقع مرفوض نهائياً، يرجى تفعيله من الإعدادات.");
      return;
    }

    // إذا وصلنا هنا، الإذن متاح
    Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    setState(() => _userPosition = pos);
  }

  Future<bool?> _showDisclosureDialog() {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: const Row(
            children: [
              Icon(Icons.location_on, color: Color(0xFF4CAF50)),
              SizedBox(width: 8),
              Text("تحسين تجربة المتجر"),
            ],
          ),
          content: const Text(
            "يقوم تطبيق أكسب بجمع بيانات الموقع الجغرافي لتمكين ميزة فلترة الموردين والمنتجات المتاحة في نطاقك الحالي، حتى تتمكن من تقديم الطلبات للعملاء بدقة وبناءً على التغطية الجغرافية للموردين.",
            style: TextStyle(fontSize: 14, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("ليس الآن", style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4CAF50)),
              child: const Text("موافق، ابدأ الفلترة", style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _showErrorSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _navigateToTraders(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RepTradersLiteScreen(
          // نمرر الموقع الحالي لصفحة التجار عشان متعملش فحص تاني
          initialPosition: _userPosition, 
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        appBar: AppBar(
          title: const Text("متجر أكسب - الأقسام",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF2c3e50),
          elevation: 0.5,
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.storefront_rounded, color: Color(0xFF4CAF50)),
              onPressed: () => _navigateToTraders(context),
            )
          ],
        ),
        // 🟢 استخدام SafeArea لضمان عدم تداخل المحتوى مع النوتش أو أزرار النظام
        body: SafeArea(
          child: _buildMainCategoriesGrid(),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _navigateToTraders(context),
          backgroundColor: const Color(0xFF4CAF50),
          icon: const Icon(Icons.location_on, color: Colors.white),
          label: const Text("الموردين المتاحين حولك",
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  Widget _buildMainCategoriesGrid() {
    return StreamBuilder<QuerySnapshot>(
      stream: _db
          .collection('mainCategory')
          .where('status', isEqualTo: 'active')
          .orderBy('order', descending: false)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const Center(child: Text("حدث خطأ في تحميل الأقسام"));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Color(0xFF4CAF50)));

        final docs = snapshot.data!.docs;

        return GridView.builder(
          // الـ Padding السفلي 100 لضمان ابتعاد العناصر تماماً عن الـ FAB
          padding: const EdgeInsets.fromLTRB(15, 15, 15, 100),
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
                      // نقدر نمرر الموقع هنا برضه لو صفحة الأقسام بتحتاج فلترة
                      currentPosition: _userPosition, 
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
                            ? Image.network(cat['imageUrl'], fit: BoxFit.contain,
                                // تحسين تجربة المستخدم أثناء تحميل الصور
                                errorBuilder: (c, e, s) => const Icon(Icons.broken_image_outlined, size: 50, color: Colors.grey),
                              )
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

