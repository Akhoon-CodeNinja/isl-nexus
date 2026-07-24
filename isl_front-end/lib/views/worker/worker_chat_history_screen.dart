import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:isl_app/core/services/api_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// WORKER CHAT HISTORY SCREEN
// Dedicated, read-only view of the signed-in worker's full chat history.
// Backend scopes /api/chat/history/ to request.user, so this can never
// show another user's messages.
// ─────────────────────────────────────────────────────────────────────────────
class WorkerChatHistoryScreen extends StatefulWidget {
  const WorkerChatHistoryScreen({super.key, this.sessionId, this.title});

  // NEW: when opened from the sidebar's "Recent" list, [sessionId] pins
  // this screen to that one past chat instead of the user's latest/active
  // session. Backend still scopes the lookup to request.user, so this can
  // never show another user's session even if an id were guessed.
  final String? sessionId;
  final String? title;

  @override
  State<WorkerChatHistoryScreen> createState() => _WorkerChatHistoryScreenState();
}

class _WorkerChatHistoryScreenState extends State<WorkerChatHistoryScreen> {
  static const Color _darkBlue = Color(0xFF0F294D);
  static const Color _accentBlue = Color(0xFF163E75);

  final ApiService _apiService = ApiService();

  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _messages = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Pull the full history (well beyond the live chat screen's 50-msg
      // window) for this dedicated page.
      final data = await _apiService.fetchChatHistory(limit: 500, sessionId: widget.sessionId);
      final List rawMessages = data['messages'] ?? [];

      if (mounted) {
        setState(() {
          _messages = rawMessages.map((m) => Map<String, dynamic>.from(m as Map)).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load history. Please try again.';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _confirmDelete() async {
    if (widget.sessionId == null) return;
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Chat'),
        content: const Text('Are you sure you want to delete this chat?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isLoading = true);
      try {
        await _apiService.deleteChatSession(widget.sessionId!);
        if (mounted) Navigator.pop(context); // Go back after deleting
      } catch (e) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to delete chat.'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  /// Groups the flat message list into date-labelled sections
  /// (Today / Yesterday / dd MMM yyyy), preserving chronological order.
  List<_HistorySection> _groupByDate(List<Map<String, dynamic>> messages) {
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    final now = DateTime.now();

    for (final m in messages) {
      final createdAt = DateTime.tryParse(m['created_at'] ?? '')?.toLocal() ?? now;
      final label = _dateLabel(createdAt, now);
      grouped.putIfAbsent(label, () => []).add(m);
    }

    return grouped.entries.map((e) => _HistorySection(label: e.key, messages: e.value)).toList();
  }

  String _dateLabel(DateTime date, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final d = DateTime(date.year, date.month, date.day);

    if (d == today) return 'Today';
    if (d == yesterday) return 'Yesterday';
    return DateFormat('dd MMM yyyy').format(date);
  }

  @override
  Widget build(BuildContext context) {
    final sections = _groupByDate(_messages);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        foregroundColor: _darkBlue,
        title: Text(
          widget.title ?? 'Chat History',
          style: const TextStyle(color: _darkBlue, fontWeight: FontWeight.bold, fontSize: 16),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (widget.sessionId != null)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              onPressed: _isLoading ? null : _confirmDelete,
              tooltip: 'Delete Chat',
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _isLoading ? null : _loadHistory,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: SafeArea(
        child: _buildBody(sections),
      ),
    );
  }

  Widget _buildBody(List<_HistorySection> sections) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: _accentBlue, strokeWidth: 2),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_off_rounded, color: Colors.grey.shade400, size: 40),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadHistory,
                style: ElevatedButton.styleFrom(backgroundColor: _accentBlue),
                child: const Text('Try Again', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
    }

    if (sections.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.forum_outlined, color: Colors.grey.shade400, size: 44),
              const SizedBox(height: 12),
              Text(
                'No chat history available yet.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13.5),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: _accentBlue,
      onRefresh: _loadHistory,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 20),
        itemCount: sections.length,
        itemBuilder: (context, index) {
          final section = sections[index];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DateDivider(label: section.label),
              const SizedBox(height: 10),
              ...section.messages.map((m) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _HistoryBubble(
                      isUser: m['sender'] == 'USER',
                      text: (m['text'] ?? '').toString(),
                      time: _formatTime(m['created_at']),
                    ),
                  )),
              const SizedBox(height: 8),
            ],
          );
        },
      ),
    );
  }

  String _formatTime(dynamic createdAt) {
    final dt = DateTime.tryParse((createdAt ?? '').toString())?.toLocal();
    if (dt == null) return '';
    return DateFormat('hh:mm a').format(dt);
  }
}

class _HistorySection {
  _HistorySection({required this.label, required this.messages});
  final String label;
  final List<Map<String, dynamic>> messages;
}

class _DateDivider extends StatelessWidget {
  const _DateDivider({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Divider(color: Colors.grey.shade300, thickness: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            label,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 11.5, fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(child: Divider(color: Colors.grey.shade300, thickness: 1)),
      ],
    );
  }
}

class _HistoryBubble extends StatelessWidget {
  const _HistoryBubble({required this.isUser, required this.text, required this.time});
  final bool isUser;
  final String text;
  final String time;

  @override
  Widget build(BuildContext context) {
    if (isUser) {
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
            child: Text(time, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
          ),
        ],
      );
    }

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
                child: Text(text, style: const TextStyle(fontSize: 13.5, color: Color(0xFF1E293B))),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 2),
                child: Text(time, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
              ),
            ],
          ),
        ),
        const SizedBox(width: 40),
      ],
    );
  }
}