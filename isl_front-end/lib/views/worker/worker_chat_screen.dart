import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http; // API call ke liye
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:isl_app/widgets/worker/worker_bottom_nav.dart';
import 'package:isl_app/widgets/worker/worker_header.dart'; 
import 'package:isl_app/views/worker/worker_documents_screen.dart';
import 'package:isl_app/views/worker/worker_alerts_screen.dart';
import 'package:isl_app/views/worker/worker_profile_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// WORKER CHAT SCREEN (Dynamic Quick Help & API Ready)
// ─────────────────────────────────────────────────────────────────────────────
class WorkerChatScreen extends StatefulWidget {
  const WorkerChatScreen({super.key});

  @override
  State<WorkerChatScreen> createState() => _WorkerChatScreenState();
}

class _WorkerChatScreenState extends State<WorkerChatScreen> {
  static const Color _darkBlue = Color(0xFF0F294D);
  static const Color _accentBlue = Color(0xFF163E75);

  final TextEditingController _msgCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  // Chat State
  List<Map<String, dynamic>> _messages = [];
  bool _isTyping = false;
  String _firstName = "";

  // Quick Help (Documents) State
  List<Map<String, dynamic>> _quickHelpDocs = [];
  bool _isLoadingQuickHelp = true;

  // UI ke liye cyclic colors
  static const List<Color> _docColors = [
    Color(0xFF2E7D32), // Green
    Color(0xFFF57C00), // Orange
    Color(0xFF7B1FA2), // Purple
    Color(0xFF1565C0), // Blue
    Color(0xFFC62828), // Red
  ];

  @override
  void initState() {
    super.initState();
    _initializeChat();
    _fetchDepartmentDocuments(); // API call for Quick Help
  }

  // --- 1. INITIALIZE CHAT ---
  Future<void> _initializeChat() async {
    final prefs = await SharedPreferences.getInstance();
    final userDataString = prefs.getString('user_data');
    
    if (userDataString != null) {
      try {
        final userData = jsonDecode(userDataString);
        final userObj = userData['user'] is Map ? userData['user'] : userData;
        String fullName = (userObj['full_name'] ?? userObj['name'] ?? '').toString();
        if (fullName.isNotEmpty) {
          _firstName = fullName.split(' ').first;
        }
      } catch (e) {
        debugPrint("Error parsing user data: $e");
      }
    }

    final String greetingText = _firstName.isNotEmpty 
        ? "Hello $_firstName! 👋\nI'm your ISL Assistant. How can I help you today?"
        : "Hello! 👋\nI'm your ISL Assistant. How can I help you today?";

    setState(() {
      _messages.add({
        'isUser': false,
        'text': greetingText,
        'time': DateFormat('hh:mm a').format(DateTime.now()),
      });
    });
  }

  // --- 2. FETCH DEPARTMENT DOCUMENTS (Dynamic Quick Help) ---
  Future<void> _fetchDepartmentDocuments() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token');

      // Apne backend URL ke hisaab se isey adjust kar lein agar server par hai
      final response = await http.get(
        Uri.parse('http://127.0.0.1:8000/api/documents/'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List results = data['results'] ?? [];
        
        if (mounted) {
          setState(() {
            // Hum sirf top 5 ya 6 documents uthayenge Quick Help ke liye
            _quickHelpDocs = List<Map<String, dynamic>>.from(results.take(6));
            _isLoadingQuickHelp = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoadingQuickHelp = false);
      }
    } catch (e) {
      debugPrint("Error fetching quick help docs: $e");
      if (mounted) setState(() => _isLoadingQuickHelp = false);
    }
  }

  // --- 3. SEND MESSAGE ---
  Future<void> _sendMessage({String? predefinedText}) async {
    final text = predefinedText ?? _msgCtrl.text.trim();
    if (text.isEmpty) return;

    _msgCtrl.clear();
    final currentTime = DateFormat('hh:mm a').format(DateTime.now());

    setState(() {
      _messages.add({
        'isUser': true,
        'text': text,
        'time': currentTime,
      });
      _isTyping = true;
    });
    
    _scrollToBottom();

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token');

      // Sahi endpoint: /api/chat/ask/
      final response = await http.post(
        Uri.parse('http://127.0.0.1:8000/api/chat/ask/'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'message': text, // Django views.py 'message' expect karta hai
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        // Django se 'answer' key aati hai
        final botReplyText = data['answer'] ?? "I didn't understand that.";

        if (mounted) {
          setState(() {
            _isTyping = false;
            _messages.add({
              'isUser': false,
              'text': botReplyText,
              'time': DateFormat('hh:mm a').format(DateTime.now()),
            });
          });
          _scrollToBottom();
        }
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isTyping = false;
          _messages.add({
            'isUser': false,
            'text': "Sorry, I am having trouble connecting to the server. Please try again.",
            'time': DateFormat('hh:mm a').format(DateTime.now()),
          });
        });
        _scrollToBottom();
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent + 100,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _handleNav(int index) {
    if (index == 0) return;
    Widget dest;
    switch (index) {
      case 1: dest = const WorkerDocumentsScreen(); break;
      case 2: dest = const WorkerAlertsScreen(); break;
      case 3: dest = const WorkerProfileScreen(); break;
      default: return;
    }
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => dest));
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const WorkerHeader(),
            _buildQuickHelp(),
            Expanded(
              child: Column(
                children: [
                  _buildChatHeader(),
                  Expanded(child: _buildMessagesList()),
                  _buildInputBar(),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: WorkerBottomNav(activeIndex: 0, onTap: _handleNav),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DYNAMIC QUICK HELP SECTION
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildQuickHelp() {
    if (_isLoadingQuickHelp) {
      return Container(
        color: Colors.white,
        padding: const EdgeInsets.all(10),
        alignment: Alignment.center,
        child: const SizedBox(
          width: 20, height: 10, 
          child: CircularProgressIndicator(strokeWidth: 2)
        ),
      );
    }

    // Agar koi document nahi mila backend se
    if (_quickHelpDocs.isEmpty) {
      return const SizedBox.shrink(); // UI hide kar dein
    }

    return Container(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          
          const SizedBox(height: 6), // Spacing kam ki
          SizedBox(
            height: 64, // 52 wasn't enough to fit the 36px icon + 2-line title below it — that mismatch was the overflow.
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _quickHelpDocs.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final doc = _quickHelpDocs[i];
                final title = doc['title']?.toString() ?? 'Document';
                final color = _docColors[i % _docColors.length]; // Color cycle karega

                return _QuickHelpCard(
                  title: title,
                  color: color,
                  onTap: () {
                    // Jab user is par click kare toh directly ek sawal bhej diya jaye
                    _sendMessage(predefinedText: "What are the guidelines for $title?");
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 6), // Spacing kam ki
          Divider(height: 1, thickness: 1, color: Colors.grey.shade200),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CHAT HEADER & LIST
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildChatHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: _darkBlue, borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.smart_toy, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('ISL Assistant', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1E293B))),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE3F2FD),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF90CAF9)),
                      ),
                      child: const Text('AI Powered', style: TextStyle(color: Color(0xFF1565C0), fontSize: 10, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Container(width: 7, height: 7, decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle)),
                    const SizedBox(width: 5),
                    const Text('Connected', style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.w500)),
                  ],
                ),
              ],
            ),
          ),
          Icon(Icons.more_vert, color: Colors.grey.shade500),
        ],
      ),
    );
  }

  Widget _buildMessagesList() {
    return Container(
      color: const Color(0xFFF8FAFC),
      child: ListView.builder(
        controller: _scrollCtrl,
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
        itemCount: _messages.length + (_isTyping ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _messages.length && _isTyping) {
            return const Padding(
              padding: EdgeInsets.only(bottom: 14),
              child: _TypingIndicator(),
            );
          }

          final msg = _messages[index];
          final isUser = msg['isUser'] as bool;
          final text = msg['text'] as String;
          final time = msg['time'] as String;

          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: isUser 
              ? _UserBubble(text: text, time: time)
              : _BotBubble(
                  time: time,
                  child: Text(text, style: const TextStyle(fontSize: 13.5, color: Color(0xFF1E293B))),
                ),
          );
        },
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // INPUT BAR
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          Icon(Icons.mic_none, color: Colors.grey.shade500, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _msgCtrl,
              onSubmitted: (_) => _sendMessage(),
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Type your message...',
                hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                isDense: true,
                filled: false,
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _isTyping ? null : () => _sendMessage(),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _isTyping ? Colors.grey.shade400 : _accentBlue,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.send, color: Colors.white, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PRIVATE WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _QuickHelpCard extends StatelessWidget {
  const _QuickHelpCard({
    required this.title,
    required this.color,
    required this.onTap,
  });
  
  final String title;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 80, // Text properly fit karne ke liye thora lamba kiya hai
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.grey.shade200),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              alignment: Alignment.center,
              // Sab documents ke liye generic File icon use kar rahe hain
              child: const Icon(Icons.description, color: Colors.white, size: 18),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 2, // Lamba naam ho toh cut jaye
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 9.5, color: Color(0xFF1E293B), height: 1.2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BotBubble extends StatelessWidget {
  const _BotBubble({required this.child, this.time});
  final Widget child;
  final String? time;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(5),
          decoration: const BoxDecoration(color: Color(0xFF0F294D), shape: BoxShape.circle),
          child: const Icon(Icons.smart_toy, color: Colors.white, size: 15),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(14),
                    bottomLeft: Radius.circular(14),
                    bottomRight: Radius.circular(14),
                  ),
                ),
                child: child,
              ),
              if (time != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 2),
                  child: Text(time!, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                ),
            ],
          ),
        ),
        const SizedBox(width: 40),
      ],
    );
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.text, required this.time});
  final String text;
  final String time;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Container(
          margin: const EdgeInsets.only(left: 50),
          padding: const EdgeInsets.all(12),
          decoration: const BoxDecoration(
            color: Color(0xFF0F294D),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(14),
              topRight: Radius.circular(14),
              bottomLeft: Radius.circular(14),
            ),
          ),
          child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 13.5)),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4, right: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(time, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
              const SizedBox(width: 4),
              Icon(Icons.done_all, size: 13, color: Colors.blue.shade400),
            ],
          ),
        ),
      ],
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(5),
          decoration: const BoxDecoration(color: Color(0xFF0F294D), shape: BoxShape.circle),
          child: const Icon(Icons.smart_toy, color: Colors.white, size: 15),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(14),
              bottomLeft: Radius.circular(14),
              bottomRight: Radius.circular(14),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(
              3,
              (i) => Container(
                width: 7,
                height: 7,
                margin: EdgeInsets.only(left: i == 0 ? 0 : 5),
                decoration: BoxDecoration(color: Colors.grey.shade500, shape: BoxShape.circle),
              ),
            ),
          ),
        ),
      ],
    );
  }
}