import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:convert';
import 'add_new_customer.dart';

class VisitScreen extends StatefulWidget {
  const VisitScreen({super.key});

  @override
  State<VisitScreen> createState() => _VisitScreenState();
}

class _VisitScreenState extends State<VisitScreen> {
  bool _isLoading = true;
  bool _isVisiting = false;
  String? _currentVisitId;
  String? _currentCustomerName;
  Map<String, dynamic>? _userData;

  List<DocumentSnapshot> _customers = [];
  String? _selectedCustomerId;
  final TextEditingController _notesController = TextEditingController();
  String? _visitStatus;

  @override
  void initState() {
    super.initState();
    _checkInitialStatus();
  }

  Future<void> _checkInitialStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final userDataString = prefs.getString('userData');

    if (userDataString == null) {
      _showErrorPage("يجب تسجيل الدخول أولاً");
      return;
    }

    _userData = jsonDecode(userDataString);
    final repCode = _userData!['repCode'];

    final logQuery = await FirebaseFirestore.instance
        .collection('daily_logs')
        .where('repCode', isEqualTo: repCode)
        .where('status', isEqualTo: 'open')
        .limit(1)
        .get();

    if (logQuery.docs.isEmpty) {
      _showErrorPage("يجب بدء يوم العمل من الصفحة الرئيسية أولاً");
      return;
    }

    _currentVisitId = prefs.getString('currentVisitId');
    _currentCustomerName = prefs.getString('currentCustomerName');

    if (_currentVisitId != null) {
      setState(() {
        _isVisiting = true;
        _isLoading = false;
      });
    } else {
      _loadCustomers(repCode);
    }
  }

  Future<void> _loadCustomers(String repCode) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where('repCode', isEqualTo: repCode)
          .where('role', isEqualTo: 'buyer')
          .get();

      setState(() {
        _customers = snap.docs;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Error loading customers: $e");
    }
  }

  // دالة جلب الموقع مع طلب الإذن (تم تحسينها لتتوافق مع منطق الـ GPS)
  Future<Position?> _getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("❌ يرجى تفعيل خدمة الموقع (GPS)")),
      );
      return null;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("❌ تم رفض إذن الموقع")),
        );
        return null;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("❌ إذن الموقع مرفوض نهائياً من الإعدادات")),
      );
      return null;
    }

    return await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
  }

  Future<void> _startVisit() async {
    if (_selectedCustomerId == null) return;

    setState(() => _isLoading = true);

    // جلب الموقع قبل بدء الزيارة
    Position? position = await _getCurrentLocation();
    
    // إذا لم يتمكن من جلب الموقع، نعطي خياراً للمندوب (أو نمنعه حسب رغبتك)
    // هنا سنكمل الزيارة حتى لو الموقع فارغ لكن سنحاول جلبه أولاً
    
    final customer = _customers.firstWhere((doc) => doc.id == _selectedCustomerId);
    final customerName = customer['fullname'];

    final visitData = {
      'repCode': _userData!['repCode'],
      'repName': _userData!['fullname'],
      'customerId': _selectedCustomerId,
      'customerName': customerName,
      'startTime': FieldValue.serverTimestamp(),
      'status': "in_progress",
      'location': position != null
          ? {'lat': position.latitude, 'lng': position.longitude}
          : null,
    };

    final docRef = await FirebaseFirestore.instance.collection('visits').add(visitData);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('currentVisitId', docRef.id);
    await prefs.setString('currentCustomerName', customerName);

    setState(() {
      _currentVisitId = docRef.id;
      _currentCustomerName = customerName;
      _isVisiting = true;
      _isLoading = false;
    });
  }

  Future<void> _endVisit() async {
    if (_visitStatus == null) return;

    setState(() => _isLoading = true);

    await FirebaseFirestore.instance.collection('visits').doc(_currentVisitId).update({
      'status': _visitStatus,
      'notes': _notesController.text,
      'endTime': FieldValue.serverTimestamp(),
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('currentVisitId');
    await prefs.remove('currentCustomerName');

    setState(() {
      _isVisiting = false;
      _currentVisitId = null;
      _currentCustomerName = null;
      _visitStatus = null;
      _notesController.clear();
      _isLoading = false;
    });
    _loadCustomers(_userData!['repCode']);
  }

  void _showErrorPage(String msg) {
    if (!mounted) return;
    setState(() => _isLoading = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      appBar: AppBar(
        title: const Text("تسجيل زيارة عميل", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF43B97F),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: _isVisiting ? _buildEndVisitUI() : _buildStartVisitUI(),
      ),
    );
  }

  Widget _buildStartVisitUI() {
    return Column(
      children: [
        const Icon(Icons.location_on, size: 80, color: Color(0xFF43B97F)),
        const SizedBox(height: 10),
        const Text("اختر العميل من قائمتك", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 20),
        DropdownButtonFormField<String>(
          decoration: const InputDecoration(border: OutlineInputBorder(), labelText: "قائمة العملاء"),
          value: _selectedCustomerId,
          items: _customers.map((doc) {
            return DropdownMenuItem(value: doc.id, child: Text(doc['fullname']));
          }).toList(),
          onChanged: (val) => setState(() => _selectedCustomerId = val),
        ),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          onPressed: _selectedCustomerId == null ? null : _startVisit,
          icon: const Icon(Icons.play_arrow),
          label: const Text("بدء الزيارة الآن"),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF43B97F),
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 55),
          ),
        ),
        const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Divider()),
        ElevatedButton.icon(
          onPressed: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const AddNewCustomerScreen()),
            );
            _loadCustomers(_userData!['repCode']);
          },
          icon: const Icon(Icons.person_add),
          label: const Text("تسجيل عميل جديد (غير موجود بالقائمة)"),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue.shade700,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 55),
          ),
        ),
      ],
    );
  }

  Widget _buildEndVisitUI() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(10)),
          child: Row(
            children: [
              const Icon(Icons.store, color: Colors.blue),
              const SizedBox(width: 10),
              Expanded(
                child: Text("أنت الآن في زيارة لـ: $_currentCustomerName",
                    style: const TextStyle(fontSize: 16, color: Colors.blue, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 25),
        DropdownButtonFormField<String>(
          decoration: const InputDecoration(border: OutlineInputBorder(), labelText: "نتيجة الزيارة"),
          items: const [
            DropdownMenuItem(value: "sold", child: Text("✅ تم عمل طلبية")),
            DropdownMenuItem(value: "followup", child: Text("⏳ متابعة لاحقاً")),
            DropdownMenuItem(value: "busy", child: Text("🚪 العميل غير متاح / مشغول")),
            DropdownMenuItem(value: "rejected", child: Text("❌ مرفوضة")),
          ],
          onChanged: (val) => setState(() => _visitStatus = val),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _notesController,
          maxLines: 4,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: "ملاحظات وتفاصيل الزيارة",
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 30),
        ElevatedButton(
          onPressed: _visitStatus == null ? null : _endVisit,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.redAccent,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 60),
          ),
          child: const Text("إنهاء الزيارة وحفظ البيانات", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}

