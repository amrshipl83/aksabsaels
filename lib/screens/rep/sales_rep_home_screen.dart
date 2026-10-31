import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
/* permission_handler removed: location handled via geolocator only */
import 'package:url_launcher/url_launcher.dart'; 
import 'dart:convert';
import 'sales_rep_dashboard.dart';
import 'visit_screen.dart';
import 'goals_screen.dart';
import 'my_customers_screen.dart';
import 'my_orders_screen.dart';
import 'rep_store_lite_screen.dart';
import 'rep_reports_screen.dart';
import 'profile_screen.dart'; 
import 'wallet_screen.dart'; 
import '../admin/offers_screen.dart';
import 'shira_voice_chat_widget.dart'; // استدعاء ويدجت مساعد شيرا الصوتي

// --- الثوابت اللونية لهوية أكسب مبيعات ---
const Color kPrimaryColor = Color(0xFFB21F2D); // أحمر أكسب
const Color kSecondaryColor = Color(0xFF1A2C3D);
const Color kSuccessColor = Color(0xFF2E7D32);
const Color kErrorColor = Color(0xFFC62828);
const Color kBgColor = Color(0xFFF8F9FA);

// Pure helper (unit-testable): builds the start-of-day briefing request text
// from data the rep is already allowed to see (own profile, own customers,
// workday-start fix). No other rep or company data is included.
String buildStartDayBriefingPrompt({
  required String repName,
  required String repCode,
  required int totalCustomers,
  required int nearbyCustomers,
  required List<String> nearbyNames,
  required bool hasLocation,
}) {
  final shown = nearbyNames.where((e) => e.isNotEmpty).take(10).join('، ');
  final areaLine = hasLocation
      ? 'موقع بداية اليوم مسجل، وعدد العملاء القريبين منك (نطاق 500 متر): $nearbyCustomers.'
      : 'تعذر تحديد موقع بداية اليوم، اعتمد على إجمالي العملاء فقط.';
  return 'افتح يوم عمل جديد للمندوب $repName (كود: $repCode). '
      'إجمالي عملائه: $totalCustomers. $areaLine'
      '${shown.isNotEmpty ? ' من الأقربين: $shown.' : ''}'
      ' جهز تحليلًا عامًا لبداية اليوم واقتراحات عملية مرتبة بالأولوية: '
      'من يزور أولًا، وأي مناطق يركز عليها، وتذكيرات ميدانية قصيرة.';
}

// One queued briefing request (latest wins): a day opened while another
// briefing is still in flight is served right after, never dropped.
class _QueuedBriefing {
  final Position fix;
  final String? logId;
  _QueuedBriefing(this.fix, this.logId);
}

// Pure restore gate (unit-testable): a stored briefing is shown only when it
// belongs to the currently open day.
bool shouldRestoreBriefing({required String? storedLogId, required String? currentLogId}) {
  return storedLogId != null && storedLogId.isNotEmpty && storedLogId == currentLogId;
}

class SalesRepHomeScreen extends StatefulWidget {
  const SalesRepHomeScreen({super.key});

  @override
  State<SalesRepHomeScreen> createState() => _SalesRepHomeScreenState();
}

class _SalesRepHomeScreenState extends State<SalesRepHomeScreen> {
  Map<String, dynamic>? repData;
  String? currentDayLogId;
  DateTime? currentDayStartTime;
  bool _isLoading = true;
  String _statusMessage = 'جاري التحقق...';
  bool _isDayOpen = false;
  // Start-of-day Shira briefing state. The briefing is requested through the
  // same Shira backend path when the rep opens a workday; its reply is kept
  // here until the rep opens the Shira sheet. The FAB frame highlights while
  // unseen suggestions exist. Never holds another rep's data.
  bool _hasNewShiraSuggestions = false;
  List<ChatMessage> _pendingShiraBriefing = [];
  bool _isBriefingLoading = false;
  Position? _lastStartFix;
  // Guards for the finding in review: re-entrant day transitions, stale
  // briefing overwrite, silent briefing loss, and restart loss.
  bool _isDayTransitioning = false;
  String? _briefingRequestedForLogId;
  Position? _lastBriefingFix;
  _QueuedBriefing? _queuedBriefing;
  final db = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _checkUserDataAndDayStatus();
    _setupNotifications();
  }

  // --- نظام التنبيهات ---
  Future<void> _setupNotifications() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;
    NotificationSettings settings = await messaging.getNotificationSettings();
    if (settings.authorizationStatus != AuthorizationStatus.authorized) {
      if (mounted) {
        bool? startRequest = await _showDisclosureDialog(
          title: 'تفعيل التنبيهات',
          body: 'نحتاج لتفعيل التنبيهات لإرسال تحديثات الطلبات الميدانية ورسائل الإدارة الهامة لك.',
          icon: Icons.notifications_active_outlined,
        );
        if (startRequest == true) {
          await messaging.requestPermission(alert: true, badge: true, sound: true);
        }
      }
    }
  }

  // --- نظام أذونات الموقع ---
  Future<bool> _handleLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showSnackBar("❌ يرجى تفعيل الـ GPS في هاتفك أولاً");
      return false;
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      bool? confirm = await _showDisclosureDialog(
        title: 'إذن الوصول للموقع',
        body: 'يتطلب "أكسب مبيعات" الوصول لموقعك الجغرافي لتسجيل "بصمة حضور العمل" وضمان تسجيل الزيارات للعملاء بدقة.',
        icon: Icons.location_on_outlined,
      );
      if (confirm == true) {
        permission = await Geolocator.requestPermission();
      }
    }
    if (permission == LocationPermission.deniedForever) {
      _showSnackBar("❌ إذن الموقع مرفوض دائماً، يرجى تفعيله من إعدادات الجهاز");
      return false;
    }
    return permission == LocationPermission.always || permission == LocationPermission.whileInUse;
  }

  Future<bool?> _showDisclosureDialog({required String title, required String body, required IconData icon}) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Column(
          children: [
            Icon(icon, size: 40, color: kPrimaryColor),
            const SizedBox(height: 10),
            Text(title, textAlign: TextAlign.center),
          ],
        ),
        content: Text(body, textAlign: TextAlign.center),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ليس الآن', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: kPrimaryColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: const Text('موافق وفهمت', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _checkUserDataAndDayStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final userDataString = prefs.getString('userData');
    if (userDataString == null) {
      if (mounted) Navigator.of(context).pushReplacementNamed('/');
      return;
    }
    repData = jsonDecode(userDataString);
    await _checkDayStatus();
  }

  Future<void> _checkDayStatus() async {
    if (repData == null) return;
    if (mounted) setState(() => _isLoading = true);
    try {
      final q = db.collection("daily_logs")
          .where("repCode", isEqualTo: repData!['repCode'])
          .where("status", isEqualTo: "open")
          .limit(1);
      final querySnapshot = await q.get();
      if (querySnapshot.docs.isNotEmpty) {
        final docData = querySnapshot.docs[0].data();
        currentDayLogId = querySnapshot.docs[0].id;
        currentDayStartTime = (docData['startTime'] as Timestamp?)?.toDate();
        setState(() {
          _isDayOpen = true;
          _statusMessage = 'يوم العمل مفتوح حالياً';
        });
        await _restorePendingBriefing();
        await _maybeResumeBriefing();
      } else {
        setState(() {
          _isDayOpen = false;
          currentDayLogId = null;
          currentDayStartTime = null;
          _statusMessage = 'يرجى بدء يوم العمل';
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Workday button entry point. Opening a day additionally requests a
  // start-of-day briefing through the same Shira backend path; the reply is
  // kept as pending chat messages and the Shira frame highlights.
  // Serialized entry point: concurrent taps during permission/GPS gaps
  // collapse into one transition (no duplicate day docs, no duplicate
  // briefings). The briefing is bound to the opened day log id.
  Future<void> _onWorkdayButton() async {
    if (_isDayTransitioning) return;
    _isDayTransitioning = true;
    try {
      if (_isDayOpen) {
        await _endDay();
      } else {
        _lastStartFix = null;
        await _startDay();
        final fix = _lastStartFix;
        _lastStartFix = null;
        final logId = currentDayLogId;
        if (fix != null && mounted && _isDayOpen && logId != null && _briefingRequestedForLogId != logId) {
          _briefingRequestedForLogId = logId;
          _requestStartDayBriefing(fix, logId);
        }
      }
    } finally {
      _isDayTransitioning = false;
    }
  }

  Future<void> _startDay() async {
    bool hasPermission = await _handleLocationPermission();
    if (!hasPermission) return;
    setState(() => _isLoading = true);
    try {
      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      _lastStartFix = position;
      await db.collection("daily_logs").add({
        'repCode': repData!['repCode'],
        'repName': repData!['fullname'],
        'startTime': FieldValue.serverTimestamp(),
        'status': "open",
        'startLocation': {
          'lat': position.latitude,
          'lng': position.longitude,
        },
      });
      await _checkDayStatus();
    } catch (e) {
      _showSnackBar("❌ فشل تسجيل الموقع، حاول مرة أخرى");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _endDay() async {
    bool hasPermission = await _handleLocationPermission();
    if (!hasPermission) return;
    setState(() => _isLoading = true);
    try {
      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      await db.collection("daily_logs").doc(currentDayLogId).update({
        'endTime': FieldValue.serverTimestamp(),
        'status': "closed",
        'endLocation': {
          'lat': position.latitude,
          'lng': position.longitude,
        },
      });
      await _checkDayStatus();
    } catch (e) {
      _showSnackBar("❌ فشل تسجيل موقع الإنهاء، حاول مرة أخرى");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: kPrimaryColor));
  }

  // --- فتح نافذة شات شيرا الصوتي المساعد ---
  // Requests a start-of-day briefing through the SAME Shira backend path the
  // chat widget uses (multipart POST with idToken/uid/role/lat/lng/message to
  // the same Cloud Run URL; same Nova reply + audio handling server-side).
  // Only data the rep may already see is used: own profile, own customers
  // (repCode-scoped query), and the workday-start fix captured in _startDay
  // (never another rep's data, never the visit fix). Fire-and-forget:
  // failures only debug-log and never block the workday.
  // Requests a start-of-day briefing through the SAME Shira backend path the
  // chat widget uses (multipart POST with idToken/uid/role/lat/lng/message to
  // the same Cloud Run URL; same Nova reply + audio handling server-side).
  // Only data the rep may already see is used: own profile, own customers
  // (repCode-scoped query), and the workday-start fix (never another rep's
  // data, never the visit fix). Fire-and-forget: failures debug-log and offer
  // an in-session retry; the workday itself is never blocked.
  Future<void> _requestStartDayBriefing(Position fix, String? logId) async {
    // Single-flight with latest-wins queue: a day opened while another
    // briefing is in flight is served right after, never silently dropped.
    if (_isBriefingLoading) {
      _queuedBriefing = _QueuedBriefing(fix, logId);
      return;
    }
    setState(() => _isBriefingLoading = true);
    _briefingRequestedForLogId = logId;
    _lastBriefingFix = fix;
    try {
      final repCode = repData?['repCode']?.toString() ?? '';
      final repName = repData?['fullname']?.toString() ?? 'المندوب';
      if (repCode.isEmpty) return;
      final snap = await db
          .collection('users')
          .where('repCode', isEqualTo: repCode)
          .where('role', isEqualTo: 'buyer')
          .get();
      final docs = snap.docs;
      final List<String> nearbyNames = [];
      int nearby = 0;
      for (final d in docs) {
        try {
          final loc = (d.data())['location'] as Map?;
          if (loc == null) continue;
          final double? la = (loc['lat'] as num?)?.toDouble();
          final double? ln = (loc['lng'] as num?)?.toDouble();
          if (la == null || ln == null) continue;
          final dist = Geolocator.distanceBetween(fix.latitude, fix.longitude, la, ln);
          if (dist <= 500) {
            nearby++;
            if (nearbyNames.length < 10) {
              nearbyNames.add((d.data())['fullname']?.toString() ?? '');
            }
          }
        } catch (_) {}
      }
      final prompt = buildStartDayBriefingPrompt(
        repName: repName,
        repCode: repCode,
        totalCustomers: docs.length,
        nearbyCustomers: nearby,
        nearbyNames: nearbyNames,
        hasLocation: true,
      );
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final idToken = await user.getIdToken();
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('https://shirachat-tmfag3rhdq-uc.a.run.app'),
      );
      request.headers['Authorization'] = 'Bearer $idToken';
      request.fields['uid'] = user.uid;
      request.fields['role'] = repData?['role']?.toString() ?? 'sales_representative';
      request.fields['lat'] = fix.latitude.toString();
      request.fields['lng'] = fix.longitude.toString();
      request.fields['isAudio'] = 'false';
      request.fields['message'] = prompt;
      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode != 200) {
        _briefingRequestedForLogId = null;
        _offerBriefingRetry(logId);
        return;
      }
      final data = jsonDecode(response.body);
      final reply = (data['reply'] ?? data['message'] ?? '').toString();
      if (reply.isEmpty) {
        _briefingRequestedForLogId = null;
        _offerBriefingRetry(logId);
        return;
      }
      final audioUrl = data['audioUrl'] ?? data['audio_url'];
      if (!mounted) return;
      // Stale guard: a briefing that arrives after its day closed (or after a
      // newer day opened) is dropped instead of overwriting current state.
      if (currentDayLogId != logId || !_isDayOpen) return;
      setState(() {
        _pendingShiraBriefing = [
          ChatMessage(text: 'طلب تحليل بداية اليوم', isUser: true),
          ChatMessage(text: reply, isUser: false, audioUrl: audioUrl?.toString()),
        ];
        _hasNewShiraSuggestions = true;
      });
      await _storePendingBriefing(logId);
    } catch (e) {
      debugPrint('Start-day briefing skipped: $e');
      _briefingRequestedForLogId = null;
      _offerBriefingRetry(logId);
    } finally {
      if (mounted) setState(() => _isBriefingLoading = false);
      final queued = _queuedBriefing;
      _queuedBriefing = null;
      if (queued != null && mounted) {
        _requestStartDayBriefing(queued.fix, queued.logId);
      }
    }
  }

  // Informs the rep (same open day only) when the briefing could not be
  // fetched, with a one-tap retry. Never fires for a stale/closed day.
  void _offerBriefingRetry(String? logId) {
    if (!mounted || logId == null || currentDayLogId != logId || !_isDayOpen) return;
    if (_lastBriefingFix == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('تعذر جلب اقتراحات بداية اليوم — يمكنك المحاولة أو سؤال شيرا مباشرة'),
        action: SnackBarAction(
          label: 'إعادة المحاولة',
          onPressed: () {
            final fix = _lastBriefingFix;
            if (fix != null) _requestStartDayBriefing(fix, logId);
          },
        ),
      ),
    );
  }

  static const String _briefingPrefsKey = 'pending_briefing_v1';

  Future<void> _storePendingBriefing(String? logId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final items = _pendingShiraBriefing
          .map((m) => {'text': m.text, 'isUser': m.isUser, 'audioUrl': m.audioUrl})
          .toList();
      await prefs.setString(_briefingPrefsKey, jsonEncode({'logId': logId, 'items': items}));
    } catch (e) {
      debugPrint('Briefing persist skipped: $e');
    }
  }

  // Restart recovery, part 1: an arrived-but-unseen briefing is restored only
  // when it belongs to the currently open day (see shouldRestoreBriefing).
  Future<void> _restorePendingBriefing() async {
    try {
      if (_pendingShiraBriefing.isNotEmpty || _hasNewShiraSuggestions) return;
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_briefingPrefsKey);
      if (raw == null) return;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      if (!shouldRestoreBriefing(
        storedLogId: data['logId']?.toString(),
        currentLogId: currentDayLogId,
      )) {
        return;
      }
      final items = (data['items'] as List?) ?? [];
      final restored = items
          .whereType<Map<String, dynamic>>()
          .map((m) => ChatMessage(
                text: (m['text'] ?? '').toString(),
                isUser: m['isUser'] == true,
                audioUrl: m['audioUrl']?.toString(),
              ))
          .where((m) => m.text.isNotEmpty)
          .toList();
      if (restored.isEmpty || !mounted) return;
      setState(() {
        _pendingShiraBriefing = restored;
        _hasNewShiraSuggestions = true;
      });
    } catch (e) {
      debugPrint('Briefing restore skipped: $e');
    }
  }

  Future<void> _clearStoredBriefing() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_briefingPrefsKey);
    } catch (e) {
      debugPrint('Briefing clear skipped: $e');
    }
  }

  // Restart recovery, part 2: an open day with no briefing, no stored copy,
  // and no request yet this session gets one request (same path, one-shot
  // fix). Skipped while a fresh start is already driving its own request.
  Future<void> _maybeResumeBriefing() async {
    if (_pendingShiraBriefing.isNotEmpty) return;
    if (_briefingRequestedForLogId == currentDayLogId) return;
    if (_lastStartFix != null) return;
    if (!mounted || !_isDayOpen || currentDayLogId == null) return;
    final logId = currentDayLogId;
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      ).timeout(const Duration(seconds: 8));
      if (!mounted || !_isDayOpen || currentDayLogId != logId) return;
      _requestStartDayBriefing(pos, logId);
    } catch (_) {
      // No standing request recorded: a later refresh may retry.
    }
  }

  Future<void> _openShiraVoiceAssistant() async {
    // One-shot GPS for nearby-customer context (omitted silently on failure;
    // no continuous tracking, no extra permission prompt beyond the granted one).
    double? lat;
    double? lng;
    try {
      Position? pos = await Geolocator.getLastKnownPosition();
      pos ??= await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      ).timeout(const Duration(seconds: 8));
      lat = pos.latitude;
      lng = pos.longitude;
    } catch (_) {}
    final pendingBriefing = _pendingShiraBriefing;
    if (mounted) {
      setState(() {
        _pendingShiraBriefing = [];
        _hasNewShiraSuggestions = false;
      });
      await _clearStoredBriefing();
    }
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 0.85,
          child: ShiraVoiceChatWidget(
            cloudFunctionUrl: 'https://shirachat-tmfag3rhdq-uc.a.run.app',
            userRole: repData?['role'] ?? 'sales_representative',
            repLat: lat,
            repLng: lng,
            initialMessages: pendingBriefing,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: kBgColor,
        drawer: _buildMainDrawer(),
        appBar: AppBar(
          title: const Text('أكسب للمبيعات', style: TextStyle(fontWeight: FontWeight.bold)),
          centerTitle: true,
          backgroundColor: Colors.white,
          foregroundColor: kSecondaryColor,
          elevation: 0,
          actions: [
            IconButton(icon: const Icon(Icons.sync_rounded), onPressed: _checkDayStatus),
          ],
        ),
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: _checkDayStatus,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildUserInfoHeader(),
                  const SizedBox(height: 20),
                  _buildActionButtons(),
                  const SizedBox(height: 20),
                  if (_isDayOpen && currentDayStartTime != null)
                    SalesRepDashboard(
                      repCode: repData!['repCode'],
                      currentDayStartTime: currentDayStartTime!,
                      onDataRefreshed: _checkDayStatus,
                    )
                  else if (!_isLoading)
                    _buildEmptyState(),
                  if (_isLoading)
                    const Padding(
                      padding: EdgeInsets.only(top: 40),
                      child: CircularProgressIndicator(color: kPrimaryColor),
                    ),
                ],
              ),
            ),
          ),
        ),

        // --- 🚀 زر المساعد الصوتي (شيرا) العائم باللوجو والتصميم الجديد ---
        floatingActionButton: GestureDetector(
          onTap: _openShiraVoiceAssistant,
          child: Hero(
            tag: "rep_home_shira_btn",
            child: Container(
              width: 65,
              height: 65,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [kPrimaryColor, kSecondaryColor],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: kPrimaryColor.withOpacity(0.4),
                    blurRadius: 12,
                    spreadRadius: 2,
                    offset: const Offset(0, 4),
                  ),
                ],
                border: Border.all(color: _hasNewShiraSuggestions ? const Color(0xFFFFA000) : Colors.white, width: _hasNewShiraSuggestions ? 3 : 2),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // عرض صورة لوجو شيرا
                  ClipOval(
                    child: Image.asset(
                      'assets/images/shira_logo.png',
                      width: 52,
                      height: 52,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => 
                          const Icon(Icons.mic, color: Colors.white, size: 28),
                    ),
                  ),
                  // نقطة الاتصال التفاعلية
                  Positioned(
                    top: 3,
                    right: 3,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: const Color(0xFF2E7D32),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),

                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUserInfoHeader() {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.grey.shade200)),
      child: Row(children: [
        const Icon(Icons.info_outline_rounded, color: kPrimaryColor),
        const SizedBox(width: 10),
        Text(_statusMessage, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      ]),
    );
  }

  Widget _buildActionButtons() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _isLoading ? null : _onWorkdayButton,
        icon: Icon(_isDayOpen ? Icons.stop_rounded : Icons.play_arrow_rounded, size: 28),
        label: Text(_isDayOpen ? "إنهاء وردية العمل" : "بدء يوم عمل جديد", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        style: ElevatedButton.styleFrom(
          backgroundColor: _isDayOpen ? kErrorColor : kSuccessColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.only(top: 40),
      child: Column(children: [
        Icon(Icons.location_off_outlined, size: 80, color: Colors.grey.shade400),
        const SizedBox(height: 15),
        const Text('يجب فتح يوم العمل لتفعيل عدادات الإنجاز والزيارات والطلبات.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
      ]),
    );
  }

  Widget _buildMainDrawer() {
    return Drawer(
      child: Container(
        color: kSecondaryColor,
        child: SafeArea(
          child: Column(children: [
            UserAccountsDrawerHeader(
              decoration: const BoxDecoration(color: Color(0xFF14212D)),
              currentAccountPicture: const CircleAvatar(backgroundColor: kPrimaryColor, child: Icon(Icons.person, color: Colors.white, size: 40)),
              accountName: Text(repData?['fullname'] ?? 'مندوب مبيعات', style: const TextStyle(fontWeight: FontWeight.bold)),
              accountEmail: Text('كود الموظف: ${repData?['repCode'] ?? '...'}'),
            ),
            Expanded(
              child: ListView(children: [
                _drawerItem(Icons.dashboard_outlined, "الرئيسية", true, onTap: () => Navigator.pop(context)),
                // 🤖 إضافة خيار المساعد الذكي شيرا بالصورة التفاعلية داخل القائمة
                ListTile(
                  leading: Container(
                    width: 30,
                    height: 30,
                    decoration: const BoxDecoration(shape: BoxShape.circle),
                    child: ClipOval(
                      child: Image.asset(
                        'assets/images/shira_logo.png',
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => 
                            const Icon(Icons.psychology, color: kPrimaryColor),
                      ),
                    ),
                  ),
                  title: const Text("المساعد الذكي شيرا", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  onTap: () {
                    Navigator.pop(context);
                    _openShiraVoiceAssistant();
                  },
                ),
                _drawerItem(Icons.account_circle_outlined, "حسابي والإعدادات", false, onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (context) => const ProfileScreen()));
                }),
                _drawerItem(Icons.wallet_outlined, "محفظة العمولات", false, onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (context) => const WalletScreen()));
                }),
                _drawerItem(Icons.storefront_outlined, "المتجر", false, onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (context) => const RepStoreLiteScreen()));
                }),
                _drawerItem(Icons.track_changes_outlined, "الأهداف", false, onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (context) => const GoalsScreen()));
                }),
                _drawerItem(Icons.people_outline, "قائمة عملائي", false, onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (context) => const MyCustomersScreen()));
                }),
                _drawerItem(Icons.receipt_outlined, "طلباتي", false, onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (context) => const MyOrdersScreen()));
                }),
                _drawerItem(Icons.location_on_outlined, "بدء زيارة", false, onTap: () {
                  Navigator.pop(context);
                  if (_isDayOpen) {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const VisitScreen()));
                  } else {
                    _showSnackBar("❌ يرجى فتح اليوم أولاً لتسجيل الزيارات");
                  }
                }),
                _drawerItem(Icons.local_offer_outlined, "مركز العروض والجوائز", false, onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (context) => const OffersScreen()));
                }),
                _drawerItem(Icons.bar_chart_outlined, "تقارير الإنجاز", false, onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (context) => const RepReportsScreen()));
                }),
                _drawerItem(Icons.privacy_tip_outlined, "سياسة الخصوصية", false, onTap: () async {
                  Navigator.pop(context);
                  final Uri url = Uri.parse('https://aksab.shop/');
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  }
                }),
              ])),
            const Divider(color: Colors.white24),
            _drawerItem(Icons.logout, "تسجيل الخروج", false, color: Colors.redAccent, onTap: () async {
              await FirebaseAuth.instance.signOut();
              final prefs = await SharedPreferences.getInstance();
              await prefs.clear();
              if (mounted) Navigator.of(context).pushReplacementNamed('/');
            }),
          ]),
        ),
      ),
    );
  }

  Widget _drawerItem(IconData icon, String title, bool isSelected, {Color? color, VoidCallback? onTap}) {
    return ListTile(
      leading: Icon(icon, color: color ?? (isSelected ? kPrimaryColor : Colors.white70)),
      title: Text(title, style: TextStyle(color: color ?? Colors.white)),
      onTap: onTap,
    );
  }
}
