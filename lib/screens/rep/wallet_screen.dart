import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// استخدام نفس الثوابت اللونية للهوية
const Color kPrimaryColor = Color(0xFFB21F2D);
const Color kSecondaryColor = Color(0xFF1A2C3D);

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  final user = FirebaseAuth.instance.currentUser;
  final _amountController = TextEditingController();
  final _accountController = TextEditingController();
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F9FA),
        appBar: AppBar(
          title: const Text("محفظة العمولات", style: TextStyle(fontWeight: FontWeight.bold)),
          centerTitle: true,
          elevation: 0,
          backgroundColor: Colors.white,
          foregroundColor: kSecondaryColor,
        ),
        body: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('salesRep').doc(user?.uid).snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: kPrimaryColor));
            
            var data = snapshot.data!.data() as Map<String, dynamic>? ?? {};
            double balance = (data['walletBalance'] ?? 0).toDouble();
            String name = data['fullname'] ?? "مندوب مبيعات";
            String phone = data['phone'] ?? "";

            return SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildBalanceCard(balance),
                  const SizedBox(height: 30),
                  const Text("إجراءات سريعة", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 15),
                  _buildActionButton(
                    title: "سحب العمولات المتاحة",
                    icon: Icons.account_balance_wallet_rounded,
                    color: kPrimaryColor,
                    onTap: balance > 0 ? () => _showWithdrawSheet(balance, name, phone) : null,
                  ),
                  const SizedBox(height: 40),
                  _buildInfoSection(),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildBalanceCard(double balance) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [kSecondaryColor, Color(0xFF2C3E50)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: kSecondaryColor.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 6)),
        ],
      ),
      child: Column(
        children: [
          const Icon(Icons.stars_rounded, color: Colors.amber, size: 40),
          const SizedBox(height: 15),
          const Text("رصيدك الحالي", style: TextStyle(color: Colors.white70, fontSize: 16)),
          const SizedBox(height: 8),
          Text(
            "${balance.toStringAsFixed(2)} ج.م",
            style: const TextStyle(color: Colors.white, fontSize: 38, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({required String title, required IconData icon, required Color color, VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
        decoration: BoxDecoration(
          color: onTap == null ? Colors.grey[200] : Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 15),
            Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: onTap == null ? Colors.grey : Colors.black87)),
            const Spacer(),
            const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoSection() {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: Colors.amber.shade800),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              "يتم مراجعة طلبات السحب وتحويلها خلال 24 ساعة عمل.",
              style: TextStyle(color: Colors.amber.shade900, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  void _showWithdrawSheet(double balance, String name, String phone) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 25, right: 25, top: 25),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("طلب تسوية رصيد", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 25),
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: "المبلغ (ج.م)",
                prefixIcon: const Icon(Icons.money),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: _accountController,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: "رقم المحفظة (فودافون كاش ..)",
                prefixIcon: const Icon(Icons.phone_android),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 25),
            ElevatedButton(
              onPressed: _isLoading ? null : () => _processWithdraw(balance, name, phone),
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimaryColor,
                minimumSize: const Size(double.infinity, 55),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
              child: _isLoading 
                  ? const CircularProgressIndicator(color: Colors.white) 
                  : const Text("تأكيد طلب السحب", style: TextStyle(fontSize: 17, color: Colors.white)),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Future<void> _processWithdraw(double balance, String name, String phone) async {
    double amount = double.tryParse(_amountController.text) ?? 0;
    if (amount <= 0 || amount > balance) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("عذراً، الرصيد غير كافٍ")));
      return;
    }

    setState(() => _isLoading = true);
    try {
      await FirebaseFirestore.instance.collection('withdrawRequests').add({
        "accountNumber": _accountController.text,
        "amount": amount,
        "driverId": user?.uid,
        "driverName": name,
        "driverPhone": phone,
        "userRole": "salesRep",
        "status": "pending",
        "type": "EARNINGS_SETTLEMENT",
        "isAmountHeld": true,
        "processedByEngine": false,
        "createdAt": FieldValue.serverTimestamp(),
      });

      await FirebaseFirestore.instance.collection('salesRep').doc(user?.uid).update({
        'walletBalance': FieldValue.increment(-amount)
      });

      Navigator.pop(context);
      _amountController.clear();
      _accountController.clear();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: Colors.green, content: Text("تم إرسال طلب السحب بنجاح!")));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("حدث خطأ، حاول لاحقاً")));
    } finally {
      setState(() => _isLoading = false);
    }
  }
}

