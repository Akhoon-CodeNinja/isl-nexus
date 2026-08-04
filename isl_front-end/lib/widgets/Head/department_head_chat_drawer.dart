import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:isl_app/core/services/api_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ADMIN (DEPARTMENT HEAD) CHAT DRAWER
// Direct adaptation of worker_chat_drawer.dart for the Head-facing chat
// screen. Same layout (New chat / Search chats / Recent, no Notebooks /
// Images / Videos / Library) and the same backend endpoint
// (GET /api/chat/sessions/), which is scoped to the signed-in user
// server-side -- so a Head only ever sees their own past chats here, same
// guarantee as the worker version.
//
// _bg intentionally matches DepartmentHeadSidebar's background color (0xFF0F294D)
// so the drawer reads as part of the same admin shell rather than a
// worker-styled overlay.
// ─────────────────────────────────────────────────────────────────────────────
/// Shared widget (Department Head) — slide-out drawer listing AI Assistant chat sessions for quick switching.
class DepartmentHeadChatDrawer extends StatefulWidget {
  const DepartmentHeadChatDrawer({
    super.key,
    required this.onNewChat,
    required this.onOpenSession,
    required this.onLogout,
    this.currentSessionId,
  });

  /// Called when the user taps "New chat". The parent (DepartmentHeadChatScreen)
  /// is responsible for actually starting the new session and resetting
  /// the visible message list.
  final Future<void> Function() onNewChat;

  /// Called when the user taps a past chat in the Recent list.
  /// Args: (sessionId, previewTextForTitle).
  final void Function(String sessionId, String preview) onOpenSession;

  /// Called when the user confirms "Logout" from the drawer.
  final Future<void> Function() onLogout;

  /// The session currently shown in the live chat screen, so it can be
  /// visually highlighted in the Recent list (may be null while loading).
  final String? currentSessionId;

  @override
  State<DepartmentHeadChatDrawer> createState() => _DepartmentHeadChatDrawerState();
}

class _DepartmentHeadChatDrawerState extends State<DepartmentHeadChatDrawer> {
  static const Color _bg = Color(0xFF0F294D);

  final ApiService _apiService = ApiService();
  final TextEditingController _searchCtrl = TextEditingController();

  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _sessions = [];
  String _query = '';

  @override
  void initState() {
    super.initState();
    _loadSessions();
    _searchCtrl.addListener(() {
      setState(() => _query = _searchCtrl.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSessions() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final sessions = await _apiService.fetchChatSessions();
      if (mounted) {
        setState(() {
          _sessions = sessions;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load past chats.';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _confirmDeleteAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear All Chats'),
        content: const Text('Are you sure you want to delete all past chats? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete All', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isLoading = true);
      try {
        await _apiService.deleteAllChatSessions();
        _loadSessions();
      } catch (e) {
        if (mounted) {
          setState(() {
            _error = 'Failed to clear chats.';
            _isLoading = false;
          });
        }
      }
    }
  }

  Future<void> _confirmDeleteSession(String sessionId) async {
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
      try {
        await _apiService.deleteChatSession(sessionId);
        _loadSessions(); // Reload list after deletion
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to delete chat.', style: TextStyle(color: Colors.white)),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  List<Map<String, dynamic>> get _filteredSessions {
    if (_query.isEmpty) return _sessions;
    return _sessions
        .where((s) => (s['preview'] ?? '').toString().toLowerCase().contains(_query))
        .toList();
  }

  String _dateLabel(String? iso) {
    final dt = DateTime.tryParse(iso ?? '')?.toLocal();
    if (dt == null) return '';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(dt.year, dt.month, dt.day);
    if (d == today) return DateFormat('hh:mm a').format(dt);
    if (d == today.subtract(const Duration(days: 1))) return 'Yesterday';
    return DateFormat('dd MMM').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: _bg,
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 6),

            // ── New chat ─────────────────────────────────────────────
            _DrawerActionTile(
              icon: Icons.edit_square,
              label: 'New chat',
              onTap: () async {
                Navigator.of(context).pop(); // close drawer first
                await widget.onNewChat();
              },
            ),

            const SizedBox(height: 6),

            // ── Search chats ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: TextField(
                controller: _searchCtrl,
                style: const TextStyle(color: Colors.white, fontSize: 13.5),
                decoration: InputDecoration(
                  hintText: 'Search chats',
                  hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13.5),
                  prefixIcon: Icon(Icons.search, color: Colors.grey.shade400, size: 20),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.07),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ── Recent header ────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text(
                        'Recent',
                        style: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.keyboard_arrow_down, color: Colors.grey.shade400, size: 16),
                    ],
                  ),
                  if (_sessions.isNotEmpty && !_isLoading)
                    InkWell(
                      onTap: _confirmDeleteAll,
                      child: Text('Clear All', style: TextStyle(color: Colors.red.shade300, fontSize: 11)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Expanded(child: _buildList()),

            // ── Logout (bottom of drawer) ───────────────────────────
            Divider(color: Colors.white.withOpacity(0.08), height: 1),
            _DrawerActionTile(
              icon: Icons.logout_rounded,
              label: 'Logout',
              iconColor: Colors.red.shade300,
              labelColor: Colors.red.shade300,
              onTap: _confirmLogout,
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Logout', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (mounted) Navigator.of(context).pop(); // close the drawer
      await widget.onLogout();
    }
  }

  Widget _buildList() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
      );
    }
    if (_error != null) {
      return Center(
        child: Text(_error!, style: TextStyle(color: Colors.grey.shade400, fontSize: 12.5)),
      );
    }
    final items = _filteredSessions;
    if (items.isEmpty) {
      return Center(
        child: Text(
          _query.isNotEmpty ? 'No chats found.' : 'No past chats available yet.',
          style: TextStyle(color: Colors.grey.shade500, fontSize: 12.5),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final s = items[index];
        final sessionId = (s['session_id'] ?? '').toString();
        final preview = (s['preview'] ?? 'New chat').toString();
        final isActive = sessionId == widget.currentSessionId;

        return Material(
          color: isActive ? Colors.white.withOpacity(0.08) : Colors.transparent,
          child: ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14),
            leading: Icon(Icons.chat_bubble_outline, color: Colors.grey.shade400, size: 18),
            title: Text(
              preview,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _dateLabel(s['last_message_at']?.toString()),
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 10),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () => _confirmDeleteSession(sessionId),
                  child: Icon(Icons.delete_outline, color: Colors.red.shade300, size: 16),
                ),
              ],
            ),
            onTap: () {
              Navigator.of(context).pop();
              widget.onOpenSession(sessionId, preview);
            },
          ),
        );
      },
    );
  }
}

class _DrawerActionTile extends StatelessWidget {
  const _DrawerActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor,
    this.labelColor,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? iconColor;
  final Color? labelColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Icon(icon, color: iconColor ?? Colors.white, size: 20),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  color: labelColor ?? Colors.white,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
