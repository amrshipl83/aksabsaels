import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SalesRepDashboard extends StatelessWidget {
  final String repCode;
  final DateTime currentDayStartTime;
  final VoidCallback onDataRefreshed;

  const SalesRepDashboard({
    super.key,
    required this.repCode,
    required this.currentDayStartTime,
    required this.onDataRefreshed,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // صف يحتوي على بطاقتين (الزيارات والعملاء الجدد)
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                title: 'الزيارات',
                collection: 'visits',
                icon: Icons.location_on_outlined,
                color: Colors.blue,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildStatCard(
                title: 'عملاء جدد',
                collection: 'users',
                icon: Icons.person_add_alt_1_outlined,
                color: Colors.orange,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // بطاقة عريضة للطلبات
        _buildStatCard(
          title: 'طلبات اليوم',
          collection: 'orders',
          icon: Icons.shopping_cart_checkout_outlined,
          color: Colors.green,
          isWide: true,
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required String title,
    required String collection,
    required IconData icon,
    required Color color,
    bool isWide = false,
  }) {
    return StreamBuilder<QuerySnapshot>(
      // جلب البيانات التي تخص المندوب وتمت بعد وقت بدء اليوم
      stream: FirebaseFirestore.instance
          .collection(collection)
          .where('repCode', isEqualTo: repCode)
          .where(collection == 'users' ? 'createdAt' : 'startTime', 
                 isGreaterThanOrEqualTo: Timestamp.fromDate(currentDayStartTime))
          .snapshots(),
      builder: (context, snapshot) {
        int count = 0;
        if (snapshot.hasData) {
          count = snapshot.data!.docs.length;
        }

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(15),
            border: Border(bottom: BorderSide(color: color, width: 4)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: isWide ? MainAxisAlignment.spaceAround : MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 30),
              const SizedBox(width: 15),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.grey, fontSize: 14)),
                  Text(
                    count.toString(),
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

