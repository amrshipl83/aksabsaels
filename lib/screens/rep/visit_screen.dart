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
  List<DocumentSnapshot> _filteredCustomers = [];
  String? _selectedCustomerId;
  final TextEditingController _searchController = TextEditingController();
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

    // 1. فحص يوم العمل (Log)
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

    // 2. فحص العلامة الذكية في مستند المندوب
    final repQuery = await FirebaseFirestore.instance
        .collection('salesRep')
        .where('repCode', isEqualTo: repCode)
        .limit(1)
        .get();

    if (repQuery.docs.isNotEmpty) {
      final repData = repQuery.docs.first.data();
      bool hasActiveVisit = repData['hasActiveVisit'] ?? false;

      if (hasActiveVisit) {
        // 3. البحث عن الزيارة المفتوحة
        final visitQuery = await FirebaseFirestore.instance
            .collection('visits')
            .where('repCode', isEqualTo: repCode)
            .where('status', isEqualTo: 'in_progress')
            .limit(1)
            .get();

        if (visitQuery.docs.isNotEmpty) {
          final visitDoc = visitQuery.docs.first;
          _currentVisitId = visitDoc.id;
          _currentCustomerName = visitDoc['customerName'];

          await prefs.setString('currentVisitId', _currentVisitId!);
          await prefs.setString('currentCustomerName', _currentCustomerName!);

          setState(() {
            _isVisiting = true;
            _isLoading = false;
          });
          return;
        }
      }
    }

    _currentVisitId = prefs.getString('currentVisitId');
    _currentCustomerName = prefs.getString('currentCustomerName');

    if (_currentVisitId != null) {
      setState(() {
        _isVisiting = true;
        _isLoading = false;
      });
    } else {
      _showLocationDisclosure(repCode);
    }
  }

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

  Future<void> _loadCustomers(String repCode) async {
    setState(() => _isLoading = true);
    try {
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

      List<DocumentSnapshot> allCustomers = snap.docs;
      List<DocumentSnapshot> nearbyCustomers = [];

      if (currentPos != null) {
        for (var doc in allCustomers) {
          try {
            var loc = doc['location'] as Map?;
            if (loc != null) {
              // حساب المسافة بين المندوب وكل عميل بالمتر
              double distance = Geolocator.distanceBetween(
                currentPos.latitude,
                currentPos.longitude,
                loc['lat'],
                loc['lng'],
              );

              // إضافة العميل فقط إذا كان في نطاق 500 متر
              if (distance <= 500) {
                nearbyCustomers.add(doc);
              }
            }
          } catch (e) {
            continue;
          }
        }

        // ترتيب القائمة المصغرة من الأقرب للأبعد
        nearbyCustomers.sort((a, b) {
          var locA = a['location'] as Map;
          var locB = b['location'] as Map;
          double distA = Geolocator.distanceBetween(currentPos!.latitude, currentPos!.longitude, locA['lat'], locA['lng']);
          double distB = Geolocator.distanceBetween(currentPos!.latitude, currentPos!.longitude, locB['lat'], locB['lng']);
          return distA.compareTo(distB);
        });
      } else {
        // في حال تعذر الحصول على الموقع، نعرض أول 30 عميل لضمان عدم توقف الشاشة
        nearbyCustomers = allCustomers.take(30).toList();
      }

      setState(() {
        _customers = nearbyCustomers;
        _filteredCustomers = nearbyCustomers;
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
    try {
      Position? position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);

      final customer = _customers.firstWhere((doc) => doc.id == _selectedCustomerId);
      final customerName = customer['fullname'];
      final customerAddress = (customer.data() as Map<String, dynamic>)['address'] ?? "عنوان غير مسجل";

      final visitData = {
        'repCode': _userData!['repCode'],
        'repName': _userData!['fullname'],
        'customerId': _selectedCustomerId,
        'customerName': customerName,
        'customerAddress': customerAddress,
        'startTime': FieldValue.serverTimestamp(),
        'status': "in_progress",
        'location': position != null ? {'lat': position.latitude, 'lng': position.longitude} : null,
      };

      final docRef = await FirebaseFirestore.instance.collection('visits').add(visitData);

      final repQuery = await FirebaseFirestore.instance
          .collection('salesRep')
          .where('repCode', isEqualTo: _userData!['repCode'])
          .limit(1)
          .get();
      if (repQuery.docs.isNotEmpty) {
        await repQuery.docs.first.reference.update({'hasActiveVisit': true});
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('currentVisitId', docRef.id);
      await prefs.setString('currentCustomerName', customerName);

      setState(() {
        _currentVisitId = docRef.id;
        _currentCustomerName = customerName;
        _isVisiting = true;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Start Visit Error: $e");
      setState(() => _isLoading = false);
    }
  }

  Future<void> _endVisit() async {
  if (_visitStatus == null) return;
  setState(() => _isLoading = true);
  try {
    // 1. الحصول على الموقع الحالي بدقة عند الإغلاق لضمان تسجيل آخر نقطة
    Position? position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high);

    // 2. تحديث مستند الزيارة (كما هو)
    await FirebaseFirestore.instance.collection('visits').doc(_currentVisitId).update({
      'status': _visitStatus,
      'notes': _notesController.text,
      'endTime': FieldValue.serverTimestamp(),
      'location': position != null ? {'lat': position.latitude, 'lng': position.longitude} : null,
    });

    // 3. تحديث حقل الـ location في daily_logs لضمان ثبات الماركر في لوحة التحكم
    final logQuery = await FirebaseFirestore.instance
        .collection('daily_logs')
        .where('repCode', isEqualTo: _userData!['repCode'])
        .where('status', isEqualTo: 'open')
        .limit(1)
        .get();

    if (logQuery.docs.isNotEmpty && position != null) {
      await logQuery.docs.first.reference.update({
        'location': {'lat': position.latitude, 'lng': position.longitude},
        'lastUpdate': FieldValue.serverTimestamp(), // لمتابعة وقت آخر تحديث
      });
    }

    // 4. تحديث علامة الزيارة في ملف المندوب (كما هو)
    final repQuery = await FirebaseFirestore.instance
        .collection('salesRep')
        .where('repCode', isEqualTo: _userData!['repCode'])
        .limit(1)
        .get();
    if (repQuery.docs.isNotEmpty) {
      await repQuery.docs.first.reference.update({'hasActiveVisit': false});
    }

    // 5. مسح البيانات المحلية والعودة للحالة الطبيعية
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
  } catch (e) {
    debugPrint("End Visit Error: $e");
    setState(() => _isLoading = false);
  }
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
        const Text("العملاء القريبون منك (في نطاق 500 متر)",
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
              ? const Center(child: Text("لا يوجد عملاء قريبون منك حالياً"))
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
            Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AddNewCustomerScreen())
            ).then((_) {
              if (_userData != null) {
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
              Text("زيارة نشطة لـ: $_currentCustomerName",
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
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

