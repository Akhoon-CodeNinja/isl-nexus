import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:isl_app/widgets/worker/worker_header.dart';
import 'package:isl_app/widgets/worker/worker_bottom_nav.dart';
import 'package:isl_app/views/worker/worker_chat_screen.dart';
import 'package:isl_app/views/worker/worker_documents_screen.dart';
import 'package:isl_app/views/worker/worker_profile_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// WORKER ALERTS SCREEN
//
// Fully backed by GET /api/alerts/ — no hardcoded alert data. The
// backend already scopes this to alerts relevant to the signed-in
// worker's own department (AlertViewSet.get_queryset returns alerts
// where target_department == user.department OR target_department is
// null i.e. a company-wide broadcast), so no additional department
// filtering is needed or applied client-side here.
// ─────────────────────────────────────────────────────────────────────────────
class WorkerAlertsScreen extends StatefulWidget {
  const WorkerAlertsScreen({super.key});

  @override
  State<WorkerAlertsScreen> createState() => _WorkerAlertsScreenState();
}

class _WorkerAlertsScreenState extends State<WorkerAlertsScreen> {
  // ── Networking ───────────────────────────────────────────────────────────
  // Same host rule as the rest of the app: 10.0.2.2 only resolves inside
  // the Android emulator, never in Chrome — using kIsWeb here avoids the
  // "silently loads nothing on web" bug found on the Documents screen.
  final String _baseUrl =
      kIsWeb ? 'http://127.0.0.1:8000/api' : 'http://10.0.2.2:8000/api';

  // ── State ─────────────────────────────────────────────────────────────────
  bool _isLoading = true;
  bool _isMarkingAllRead = false;
  String? _errorMessage;
  List<dynamic> _allAlerts = [];
  String _activeFilter = 'ALL'; // 'ALL' | 'EMERGENCY' | 'SAFETY' | 'ANNOUNCEMENT' | 'MAINTENANCE'

  static const List<Map<String, String>> _filterTypes = [
    {'label': 'All', 'value': 'ALL'},
    {'label': 'Emergency', 'value': 'EMERGENCY'},
    {'label': 'Safety', 'value': 'SAFETY'},
    {'label': 'Announcement', 'value': 'ANNOUNCEMENT'},
    {'label': 'Maintenance', 'value': 'MAINTENANCE'},
  ];

  @override
  void initState() {
    super.initState();
    _fetchAlerts();
  }

  // ── API Integration ───────────────────────────────────────────────────────
  Future<String> _readToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('access_token') ?? '';
  }

  Future<void> _fetchAlerts() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final token = await _readToken();
      final response = await http.get(
        Uri.parse('$_baseUrl/alerts/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      debugPrint('WORKER ALERTS — status ${response.statusCode}, body: ${response.body}');

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final List<dynamic> data = decoded is List
            ? decoded
            : (decoded is Map && decoded['results'] is List
                ? decoded['results'] as List<dynamic>
                : <dynamic>[]);
        // Newest first.
        data.sort((a, b) {
          final da = DateTime.tryParse(a['created_at'] ?? '') ?? DateTime(1970);
          final db = DateTime.tryParse(b['created_at'] ?? '') ?? DateTime(1970);
          return db.compareTo(da);
        });
        if (!mounted) return;
        setState(() {
          _allAlerts = data;
          _isLoading = false;
        });
      } else if (response.statusCode == 401) {
        _setError('Your session has expired. Please sign in again.');
      } else {
        _setError('Failed to load alerts (status ${response.statusCode}).');
      }
    } catch (e) {
      debugPrint('WORKER ALERTS — network error: $e');
      _setError('Network error — could not reach the server.');
    }
  }

  void _setError(String msg) {
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _errorMessage = msg;
    });
  }

  Future<void> _markOneRead(String alertId) async {
    final token = await _readToken();
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/alerts/$alertId/mark_read/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      if (response.statusCode == 200 && mounted) {
        setState(() {
          final idx = _allAlerts.indexWhere((a) => a['id'].toString() == alertId);
          if (idx != -1) _allAlerts[idx]['is_read'] = true;
        });
      }
    } catch (e) {
      debugPrint('WORKER ALERTS — mark_read failed for $alertId: $e');
    }
  }

  Future<void> _markAllRead() async {
    final unreadIds = _allAlerts
        .where((a) => a['is_read'] != true)
        .map((a) => a['id'].toString())
        .toList();
    if (unreadIds.isEmpty) return;

    setState(() => _isMarkingAllRead = true);
    try {
      await Future.wait(unreadIds.map(_markOneRead));
    } finally {
      if (mounted) setState(() => _isMarkingAllRead = false);
    }
  }

  // ── Navigation ────────────────────────────────────────────────────────────
  void _handleNav(int index) {
    if (index == 2) return;
    Widget dest;
    switch (index) {
      case 0:  dest = const WorkerChatScreen();      break;
      case 1:  dest = const WorkerDocumentsScreen(); break;
      case 3:  dest = const WorkerProfileScreen();   break;
      default: return;
    }
    Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => dest));
  }

  // ── Derived, filter-aware lists ──────────────────────────────────────────
  List<dynamic> get _filteredAlerts {
    if (_activeFilter == 'ALL') return _allAlerts;
    return _allAlerts.where((a) => a['type'] == _activeFilter).toList();
  }

  List<dynamic> get _urgentAlerts =>
      _filteredAlerts.where((a) => a['type'] == 'EMERGENCY').toList();

  List<dynamic> get _recentAlerts =>
      _filteredAlerts.where((a) => a['type'] != 'EMERGENCY').toList();

  int _countFor(String type) {
    if (type == 'ALL') return _allAlerts.length;
    return _allAlerts.where((a) => a['type'] == type).length;
  }

  @override
  Widget build(BuildContext context) {
    final urgent = _urgentAlerts;
    final recent = _recentAlerts;
    final hasUnread = _allAlerts.any((a) => a['is_read'] != true);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const WorkerHeader(),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: Color(0xFF163E75)))
                  : _errorMessage != null
                      ? _buildErrorState()
                      : RefreshIndicator(
                          onRefresh: _fetchAlerts,
                          color: const Color(0xFF163E75),
                          child: SingleChildScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // ── Title + Mark all as read ──────────────
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text('Alerts',
                                          style: TextStyle(
                                              fontSize: 22,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF1E293B))),
                                      GestureDetector(
                                        onTap: (!hasUnread || _isMarkingAllRead)
                                            ? null
                                            : _markAllRead,
                                        child: Row(
                                          children: [
                                            if (_isMarkingAllRead)
                                              const SizedBox(
                                                width: 12,
                                                height: 12,
                                                child: CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    color: Color(0xFF163E75)),
                                              ),
                                            if (_isMarkingAllRead)
                                              const SizedBox(width: 6),
                                            Text('Mark all as read',
                                                style: TextStyle(
                                                    color: hasUnread
                                                        ? const Color(0xFF163E75)
                                                        : Colors.grey.shade400,
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w600)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 14),

                                // ── Filter chips with REAL count badges ────
                                _buildFilterChips(),
                                const SizedBox(height: 22),

                                // ── Urgent Alerts ───────────────────────
                                if (urgent.isNotEmpty) ...[
                                  const Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 16),
                                    child: Text('Urgent Alerts',
                                        style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF1E293B))),
                                  ),
                                  const SizedBox(height: 10),
                                  ...urgent.map((a) => Padding(
                                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                                        child: _UrgentCard(
                                          alert: a,
                                          onTap: a['is_read'] == true
                                              ? null
                                              : () => _markOneRead(a['id'].toString()),
                                        ),
                                      )),
                                  const SizedBox(height: 10),
                                ],

                                // ── Recent Alerts ───────────────────────
                                if (recent.isNotEmpty) ...[
                                  const Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 16),
                                    child: Text('Recent Alerts',
                                        style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF1E293B))),
                                  ),
                                  const SizedBox(height: 10),
                                  Container(
                                    margin: const EdgeInsets.symmetric(horizontal: 16),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      border: Border.all(color: Colors.grey.shade200),
                                      borderRadius: BorderRadius.circular(12),
                                      boxShadow: [
                                        BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.03),
                                            blurRadius: 6)
                                      ],
                                    ),
                                    child: ListView.separated(
                                      physics: const NeverScrollableScrollPhysics(),
                                      shrinkWrap: true,
                                      padding: EdgeInsets.zero,
                                      itemCount: recent.length,
                                      separatorBuilder: (_, __) => Divider(
                                          height: 1, color: Colors.grey.shade100),
                                      itemBuilder: (_, i) => _RecentAlertRow(
                                        alert: recent[i],
                                        onTap: recent[i]['is_read'] == true
                                            ? null
                                            : () => _markOneRead(recent[i]['id'].toString()),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                ],

                                if (urgent.isEmpty && recent.isEmpty)
                                  _buildEmptyState(),

                                const SizedBox(height: 8),
                              ],
                            ),
                          ),
                        ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: WorkerBottomNav(
        activeIndex: 2,
        onTap: _handleNav,
      ),
    );
  }

  // ── Error state ──────────────────────────────────────────────────────────
  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_outlined, size: 40, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              _errorMessage ?? 'Something went wrong.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: _fetchAlerts,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Retry'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF163E75),
                side: const BorderSide(color: Color(0xFF163E75)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Empty state ───────────────────────────────────────────────────────────
  Widget _buildEmptyState() {
    final filtered = _activeFilter != 'ALL';
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 16, 32, 32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.notifications_off_outlined, size: 36, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              filtered
                  ? 'No alerts in this category.'
                  : 'No alerts for your department right now.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  // ── Filter chips — real, backend-driven counts ──────────────────────────
  Widget _buildFilterChips() {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _filterTypes.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final label = _filterTypes[i]['label']!;
          final value = _filterTypes[i]['value']!;
          final count = _countFor(value);
          final badgeColor = _badgeColorFor(value);
          final isActive = value == _activeFilter;
          return GestureDetector(
            onTap: () => setState(() => _activeFilter = value),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: isActive ? const Color(0xFFEBF2FF) : Colors.white,
                border: Border.all(
                    color: isActive ? const Color(0xFF163E75) : Colors.grey.shade300,
                    width: isActive ? 1.5 : 1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isActive ? const Color(0xFF163E75) : Colors.grey.shade700)),
                  const SizedBox(width: 6),
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(color: badgeColor, shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: Text('$count',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Color _badgeColorFor(String type) {
    switch (type) {
      case 'EMERGENCY':
        return Colors.red;
      case 'SAFETY':
        return const Color(0xFFF9A825);
      case 'ANNOUNCEMENT':
        return const Color(0xFF1565C0);
      case 'MAINTENANCE':
        return const Color(0xFF6A1B9A);
      default:
        return const Color(0xFF1565C0); // 'ALL'
    }
  }

}

// ─────────────────────────────────────────────────────────────────────────────
// Shared time formatting: "Today, 08:15 AM" / "Yesterday, 04:30 PM" /
// "Jul 9, 2026, 11:20 AM" — no intl dependency needed.
// ─────────────────────────────────────────────────────────────────────────────
String _formatAlertTime(dynamic rawIso) {
  final iso = rawIso?.toString();
  if (iso == null || iso.isEmpty) return '';
  final dt = DateTime.tryParse(iso)?.toLocal();
  if (dt == null) return '';

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final alertDay = DateTime(dt.year, dt.month, dt.day);

  final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
  final ampm = dt.hour >= 12 ? 'PM' : 'AM';
  final min = dt.minute.toString().padLeft(2, '0');
  final timeStr = '$h:$min $ampm';

  if (alertDay == today) return 'Today, $timeStr';
  if (alertDay == today.subtract(const Duration(days: 1))) return 'Yesterday, $timeStr';

  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[dt.month - 1]} ${dt.day}, ${dt.year}, $timeStr';
}

Map<String, dynamic> _visualsFor(String? type) {
  switch (type) {
    case 'EMERGENCY':
      return {
        'icon': Icons.crisis_alert,
        'bg': Colors.red.shade100,
        'color': Colors.red.shade700,
      };
    case 'SAFETY':
      return {
        'icon': Icons.warning_rounded,
        'bg': const Color(0xFFFFF8E1),
        'color': const Color(0xFFF9A825),
      };
    case 'MAINTENANCE':
      return {
        'icon': Icons.settings_outlined,
        'bg': const Color(0xFFEDE7F6),
        'color': const Color(0xFF6A1B9A),
      };
    case 'ANNOUNCEMENT':
    default:
      return {
        'icon': Icons.campaign_outlined,
        'bg': const Color(0xFFE3F2FD),
        'color': const Color(0xFF1565C0),
      };
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// URGENT ALERT CARD (red tint, red border) — real data from the backend
// ─────────────────────────────────────────────────────────────────────────────
class _UrgentCard extends StatelessWidget {
  const _UrgentCard({required this.alert, this.onTap});
  final dynamic alert;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final title = (alert['title'] ?? 'Untitled Alert').toString();
    final body = (alert['description'] ?? '').toString();
    final time = _formatAlertTime(alert['created_at']);
    final isRead = alert['is_read'] == true;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          border: Border.all(color: Colors.red.shade200),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.shade100,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: Colors.red.withValues(alpha: 0.25),
                      blurRadius: 10,
                      spreadRadius: 2)
                ],
              ),
              child: Icon(Icons.crisis_alert, color: Colors.red.shade700, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.red.shade700)),
                  const SizedBox(height: 4),
                  Text(body,
                      style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(time, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                const SizedBox(height: 6),
                if (!isRead)
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RECENT ALERT ROW — real data from the backend
// ─────────────────────────────────────────────────────────────────────────────
class _RecentAlertRow extends StatelessWidget {
  const _RecentAlertRow({required this.alert, this.onTap});
  final dynamic alert;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final title = (alert['title'] ?? 'Untitled Alert').toString();
    final body = (alert['description'] ?? '').toString();
    final time = _formatAlertTime(alert['created_at']);
    final isRead = alert['is_read'] == true;
    final visuals = _visualsFor(alert['type']?.toString());

    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(color: visuals['bg'] as Color, shape: BoxShape.circle),
              child: Icon(visuals['icon'] as IconData, color: visuals['color'] as Color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B))),
                  const SizedBox(height: 4),
                  Text(body, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(time, style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500)),
                const SizedBox(height: 6),
                if (!isRead)
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                        color: Color(0xFF163E75), shape: BoxShape.circle),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}