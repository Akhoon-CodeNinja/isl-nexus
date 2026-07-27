import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:isl_app/widgets/worker/worker_bottom_nav.dart';
import 'package:isl_app/widgets/worker/worker_header.dart';
import 'package:isl_app/widgets/worker/worker_ai_mascot.dart'; 
import 'package:isl_app/views/worker/worker_documents_screen.dart';
import 'package:isl_app/views/worker/worker_alerts_screen.dart';
import 'package:isl_app/views/worker/worker_profile_screen.dart';
import 'package:isl_app/views/worker/worker_chat_history_screen.dart';
import 'package:isl_app/widgets/worker/worker_chat_drawer.dart';
import 'package:isl_app/views/auth/login_screen.dart';
import 'package:isl_app/core/services/api_service.dart';

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

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final TextEditingController _msgCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final ApiService _apiService = ApiService();

  // Which chat session's messages are currently shown. Used to highlight
  // the active chat in the sidebar's "Recent" list.
  String? _currentSessionId;

  // Chat State
  List<Map<String, dynamic>> _messages = [];
  bool _isTyping = false;
  String _firstName = "";

  // AI mascot state machine (pure-Flutter animated avatar, see
  // worker_ai_mascot.dart). Driven by real chat events below: typing in
  // the input field, sending, awaiting a reply, the reply landing, and
  // errors.
  MascotState _mascotState = MascotState.idle;
  Timer? _mascotTypingIdleTimer;

  // Per-user history (point 2 & 4): loaded from /api/chat/history/, which
  // is scoped server-side to the logged-in user's JWT, so it can never
  // contain another user's messages.
  bool _isLoadingHistory = true;
  static const int _sessionHistoryWindow = 50; // keep UI list capped; DB keeps full history

  // Chat limitation (point 3): daily message quota, enforced by backend
  // but reflected here so the input bar can be disabled once hit.
  bool _limitReached = false;
  int _dailyLimit = 30;
  int _remainingMessagesToday = 30; // updated live: history load + every send

  // Quick Help (Documents) State
  List<Map<String, dynamic>> _quickHelpDocs = [];
  bool _isLoadingQuickHelp = true;

  // Cyclic colors for UI elements
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

    if (ApiService.needsFreshChatSession) {
      ApiService.needsFreshChatSession = false;
      // Either the app process just started (cold launch), or the user
      // just signed in (fresh login, possibly after signing out) --
      // either way, start a new chat session instead of resuming the
      // last one. Old messages are NOT lost; they're still visible from
      // the sidebar's "Recent" list.
      try {
        final session = await _apiService.startNewChatSession();
        _currentSessionId = session['session_id']?.toString();
      } catch (e) {
        debugPrint("Could not start a fresh session: $e");
        // Don't leave the flag silently "consumed" if the call actually
        // failed (e.g. network hiccup) -- retry on next screen load.
        ApiService.needsFreshChatSession = true;
      }
    }

    await _loadChatHistory();
  }

  // --- 1b. LOAD THIS USER'S OWN CHAT HISTORY (point 2 & 4) ---
  Future<void> _loadChatHistory() async {
    final String greetingText = _firstName.isNotEmpty
        ? "Hello $_firstName! 👋\nI'm your ISL Assistant. How can I help you today?"
        : "Hello! 👋\nI'm your ISL Assistant. How can I help you today?";

    try {
      List<Map<String, dynamic>> loaded = [];
      final historyData = await _apiService.fetchChatHistory();
      final List rawMessages = historyData['messages'] ?? [];
      for (final m in rawMessages) {
        final createdAt = DateTime.tryParse(m['created_at'] ?? '') ?? DateTime.now();
        loaded.add({
          'isUser': m['sender'] == 'USER',
          'text': m['text'] ?? '',
          'time': DateFormat('hh:mm a').format(createdAt.toLocal()),
        });
      }

      if (mounted) {
        setState(() {
          _messages = loaded.isNotEmpty
              ? loaded
              : [
                  {
                    'isUser': false,
                    'text': greetingText,
                    'time': DateFormat('hh:mm a').format(DateTime.now()),
                  }
                ];
          _isLoadingHistory = false;
          _currentSessionId = historyData['session_id']?.toString() ?? _currentSessionId;
          if (historyData['daily_limit'] is int) {
            _dailyLimit = historyData['daily_limit'];
          }
          if (historyData['remaining_messages_today'] is int) {
            _remainingMessagesToday = historyData['remaining_messages_today'];
            _limitReached = _remainingMessagesToday <= 0;
          }
        });
        _scrollToBottom();
      }
    } catch (e) {
      debugPrint("Error loading chat history: $e");
      if (mounted) {
        setState(() {
          _messages = [
            {
              'isUser': false,
              'text': greetingText,
              'time': DateFormat('hh:mm a').format(DateTime.now()),
            }
          ];
          _isLoadingHistory = false;
        });
      }
    }
  }

  // --- 2. FETCH DEPARTMENT DOCUMENTS (Dynamic Quick Help) ---
  Future<void> _fetchDepartmentDocuments() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token');

      // Adjust according to your backend URL if deployed on a server
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
            // We will pick only the top 5 or 6 documents for Quick Help
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
    if (text.isEmpty || _limitReached) return;

    _msgCtrl.clear();
    _mascotTypingIdleTimer?.cancel();
    final currentTime = DateFormat('hh:mm a').format(DateTime.now());

    setState(() {
      _messages.add({
        'isUser': true,
        'text': text,
        'time': currentTime,
      });
      _isTyping = true;
      _mascotState = MascotState.thinking;
    });
    
    _scrollToBottom();

    // ── "Meri details do" style queries ──────────────────────────────────
    // The AI chat endpoint deliberately has no access to personal employee
    // records (see its "contact admin" replies), so it can never answer
    // this. Instead of hitting the AI at all, answer directly from
    // GET /api/auth/me/ via ApiService.getProfile() -- which the backend
    // already scopes to the signed-in worker's own JWT, so this can only
    // ever return the asking employee's own data, never anyone else's.
    if (_isSelfProfileQuery(text)) {
      await _handleSelfProfileQuery();
      return;
    }

    try {
      final data = await _apiService.askChatWithReferences(text);

      final botReplyText = data['answer'] ?? "I didn't understand that.";
      final String? intent = data['intent'];

      if (mounted) {
        setState(() {
          _isTyping = false;
          _messages.add({
            'isUser': false,
            'text': botReplyText,
            'time': DateFormat('hh:mm a').format(DateTime.now()),
          });
          // Session length cap: keep the visible list bounded; full
          // history always stays safe in the backend regardless.
          if (_messages.length > _sessionHistoryWindow) {
            _messages = _messages.sublist(_messages.length - _sessionHistoryWindow);
          }
          if (intent == 'LIMIT_REACHED') {
            _limitReached = true;
            _remainingMessagesToday = 0;
          } else if (data['remaining_messages_today'] is int) {
            _remainingMessagesToday = data['remaining_messages_today'];
            _limitReached = _remainingMessagesToday <= 0;
          }
        });
        _scrollToBottom();
        _playMascotReplySequence();

        if (intent == 'LEAVE_REQUEST') {
          _showLeaveApplicationForm();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isTyping = false;
          _mascotState = MascotState.error;
          _messages.add({
            'isUser': false,
            'text': "Sorry, I am having trouble connecting to the server. Please try again.",
            'time': DateFormat('hh:mm a').format(DateTime.now()),
          });
        });
        _scrollToBottom();
        // Per spec: hold the error expression briefly, then settle back
        // to idle.
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted && _mascotState == MascotState.error) {
            setState(() => _mascotState = MascotState.idle);
          }
        });
      }
    }
  }

  // ── "Meri details do" detection ──────────────────────────────────────
  // Deliberately broad but literal keyword matching (Roman Urdu + English)
  // rather than anything fuzzy/AI-based -- this only needs to catch
  // "give me my own info" phrasing; it's fine if an odd phrasing slips
  // through to the normal AI flow instead (which will just say it doesn't
  // have personal data, same as before).
  static const List<String> _selfProfileTriggers = [
    'meri detail',
    'meri details',
    'meri maloomat',
    'meri malumat',
    'meri profile',
    'mera profile',
    'mera data',
    'meri info',
    'mera info',
    'mera record',
    'meri record',
    'mera naam bata',
    'meri department',
    'mera department',
    'meri shift',
    'mera shift',
    'meri employee id',
    'mera employee id',
    'apni details',
    'apna profile',
    'apna data',
    'my details',
    'my profile',
    'my info',
    'my data',
    'my employee id',
    'who am i',
    'show my profile',
  ];

  bool _isSelfProfileQuery(String text) {
    final t = text.toLowerCase();
    return _selfProfileTriggers.any((k) => t.contains(k));
  }

  String _formatRole(String rawRole) {
    switch (rawRole.toUpperCase()) {
      case 'DEPARTMENT_HEAD':
        return 'Department Head';
      case 'WORKER':
        return 'Worker';
      default:
        return rawRole.isEmpty ? 'Worker' : rawRole;
    }
  }

  Future<void> _handleSelfProfileQuery() async {
    try {
      // Live call, not the cached SharedPreferences copy the header uses --
      // scoped server-side to the signed-in user's JWT, same guarantee the
      // Profile screen relies on.
      final profile = await _apiService.getProfile();

      final lines = <String>[
        'Here are your details:',
        '• Name: ${profile.fullName.isNotEmpty ? profile.fullName : 'Not set'}',
        '• Employee ID: ${profile.employeeId.isNotEmpty ? profile.employeeId : 'Not set'}',
        '• Department: ${profile.department.isNotEmpty ? profile.department : 'Not assigned'}',
        '• Shift: ${profile.shift.isNotEmpty ? profile.shift : 'Not set'}',
        '• Role: ${_formatRole(profile.role)}',
        '• Email: ${profile.email.isNotEmpty ? profile.email : 'Not set'}',
        if (profile.phone?.isNotEmpty == true) '• Phone: ${profile.phone}',
      ];

      if (mounted) {
        setState(() {
          _isTyping = false;
          _messages.add({
            'isUser': false,
            'text': lines.join('\n'),
            'time': DateFormat('hh:mm a').format(DateTime.now()),
          });
        });
        _scrollToBottom();
        _playMascotReplySequence();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isTyping = false;
          _mascotState = MascotState.error;
          _messages.add({
            'isUser': false,
            'text': 'Your details could not be loaded right now. Please try again.',
            'time': DateFormat('hh:mm a').format(DateTime.now()),
          });
        });
        _scrollToBottom();
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted && _mascotState == MascotState.error) {
            setState(() => _mascotState = MascotState.idle);
          }
        });
      }
    }
  }

  // "Response Ready" (brief bright glow + growing smile, ~400ms) ->
  // "Speaking" (mouth flaps while the reply is on screen) -> back to Idle.
  // There's no typewriter effect in this chat yet, so "speaking" is just
  // held for a moment after the bubble appears rather than synced
  // character-by-character.
  Future<void> _playMascotReplySequence() async {
    if (!mounted) return;
    setState(() => _mascotState = MascotState.happy);
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    setState(() => _mascotState = MascotState.speaking);
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted || _mascotState != MascotState.speaking) return;
    setState(() => _mascotState = MascotState.idle);
  }

  // --- LEAVE APPLICATION FORM (point 1) ---
  void _showLeaveApplicationForm() {
    String selectedType = 'CASUAL';
    final reasonCtrl = TextEditingController();
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20, right: 20, top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Leave Application",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _darkBlue),
                  ),
                  const SizedBox(height: 14),
                  const Text("Leave Type", style: TextStyle(fontSize: 12.5, color: Colors.grey)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: selectedType,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'SICK', child: Text('Sick Leave')),
                      DropdownMenuItem(value: 'CASUAL', child: Text('Casual Leave')),
                      DropdownMenuItem(value: 'ANNUAL', child: Text('Annual Leave')),
                    ],
                    onChanged: (v) => setSheetState(() => selectedType = v ?? selectedType),
                  ),
                  const SizedBox(height: 14),
                  const Text("Reason (optional)", style: TextStyle(fontSize: 12.5, color: Colors.grey)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: reasonCtrl,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: 'Leave blank if you want us to write it...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.all(12),
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _accentBlue,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: isSubmitting
                          ? null
                          : () async {
                              setSheetState(() => isSubmitting = true);
                              await _submitLeaveApplication(
                                leaveType: selectedType,
                                reason: reasonCtrl.text.trim(),
                              );
                              if (ctx.mounted) Navigator.pop(ctx);
                            },
                      child: isSubmitting
                          ? const SizedBox(
                              width: 20, height: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Text("Submit Application", style: TextStyle(color: Colors.white)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _submitLeaveApplication({required String leaveType, required String reason}) async {
    try {
      final data = await _apiService.submitLeaveApplication(
        leaveType: leaveType,
        reason: reason,
      );

      final confirmationText =
          "Your leave application has been sent to your Department Head. ✅\n\n${data['application_text'] ?? ''}";

      if (mounted) {
        setState(() {
          _messages.add({
            'isUser': false,
            'text': confirmationText,
            'time': DateFormat('hh:mm a').format(DateTime.now()),
          });
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages.add({
            'isUser': false,
            'text': "Sorry, the leave application could not be submitted. Please try again.",
            'time': DateFormat('hh:mm a').format(DateTime.now()),
          });
        });
        _scrollToBottom();
      }
    }
  }

  // ── Mascot: reacts to the user typing in the input field ────────────────
  // Fires on every keystroke. Moves the mascot to `userTyping` (eyes on
  // the input, attentive smile) and, if no further keystrokes land within
  // ~1s, eases it back to `idle` -- matching "User Stops Typing" in the
  // animation spec. Ignored while the mascot is busy thinking/speaking.
  void _onMessageFieldChanged(String value) {
    if (_mascotState == MascotState.thinking || _mascotState == MascotState.speaking) {
      return;
    }
    _mascotTypingIdleTimer?.cancel();

    if (value.trim().isEmpty) {
      if (_mascotState != MascotState.idle) {
        setState(() => _mascotState = MascotState.idle);
      }
      return;
    }

    if (_mascotState != MascotState.userTyping) {
      setState(() => _mascotState = MascotState.userTyping);
    }

    _mascotTypingIdleTimer = Timer(const Duration(milliseconds: 1000), () {
      if (mounted && _mascotState == MascotState.userTyping) {
        setState(() => _mascotState = MascotState.idle);
      }
    });
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
    _mascotTypingIdleTimer?.cancel();
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF8FAFC),
      drawer: WorkerChatDrawer(
        onNewChat: _startNewChat,
        onOpenSession: _openRecentSession,
        onLogout: _handleLogout,
        currentSessionId: _currentSessionId,
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            WorkerHeader(onMenuTap: () => _scaffoldKey.currentState?.openDrawer()),
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

    // If no documents are returned from the backend
    if (_quickHelpDocs.isEmpty) {
      return const SizedBox.shrink(); // Hide the UI
    }

    return Container(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 6), // Reduced spacing
          SizedBox(
            height: 64, // 52 wasn't enough to fit the 36px icon + 2-line title below it — that mismatch was the overflow.
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _quickHelpDocs.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final doc = _quickHelpDocs[i];
                final title = doc['title']?.toString() ?? 'Document';
                final color = _docColors[i % _docColors.length]; // Cycles the color

                return _QuickHelpCard(
                  title: title,
                  color: color,
                  onTap: () {
                    // Automatically send a question directly when the user clicks this
                    _sendMessage(predefinedText: "What are the guidelines for $title?");
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 6), // Reduced spacing
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
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(color: _darkBlue, borderRadius: BorderRadius.circular(12)),
            child: AiMascotAvatar(state: _mascotState, size: 34, showAntenna: false),
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
          IconButton(
            icon: Icon(Icons.delete_sweep, color: Colors.grey.shade400, size: 22),
            onPressed: _confirmClearCurrentChat,
            tooltip: 'Clear Current Chat',
          ),
          _ChatLimitIndicator(
            remaining: _remainingMessagesToday,
            total: _dailyLimit,
            onTap: _showLimitDetailsSheet,
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClearCurrentChat() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Current Chat'),
        content: const Text('Are you sure you want to clear the current chat?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true && _currentSessionId != null) {
      try {
        await _apiService.deleteChatSession(_currentSessionId!);
        _startNewChat(); // Reset UI to a fresh chat
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to clear chat.'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  void _showLimitDetailsSheet() {
    final used = _dailyLimit - _remainingMessagesToday;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Today's Message Limit",
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _darkBlue),
              ),
              const SizedBox(height: 10),
              Text(
                "You have sent $used/$_dailyLimit messages today. "
                "${_remainingMessagesToday > 0 ? '$_remainingMessagesToday messages remaining.' : 'Today\'s limit has been reached, please try again tomorrow.'}",
                style: const TextStyle(fontSize: 13, color: Color(0xFF1E293B), height: 1.4),
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: _dailyLimit == 0 ? 0 : used / _dailyLimit,
                  minHeight: 8,
                  backgroundColor: Colors.grey.shade200,
                  color: _limitGaugeColor(_remainingMessagesToday, _dailyLimit),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static Color _limitGaugeColor(int remaining, int total) {
    if (total == 0) return Colors.grey;
    final ratio = remaining / total;
    if (ratio > 0.5) return const Color(0xFF2E7D32); // green
    if (ratio > 0.2) return const Color(0xFFF57C00); // orange
    return const Color(0xFFC62828); // red
  }

  // --- SIDEBAR: "New Chat" button ---
  // Starts a brand new backend session and resets the visible messages to
  // just the greeting. The previous chat isn't deleted -- it stays
  // available from the sidebar's Recent list / Chat History screen.
  Future<void> _startNewChat() async {
    setState(() => _isLoadingHistory = true);
    try {
      final session = await _apiService.startNewChatSession();
      _currentSessionId = session['session_id']?.toString();
      if (session['daily_limit'] is int) _dailyLimit = session['daily_limit'];
      if (session['remaining_messages_today'] is int) {
        _remainingMessagesToday = session['remaining_messages_today'];
        _limitReached = _remainingMessagesToday <= 0;
      }
    } catch (e) {
      debugPrint("Error starting new chat: $e");
    }

    final greetingText = _firstName.isNotEmpty
        ? "Hello $_firstName! 👋\nI'm your ISL Assistant. How can I help you today?"
        : "Hello! 👋\nI'm your ISL Assistant. How can I help you today?";

    if (mounted) {
      setState(() {
        _messages = [
          {
            'isUser': false,
            'text': greetingText,
            'time': DateFormat('hh:mm a').format(DateTime.now()),
          }
        ];
        _isTyping = false;
        _isLoadingHistory = false;
      });
      _scrollToBottom();
    }
  }

  // --- SIDEBAR: tapping a past chat under "Recent" ---
  // Opens that specific session read-only via the Chat History screen,
  // rather than mixing it into the live/active conversation.
  // --- SIDEBAR: "Logout" ---
  // Same pattern as the working logout in WorkerProfileScreen: clear the
  // stored tokens/user data, then replace the entire navigation stack
  // with LoginScreen so there's no way back via the back button.
  //
  // The next successful login re-arms ApiService.needsFreshChatSession
  // (see saveSession()), so whoever logs in next -- same worker or
  // someone else on a shared device -- always starts a brand new chat
  // rather than resuming this one.
  Future<void> _handleLogout() async {
    await _apiService.clearSession();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  void _openRecentSession(String sessionId, String preview) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WorkerChatHistoryScreen(sessionId: sessionId, title: preview),
      ),
    );
  }

  Widget _buildMessagesList() {
    if (_isLoadingHistory) {
      return const Center(
        child: CircularProgressIndicator(color: _accentBlue, strokeWidth: 2),
      );
    }
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
              enabled: !_limitReached,
              onChanged: _onMessageFieldChanged,
              onSubmitted: (_) => _sendMessage(),
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: _limitReached
                    ? 'Today\'s message limit has been reached...'
                    : 'Type your message...',
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
            onTap: (_isTyping || _limitReached) ? null : () => _sendMessage(),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: (_isTyping || _limitReached) ? Colors.grey.shade400 : _accentBlue,
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

class _ChatLimitIndicator extends StatelessWidget {
  const _ChatLimitIndicator({
    required this.remaining,
    required this.total,
    required this.onTap,
  });

  final int remaining;
  final int total;
  final VoidCallback onTap;

  Color get _color {
    if (total <= 0) return Colors.grey;
    final ratio = remaining / total;
    if (ratio > 0.5) return const Color(0xFF2E7D32); // green
    if (ratio > 0.2) return const Color(0xFFF57C00); // orange
    return const Color(0xFFC62828); // red
  }

  @override
  Widget build(BuildContext context) {
    final progress = total <= 0 ? 0.0 : remaining / total;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: _color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _color.withOpacity(0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 3,
                      backgroundColor: _color.withOpacity(0.15),
                      valueColor: AlwaysStoppedAnimation<Color>(_color),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '$remaining/$total',
                style: TextStyle(color: _color, fontSize: 11.5, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
        width: 80, // Slightly increased width to fit the text properly
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
              // Using a generic File icon for all documents
              child: const Icon(Icons.description, color: Colors.white, size: 18),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 2, // Truncates if the name is too long
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
          padding: const EdgeInsets.all(3),
          decoration: const BoxDecoration(color: Color(0xFF0F294D), shape: BoxShape.circle),
          child: const AiMascotAvatar(state: MascotState.thinking, size: 24, showAntenna: false),
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