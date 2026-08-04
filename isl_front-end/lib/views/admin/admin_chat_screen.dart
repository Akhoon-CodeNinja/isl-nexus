import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:isl_app/core/providers/app_state.dart';
import 'package:isl_app/core/services/api_service.dart';
import 'package:isl_app/views/auth/login_screen.dart';
import 'package:isl_app/widgets/Admin/admin_chat_drawer.dart';
import 'package:isl_app/widgets/Admin/admin_sidebar.dart';
import 'package:isl_app/widgets/Admin/admin_top_header.dart';
import 'package:isl_app/views/Admin/admin_chat_history_screen.dart';
import 'package:isl_app/widgets/worker/worker_ai_mascot.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ADMIN (DEPARTMENT HEAD) CHAT SCREEN
//
// Head-facing equivalent of worker_chat_screen.dart. Reuses the exact same
// backend endpoints (askChatWithReferences, fetchChatHistory,
// startNewChatSession, submitLeaveApplication, getProfile) since the
// backend's ChatAskView etc. are already role-agnostic (IsAuthenticated
// only) and already give DEPARTMENT_HEAD a higher daily limit (100 vs 30).
//
// INTENTIONALLY SIMPLIFIED vs worker_chat_screen.dart (flag these if you
// want full parity later):
//   - Mascot: reuses AiMascotAvatar (worker_ai_mascot.dart) directly for the
//     bot's chat-bubble avatar (idle) and the typing indicator (thinking).
//     There is no single persistent "live" avatar reacting to userTyping /
//     speaking / happy / error the way the worker screen's input area does
//     -- each bubble/indicator just shows the state that matches its own
//     context. Wire up a shared MascotState if you want the fuller reactive
//     behaviour later.
//   - Recent chats: AdminChatDrawer (adapted from worker_chat_drawer.dart)
//     opens as an endDrawer via the header's "Recent chats" icon button.
//     New chat / search / delete-one / clear-all all work the same as the
//     worker version. Tapping a past session pushes AdminChatHistoryScreen
//     (read-only) instead of loading it into this live screen, same
//     behaviour as worker_shared_drawer.dart's onOpenSession.
//   - No "Quick Help" department-documents chips (worker screen fetches
//     these via a hardcoded http://127.0.0.1:8000 URL, which wouldn't work
//     in production anyway -- worth fixing there too, separately).
// ─────────────────────────────────────────────────────────────────────────────
/// Admin screen — AI Assistant chat interface; answers are grounded in approved ISL documents (RAG).
class AdminChatScreen extends StatefulWidget {
  const AdminChatScreen({super.key});

  @override
  State<AdminChatScreen> createState() => _AdminChatScreenState();
}

class _AdminChatScreenState extends State<AdminChatScreen> {
  static const Color _darkBlue = Color(0xFF0F294D);
  static const Color _accentBlue = Color(0xFF163E75);
  static const Color _bgLight = Color(0xFFF8FAFC);

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final TextEditingController _msgCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final ApiService _apiService = ApiService();

  String? _currentSessionId;
  List<Map<String, dynamic>> _messages = [];
  bool _isLoadingHistory = true;
  bool _isTyping = false;

  bool _limitReached = false;
  int _dailyLimit = 100; // Head's backend default (see get_daily_limit)
  int _remainingMessagesToday = 100;

  static const int _sessionHistoryWindow = 50;

  @override
  void initState() {
    super.initState();
    _initializeChat();
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _initializeChat() async {
    if (ApiService.needsFreshChatSession) {
      ApiService.needsFreshChatSession = false;
      try {
        final session = await _apiService.startNewChatSession();
        _currentSessionId = session['session_id']?.toString();
      } catch (e) {
        debugPrint("Could not start a fresh session: $e");
        ApiService.needsFreshChatSession = true;
      }
    }
    await _loadChatHistory();
  }

  Future<void> _loadChatHistory() async {
    const greetingText =
        "Hello! 👋\nI'm your ISL Assistant. How can I help you today?";

    try {
      final historyData = await _apiService.fetchChatHistory();
      final List rawMessages = historyData['messages'] ?? [];
      final loaded = rawMessages.map((m) {
        final createdAt = DateTime.tryParse(m['created_at'] ?? '') ?? DateTime.now();
        return {
          'isUser': m['sender'] == 'USER',
          'text': m['text'] ?? '',
          'time': DateFormat('hh:mm a').format(createdAt.toLocal()),
        };
      }).toList();

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

  // ── "Meri details do" detection — same trigger list as worker_chat_screen ──
  static const List<String> _selfProfileTriggers = [
    'meri detail', 'meri details', 'meri maloomat', 'meri malumat',
    'meri profile', 'mera profile', 'mera data', 'meri info', 'mera info',
    'mera record', 'meri record', 'mera naam bata', 'meri department',
    'mera department', 'meri shift', 'mera shift', 'meri employee id',
    'mera employee id', 'apni details', 'apna profile', 'apna data',
    'my details', 'my profile', 'my info', 'my data', 'my employee id',
    'who am i', 'show my profile',
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
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isTyping = false;
          _messages.add({
            'isUser': false,
            'text': 'Your details could not be loaded right now. Please try again.',
            'time': DateFormat('hh:mm a').format(DateTime.now()),
          });
        });
        _scrollToBottom();
      }
    }
  }

  Future<void> _sendMessage() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || _limitReached) return;

    _msgCtrl.clear();
    final currentTime = DateFormat('hh:mm a').format(DateTime.now());

    setState(() {
      _messages.add({'isUser': true, 'text': text, 'time': currentTime});
      _isTyping = true;
    });
    _scrollToBottom();

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

        if (intent == 'LEAVE_REQUEST') {
          _showLeaveApplicationForm();
        }
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

  // ── LEAVE APPLICATION FORM — same as worker_chat_screen ──────────────────
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
      final data = await _apiService.submitLeaveApplication(leaveType: leaveType, reason: reason);
      final confirmationText =
          "Your leave application has been sent. ✅\n\n${data['application_text'] ?? ''}";
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

  // ── AdminChatDrawer callbacks ───────────────────────────────────────
  // "New chat" tapped from the drawer while already on this live screen:
  // start a fresh session directly and reset what's shown, instead of
  // navigating away and back (there's nowhere else to navigate to -- this
  // *is* the chat screen).
  Future<void> _startNewChatFromDrawer() async {
    setState(() => _isLoadingHistory = true);
    try {
      final session = await _apiService.startNewChatSession();
      _currentSessionId = session['session_id']?.toString();
    } catch (e) {
      debugPrint("Could not start a fresh session: $e");
    }
    await _loadChatHistory();
  }

  // Tapping a past chat in "Recent": open it read-only, same as
  // worker_shared_drawer.dart's onOpenSession -- the live screen keeps
  // showing the active session, past ones are viewed separately.
  void _openSessionFromDrawer(String sessionId, String preview) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminChatHistoryScreen(sessionId: sessionId, title: preview),
      ),
    );
  }

  // Same logout sequence as AdminSidebar._signOut: sign out via AppState,
  // then replace the whole nav stack with LoginScreen so there's no way
  // back via the system back button.
  Future<void> _logoutFromDrawer() async {
    await context.read<AppState>().logout();
    if (!context.mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: _bgLight,
      endDrawer: AdminChatDrawer(
        currentSessionId: _currentSessionId,
        onNewChat: _startNewChatFromDrawer,
        onOpenSession: _openSessionFromDrawer,
        onLogout: _logoutFromDrawer,
      ),
      body: Row(
        children: [
          const AdminSidebar(activeItem: "AI Assistant"),
          Expanded(
            child: Column(
              children: [
                const AdminTopHeader(
                  title: "AI Assistant",
                  subtitle: "Ask about ISL policies, documents, or apply for leave.",
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton.icon(
                        onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
                        icon: const Icon(Icons.history_rounded, size: 18, color: _accentBlue),
                        label: const Text(
                          "Recent chats",
                          style: TextStyle(fontSize: 12.5, color: _accentBlue, fontWeight: FontWeight.w600),
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                      if (_remainingMessagesToday <= _dailyLimit)
                        Text(
                          "$_remainingMessagesToday / $_dailyLimit messages left today",
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: _isLoadingHistory
                      ? const Center(child: CircularProgressIndicator(color: _accentBlue))
                      : Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: ListView.builder(
                            controller: _scrollCtrl,
                            itemCount: _messages.length + (_isTyping ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index == _messages.length) {
                                return _buildTypingIndicator();
                              }
                              final m = _messages[index];
                              return _ChatBubble(
                                isUser: m['isUser'] as bool,
                                text: m['text'] as String,
                                time: m['time'] as String,
                              );
                            },
                          ),
                        ),
                ),
                _buildInputBar(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          const AiMascotAvatar(state: MascotState.thinking, size: 32),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Text("• • •", style: TextStyle(letterSpacing: 2, color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(32, 12, 32, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _msgCtrl,
              enabled: !_limitReached,
              decoration: InputDecoration(
                hintText: _limitReached
                    ? "Daily message limit reached"
                    : "Type your message...",
                filled: true,
                fillColor: Colors.grey.shade50,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              ),
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 10),
          CircleAvatar(
            radius: 22,
            backgroundColor: _accentBlue,
            child: IconButton(
              icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
              onPressed: (_isTyping || _limitReached) ? null : _sendMessage,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.isUser, required this.text, required this.time});
  final bool isUser;
  final String text;
  final String time;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            const AiMascotAvatar(state: MascotState.idle, size: 32),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.5),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isUser ? const Color(0xFF163E75) : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    text,
                    style: TextStyle(
                      color: isUser ? Colors.white : const Color(0xFF1E293B),
                      fontSize: 13.5,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(time, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}