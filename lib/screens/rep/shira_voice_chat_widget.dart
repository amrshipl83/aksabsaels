import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const Color kPrimaryColor = Color(0xFF43B97F);
const Color kSecondaryColor = Color(0xFF1A2C3D);

class ChatMessage {
  final String text;
  final bool isUser;
  final String? audioUrl;
  final DateTime timestamp;

  ChatMessage({
    required this.text,
    required this.isUser,
    this.audioUrl,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

class ShiraVoiceChatWidget extends StatefulWidget {
  final String cloudFunctionUrl;
  final String userRole; // e.g. 'sales_representative', 'company_agent'

  const ShiraVoiceChatWidget({
    super.key,
    required this.cloudFunctionUrl,
    required this.userRole,
  });

  @override
  State<ShiraVoiceChatWidget> createState() => _ShiraVoiceChatWidgetState();
}

class _ShiraVoiceChatWidgetState extends State<ShiraVoiceChatWidget> {
  final List<ChatMessage> _messages = [];
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  late AudioRecorder _audioRecorder;
  late AudioPlayer _audioPlayer;

  bool _isRecording = false;
  bool _isLoading = false;
  bool _isPlayingAudio = false;
  String? _currentlyPlayingUrl;

  @override
  void initState() {
    super.initState();
    _audioRecorder = AudioRecorder();
    _audioPlayer = AudioPlayer();

    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _isPlayingAudio = (state == PlayerState.playing);
        });
      }
    });

    // رسالة الترحيب الافتراضية
    _messages.add(ChatMessage(
      text: "أهلاً بك يا بطل! أنا شيرا، مساعدك الذكي لإدارة العهدة، تتبع الشحنات، واستعراض نقاط الأمان. كيف أستطيع مساعدتك اليوم؟",
      isUser: false,
    ));
  }

  @override
  void dispose() {
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // بدء التسجيل الصوتي
  Future<void> _startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final Directory appFolder = await getApplicationDocumentsDirectory();
        final String filePath = '${appFolder.path}/audio_${DateTime.now().millisecondsSinceEpoch}.m4a';

        await _audioRecorder.start(
          const RecordConfig(encoder: AudioEncoder.aacLc),
          path: filePath,
        );
        setState(() => _isRecording = true);
      }
    } catch (e) {
      debugPrint("خطأ أثناء بدء التسجيل: $e");
    }
  }

  // إيقاف التسجيل وإرساله فوراً
  Future<void> _stopAndSendRecording() async {
    try {
      final String? path = await _audioRecorder.stop();
      setState(() => _isRecording = false);

      if (path != null) {
        File audioFile = File(path);
        _sendMessage(audioFile: audioFile);
      }
    } catch (e) {
      debugPrint("خطأ أثناء إيقاف التسجيل: $e");
    }
  }

  // إرسال النص أو التسجيل إلى Cloud Function
  Future<void> _sendMessage({File? audioFile}) async {
    final text = _textController.text.trim();
    if (text.isEmpty && audioFile == null) return;

    _textController.clear();

    setState(() {
      _messages.add(ChatMessage(
        text: audioFile != null ? "🎙 [تسجيل صوتي]" : text,
        isUser: true,
      ));
      _isLoading = true;
    });
    _scrollToBottom();

    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataString = prefs.getString('userData');
      String uid = "";
      if (userDataString != null) {
        final userData = jsonDecode(userDataString);
        uid = userData['uid'] ?? userData['id'] ?? userData['repCode'] ?? '';
      }

      var request = http.MultipartRequest(
        'POST',
        Uri.parse(widget.cloudFunctionUrl),
      );

      request.fields['uid'] = uid;
      request.fields['role'] = widget.userRole;
      request.fields['isAudio'] = (audioFile != null).toString();

      if (text.isNotEmpty) {
        request.fields['message'] = text;
      }

      if (audioFile != null) {
        request.files.add(await http.MultipartFile.fromPath(
          'file',
          audioFile.path,
          filename: 'voice_note.m4a',
        ));
      }

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final replyText = data['reply'] ?? data['message'] ?? 'تم استلام الطلب.';
        final audioUrl = data['audioUrl'] ?? data['audio_url'];

        setState(() {
          _messages.add(ChatMessage(
            text: replyText,
            isUser: false,
            audioUrl: audioUrl,
          ));
        });

        // تشغيل صوت الرد تلقائياً إذا وُجد
        if (audioUrl != null && audioUrl.toString().isNotEmpty) {
          _playAudio(audioUrl);
        }
      } else {
        _addErrorResponse("حدث خطأ في التواصل مع السيرفر، يرجى المحاولة لاحقاً.");
      }
    } catch (e) {
      debugPrint("Error sending chat request: $e");
      _addErrorResponse("عذراً، يرجى التأكد من اتصال الإنترنت وحاول مجدداً.");
    } finally {
      setState(() => _isLoading = false);
      _scrollToBottom();
    }
  }

  void _addErrorResponse(String errorText) {
    setState(() {
      _messages.add(ChatMessage(
        text: errorText,
        isUser: false,
      ));
    });
  }

  // تشغيل وإيقاف الرد الصوتي
  Future<void> _playAudio(String url) async {
    if (_isPlayingAudio && _currentlyPlayingUrl == url) {
      await _audioPlayer.pause();
    } else {
      await _audioPlayer.stop();
      await _audioPlayer.play(UrlSource(url));
      setState(() {
        _currentlyPlayingUrl = url;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 15,
            spreadRadius: 2,
          )
        ],
      ),
      child: Column(
        children: [
          // شريط العنوان العلوي
          _buildHeader(),
          const Divider(height: 1),

          // منطقة الرسائل
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                return _buildMessageBubble(_messages[index]);
              },
            ),
          ),

          // مؤشر التحميل
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: kPrimaryColor),
                  ),
                  SizedBox(width: 10),
                  Text("شيرا تفكر الآن...", style: TextStyle(color: Colors.grey, fontSize: 13)),
                ],
              ),
            ),

          // شريط الإدخال والتسجيل
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: kPrimaryColor.withOpacity(0.15),
            child: const Icon(Icons.support_agent_rounded, color: kPrimaryColor),
          ),
          const SizedBox(width: 12),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "المساعد الميداني الذكي (شيرا)",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: kSecondaryColor),
              ),
              Text(
                "متصل لإدارة العهدة والخدمات اللوجستية",
                style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.w500),
              ),
            ],
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.grey),
            onPressed: () => Navigator.of(context).pop(),
          )
        ],
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage msg) {
    return Align(
      alignment: msg.isUser ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: msg.isUser ? kPrimaryColor : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(msg.isUser ? 0 : 16),
            bottomRight: Radius.circular(msg.isUser ? 16 : 0),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              msg.text,
              style: TextStyle(
                color: msg.isUser ? Colors.white : kSecondaryColor,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            if (msg.audioUrl != null) ...[
              const SizedBox(height: 8),
              InkWell(
                onTap: () => _playAudio(msg.audioUrl!),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: kPrimaryColor.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        (_isPlayingAudio && _currentlyPlayingUrl == msg.audioUrl)
                            ? Icons.pause_circle_filled_rounded
                            : Icons.play_circle_fill_rounded,
                        color: kPrimaryColor,
                        size: 24,
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        "استماع للرد الصوتي",
                        style: TextStyle(color: kPrimaryColor, fontSize: 12, fontWeight: FontWeight.bold),
                      )
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 10,
        bottom: MediaQuery.of(context).viewInsets.bottom + 10,
      ),
      color: Colors.white,
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(25),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: TextField(
                controller: _textController,
                decoration: const InputDecoration(
                  hintText: "اسأل عن العهدة، الشحنات، أو الأمانات...",
                  hintStyle: TextStyle(fontSize: 13, color: Colors.grey),
                  border: InputBorder.none,
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          
          // زر التسجيل الصوتي بالضغط المباشر
          GestureDetector(
            onLongPress: _startRecording,
            onLongPressUp: _stopAndSendRecording,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: EdgeInsets.all(_isRecording ? 14 : 10),
              decoration: BoxDecoration(
                color: _isRecording ? Colors.redAccent : kSecondaryColor,
                shape: BoxShape.circle,
              ),
              child: Icon(
                _isRecording ? Icons.mic_rounded : Icons.mic_none_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 6),

          // زر الإرسال النصي
          InkWell(
            onTap: () => _sendMessage(),
            child: const CircleAvatar(
              radius: 20,
              backgroundColor: kPrimaryColor,
              child: Icon(Icons.send_rounded, color: Colors.white, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}