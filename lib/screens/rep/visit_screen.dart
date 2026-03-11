import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sizer/sizer.dart';
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
  List<DocumentSnapshot> _filteredCustomers = []; // للقائمة المفلترة والبحث
  String? _selectedCustomerId;
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  String? _visitStatus;

  @override
  void initState() {
    super.initState();
    _checkInitialStatus();
  }

  // 1. فحص الحالة وطلب الإذن مع الإفصاح
  Future<void> _checkInitialStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final userDataString = prefs.getString('userData');

    if (userDataString == null) {
      _showErrorPage("يجب تسجيل الدخول أولاً");
      return;
    }

    _userData = jsonDecode(userDataString);
    final repCode = _userData!['repCode'];

    // فحص يوم العمل (Log)
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
      // إظهار رسالة الإفصاح قبل جلب العملاء لترتيبهم
      _showLocationDisclosure(repCode);
    }
  }

  // رسالة إفصاح جوجل (Prominent Disclosure)
  void _showLocationDisclosure(String repCode) async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.always || permission == LocationPermission.whileInUse) {
      _loadCustomers(repCode);
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.gps_fixed, color: Color(0xFF43B97F)),
            SizedBox(width: 10),
            Text("تحديد أقرب العملاء"),
          ],
        ),
        content: const Text(
          "يحتاج التطبيق للوصول لموقعك لترتيب قائمة العملاء حسب الأقرب إليك حالياً، مما يسهل عليك العثور على العميل وبدء الزيارة بسرعة.",
          style: TextStyle(fontSize: 14, height: 1.5),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF43B97F)),
            onPressed: () {
              Navigator.pop(context);
              _loadCustomers(repCode);
            },
            child: const Text("موافق", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // تحميل العملاء مع الترتيب الجغرافي
  Future<void> _loadCustomers(String repCode) async {
    setState(() => _isLoading = true);
    try {
      // طلب الإذن الرسمي
      LocationPermission permission = await Geolocator.requestPermission();
      Position? currentPos;
      if (permission == LocationPermission.always || permission == LocationPermission.whileInUse) {
        currentPos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      }

      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where('repCode', isEqualTo: repCode)
          .where('role', isEqualTo: 'buyer')
          .get();

      List<DocumentSnapshot> tempCustomers = snap.docs;

      // الترتيب الجغرافي (Geo-Sorting)
      if (currentPos != null) {
        tempCustomers.sort((a, b) {
          try {
            var locA = a['location'] as Map?;
            var locB = b['location'] as Map?;
            if (locA == null || locB == null) return 1;
            double distA = Geolocator.distanceBetween(currentPos!.latitude, currentPos!.longitude, locA['lat'], locA['lng']);
            double distB = Geolocator.distanceBetween(currentPos!.latitude, currentPos!.longitude, locB['lat'], locB['lng']);
            return distA.compareTo(distB);
          } catch (e) { return 0; }
        });
      }

      setState(() {
        _customers = tempCustomers;
        _filteredCustomers = tempCustomers;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Error: $e");
      setState(() => _isLoading = false);
    }
  }

  void _filterSearch(String query) {
    setState(() {
      _filteredCustomers = _customers.where((doc) {
        final name = doc['fullname'].toString().toLowerCase();
        final phone = doc['phone'].toString();
        return name.contains(query.toLowerCase()) || phone.contains(query);
      }).toList();
    });
  }

  Future<void> _startVisit() async {
    if (_selectedCustomerId == null) return;
    setState(() => _isLoading = true);

    Position? position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    final customer = _customers.firstWhere((doc) => doc.id == _selectedCustomerId);
    final customerName = customer['fullname'];

    final visitData = {
      'repCode': _userData!['repCode'],
      'repName': _userData!['fullname'],
      'customerId': _selectedCustomerId,
      'customerName': customerName,
      'startTime': FieldValue.serverTimestamp(),
      'status': "in_progress",
      'location': position != null ? {'lat': position.latitude, 'lng': position.longitude} : null,
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("زيارات المناديب", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF43B97F),
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF43B97F)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: _isVisiting ? _buildEndVisitUI() : _buildStartVisitUI(),
            ),
    );
  }

  Widget _buildStartVisitUI() {
    return Column(
      children: [
        TextField(
          controller: _searchController,
          onChanged: _filterSearch,
          decoration: InputDecoration(
            hintText: "بحث باسم المحل أو الرقم...",
            prefixIcon: const Icon(Icons.search, color: Color(0xFF43B97F)),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
            filled: true,
            fillColor: Colors.white,
          ),
        ),
        const SizedBox(height: 15),
        const Text("اختر العميل (الأقرب لك دائماً في البداية)",
            style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Container(
          height: 40.h,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: _filteredCustomers.isEmpty
            ? const Center(child: Text("لا يوجد عملاء متاحين"))
            : ListView.builder(
                itemCount: _filteredCustomers.length,
                itemBuilder: (context, index) {
                  var doc = _filteredCustomers[index];
                  bool isSelected = _selectedCustomerId == doc.id;
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isSelected ? const Color(0xFF43B97F) : Colors.grey[100],
                      child: Icon(Icons.store, color: isSelected ? Colors.white : Colors.grey),
                    ),
                    title: Text(doc['fullname'], style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(doc['phone']),
                    onTap: () => setState(() => _selectedCustomerId = doc.id),
                    trailing: isSelected ? const Icon(Icons.check_circle, color: Color(0xFF43B97F)) : null,
                  );
                },
              ),
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: _selectedCustomerId == null ? null : _startVisit,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF43B97F),
            minimumSize: const Size(double.infinity, 55),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text("بدء الزيارة الآن", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 15),
        OutlinedButton.icon(
          onPressed: () {
            // ✅ تم دمج الحل الأول: التحديث التلقائي عند العودة من شاشة التسجيل
            Navigator.push(
              context, 
              MaterialPageRoute(builder: (context) => const AddNewCustomerScreen())
            ).then((_) {
              if (_userData != null) {
                // إعادة تحميل العملاء لضمان ظهور العميل الجديد فوراً
                _loadCustomers(_userData!['repCode']);
              }
            });
          },
          icon: const Icon(Icons.person_add),
          label: const Text("تسجيل عميل جديد"),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 50),
            side: const BorderSide(color: Colors.blue),
            foregroundColor: Colors.blue,
          ),
        ),
      ],
    );
  }

  Widget _buildEndVisitUI() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(15)),
          child: Row(
            children: [
              const Icon(Icons.timer, color: Colors.green),
              const SizedBox(width: 10),
              Text("زيارة نشطة لـ: $_currentCustomerName", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
            ],
          ),
        ),
        const SizedBox(height: 20),
        DropdownButtonFormField<String>(
          decoration: const InputDecoration(border: OutlineInputBorder(), labelText: "نتيجة الزيارة"),
          items: const [
            DropdownMenuItem(value: "sold", child: Text("✅ تم عمل طلبية")),
            DropdownMenuItem(value: "followup", child: Text("⏳ متابعة لاحقاً")),
            DropdownMenuItem(value: "busy", child: Text("🚪 العميل غير متاح")),
            DropdownMenuItem(value: "rejected", child: Text("❌ مرفوضة")),
          ],
          onChanged: (val) => setState(() => _visitStatus = val),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _notesController,
          maxLines: 4,
          decoration: const InputDecoration(border: OutlineInputBorder(), labelText: "ملاحظات الزيارة"),
        ),
        const SizedBox(height: 30),
        ElevatedButton(
          onPressed: _visitStatus == null ? null : _endVisit,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.redAccent,
            minimumSize: const Size(double.infinity, 60),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text("إنهاء وحفظ الزيارة", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}

