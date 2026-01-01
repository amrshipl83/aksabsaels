import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart'; // سنحتاجه لجلب الموقع كما في الـ HTML

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

  // التحقق من تسجيل الدخول وبداية اليوم والزيارات المعلقة
  Future<void> _checkInitialStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final userDataString = prefs.getString('userData');
    
    if (userDataString == null) {
      _showErrorPage("يجب تسجيل الدخول أولاً");
      return;
    }

    _userData = Map<String, dynamic>.from(Iterable.castFrom(userDataString as Iterable));
    final repCode = _userData!['repCode'];

    // 1. التحقق من فتح يوم العمل (daily_logs)
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

    // 2. التحقق من وجود زيارة نشطة في الـ Local Storage
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

  // جلب قائمة العملاء الخاصين بالمندوب
  Future<void> _loadCustomers(String repCode) async {
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .where('repCode', isEqualTo: repCode)
        .get();
    
    setState(() {
      _customers = snap.docs;
      _isLoading = false;
    });
  }

  // بدء زيارة جديدة (مع التقاط الموقع)
  Future<void> _startVisit() async {
    if (_selectedCustomerId == null) return;

    setState(() => _isLoading = true);
    
    Position? position;
    try {
      position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    } catch (e) {
      debugPrint("Location error: $e");
    }

    final customer = _customers.firstWhere((doc) => doc.id == _selectedCustomerId);
    final customerName = customer['fullname'];

    final visitData = {
      'repCode': _userData!['repCode'],
      'repName': _userData!['fullname'],
      'customerId': _selectedCustomerId,
      'customerName': customerName,
      'startTime': FieldValue.serverTimestamp(),
      'status': "in_progress",
      if (position != null) 'location': {'lat': position.latitude, 'lng': position.longitude},
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

  // إنهاء الزيارة
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
    setState(() {
      _isLoading = false;
    });
    // عرض تنبيه أو واجهة خطأ
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      appBar: AppBar(title: const Text("تسجيل زيارة"), backgroundColor: const Color(0xFF43B97F)),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: _isVisiting ? _buildEndVisitUI() : _buildStartVisitUI(),
      ),
    );
  }

  // واجهة بدء الزيارة
  Widget _buildStartVisitUI() {
    return Column(
      children: [
        const Text("اختر العميل لبدء الزيارة", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF43B97F), minimumSize: const Size(double.infinity, 50)),
        ),
      ],
    );
  }

  // واجهة إنهاء الزيارة
  Widget _buildEndVisitUI() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("أنت الآن في زيارة لـ: $_currentCustomerName", style: const TextStyle(fontSize: 18, color: Colors.blue, fontWeight: FontWeight.bold)),
        const SizedBox(height: 20),
        DropdownButtonFormField<String>(
          decoration: const InputDecoration(border: OutlineInputBorder(), labelText: "حالة الزيارة"),
          items: const [
            DropdownMenuItem(value: "sold", child: Text("تم البيع")),
            DropdownMenuItem(value: "followup", child: Text("متابعة لاحقاً")),
            DropdownMenuItem(value: "busy", child: Text("العميل مشغول")),
            DropdownMenuItem(value: "rejected", child: Text("مرفوضة")),
          ],
          onChanged: (val) => setState(() => _visitStatus = val),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _notesController,
          maxLines: 3,
          decoration: const InputDecoration(border: OutlineInputBorder(), labelText: "ملاحظات الزيارة"),
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: _visitStatus == null ? null : _endVisit,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, minimumSize: const Size(double.infinity, 50)),
          child: const Text("إنهاء الزيارة وحفظ النتائج", style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}

