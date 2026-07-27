import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:isl_app/widgets/worker/worker_header.dart';
import 'package:isl_app/widgets/worker/worker_bottom_nav.dart';
import 'package:isl_app/widgets/worker/worker_shared_drawer.dart';
import 'package:isl_app/views/worker/worker_chat_screen.dart';
import 'package:isl_app/views/worker/worker_alerts_screen.dart';
import 'package:isl_app/views/worker/worker_profile_screen.dart';
import 'package:isl_app/core/services/api_service.dart';
import 'package:provider/provider.dart';
import 'package:isl_app/core/providers/app_state.dart';
import 'package:isl_app/views/worker/worker_upload_document_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// WORKER DOCUMENTS SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class WorkerDocumentsScreen extends StatefulWidget {
  const WorkerDocumentsScreen({super.key});

  @override
  State<WorkerDocumentsScreen> createState() => _WorkerDocumentsScreenState();
}

class _WorkerDocumentsScreenState extends State<WorkerDocumentsScreen> {
  // ── State ─────────────────────────────────────────────────────────────────
  bool _isLoading = true;
  bool _isOffline = false; // true only when showing genuinely cached data
  String? _errorMessage;
  DateTime? _cachedAt;
  List<dynamic> _allDocs = [];
  List<String> _filters = ['All'];
  String _activeFilter = 'All';
  String _searchQuery = '';

  final TextEditingController _searchCtrl = TextEditingController();

  static const String _cacheKey = 'cached_worker_documents_v1';
  static const String _cacheTimeKey = 'cached_worker_documents_v1_at';

  // Same host-resolution rule as the rest of the app (see ApiService):
  // 10.0.2.2 only resolves inside the Android emulator, never in Chrome
  // or on a physical device on the same network as your PC. Using the
  // wrong one here was why this screen previously loaded nothing at all
  // when tested on `flutter run -d chrome`.
  final String _baseUrl =
      kIsWeb ? 'http://127.0.0.1:8000/api' : 'http://10.0.2.2:8000/api';

  @override
  void initState() {
    super.initState();
    _fetchDocuments();
    // Make sure we know the signed-in worker's `canManageDocs` / role
    // before build() decides whether to show the Upload button.
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureProfileLoaded());
  }

  Future<void> _ensureProfileLoaded() async {
    final appState = context.read<AppState>();
    if (appState.profile == null) {
      await appState.loadProfile();
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── API Integration ───────────────────────────────────────────────────────
  // Note: no department filter is applied client-side on purpose — the
  // backend's DocumentViewSet.get_queryset() already restricts Workers
  // to `Document.objects.filter(department=user.department, is_active=True)`.
  // Everything this call returns already belongs to the signed-in
  // worker's own department; adding a second filter here would be
  // redundant and risks silently hiding documents if this screen's
  // notion of "my department" ever drifts from the token's.
  Future<void> _fetchDocuments() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token') ?? '';

      final response = await http.get(
        Uri.parse('$_baseUrl/documents/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      debugPrint(
        'WORKER DOCUMENTS — status ${response.statusCode}, body: ${response.body}',
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        // Same DRF pagination shape as the admin side: either a raw
        // list, or {count, next, previous, results: [...]}.
        final List<dynamic> data = decoded is List
            ? decoded
            : (decoded is Map && decoded['results'] is List
                ? decoded['results'] as List<dynamic>
                : <dynamic>[]);

        await prefs.setString(_cacheKey, jsonEncode(data));
        await prefs.setString(_cacheTimeKey, DateTime.now().toIso8601String());

        _applyDocuments(data, offline: false, cachedAt: null);
      } else if (response.statusCode == 401) {
        _showError(
          'Your session has expired. Please sign in again.',
          tryCache: false,
        );
      } else {
        _showError(
          'Failed to load documents (status ${response.statusCode}).',
          tryCache: true,
        );
      }
    } catch (e) {
      debugPrint('WORKER DOCUMENTS — network error: $e');
      _showError('Network error — could not reach the server.', tryCache: true);
    }
  }

  void _applyDocuments(
    List<dynamic> data, {
    required bool offline,
    DateTime? cachedAt,
  }) {
    final Set<String> uniqueTags = {};
    for (var doc in data) {
      if (doc['tags_details'] != null) {
        for (var tag in doc['tags_details']) {
          uniqueTags.add(tag['name'].toString());
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _allDocs = data;
      _filters = ['All', ...uniqueTags.toList()..sort()];
      _isLoading = false;
      _isOffline = offline;
      _cachedAt = cachedAt;
      _errorMessage = null;
    });
  }

  /// On any real failure (network down, server error, timeout), fall
  /// back to the last successfully-cached document list if one exists,
  /// so the offline banner's claim is genuinely true instead of
  /// decorative. If there's no cache either, show a real error state.
  Future<void> _showError(String msg, {required bool tryCache}) async {
    if (tryCache) {
      final prefs = await SharedPreferences.getInstance();
      final rawCache = prefs.getString(_cacheKey);
      final rawCachedAt = prefs.getString(_cacheTimeKey);
      if (rawCache != null) {
        try {
          final data = jsonDecode(rawCache) as List<dynamic>;
          final cachedAt = rawCachedAt != null
              ? DateTime.tryParse(rawCachedAt)
              : null;
          _applyDocuments(data, offline: true, cachedAt: cachedAt);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Showing offline data — could not reach the server.'),
              ),
            );
          }
          return;
        } catch (_) {
          // Corrupt cache — fall through to the real error state below.
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _errorMessage = msg;
    });
  }

  // ── Document Actions (View / Download) ────────────────────────────────────
  Future<void> _handleDocumentAction(String documentId, String action) async {
    try {
      // 1. URL open karne se pehle settings check karein
      final settings = await ApiService().fetchSettings();
      
      // Agar view click kiya aur preview disabled hai
      if (action == 'view' && settings['enable_file_preview'] == false) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Department Head has not allowed document previews.', style: TextStyle(color: Colors.white)),
              backgroundColor: Colors.red,
            ),
          );
        }
        return; // Yahan ruk jayega, browser open nahi hoga
      }

      // Agar download click kiya aur downloads disabled hain
      if (action == 'download' && settings['allow_worker_downloads'] == false) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Department Head has not allowed document downloads.', style: TextStyle(color: Colors.white)),
              backgroundColor: Colors.red,
            ),
          );
        }
        return; // Yahan ruk jayega, browser open nahi hoga
      }

      // 2. Agar allowed hai toh normal URL launch karein
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token') ?? '';
      
      final url = Uri.parse('$_baseUrl/documents/$documentId/$action/?token=$token');
      
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open the document URL.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not verify permissions. Please try again.', style: TextStyle(color: Colors.white)),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ── Navigation ────────────────────────────────────────────────────────────
  void _handleNav(int index) {
    if (index == 1) return; // already here
    Widget dest;
    switch (index) {
      case 0:  dest = const WorkerChatScreen();      break;
      case 2:  dest = const WorkerAlertsScreen();    break;
      case 3:  dest = const WorkerProfileScreen();   break;
      default: return;
    }
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => dest));
  }

  // ── Filter Logic ──────────────────────────────────────────────────────────
  List<dynamic> get _filteredDocs {
    return _allDocs.where((doc) {
      final title = (doc['title'] ?? '').toString().toLowerCase();
      final matchesSearch = title.contains(_searchQuery.toLowerCase());
      
      bool matchesFilter = _activeFilter == 'All';
      if (!matchesFilter && doc['tags_details'] != null) {
        matchesFilter = (doc['tags_details'] as List)
            .any((tag) => tag['name'].toString() == _activeFilter);
      }
      
      return matchesSearch && matchesFilter;
    }).toList();
  }

  List<dynamic> get _recentlyUpdatedDocs {
    // Return top 5 most recently updated documents based on updated_at
    final docs = List<dynamic>.from(_allDocs);
    docs.sort((a, b) {
      final dateA = DateTime.tryParse(a['updated_at'] ?? '') ?? DateTime.now();
      final dateB = DateTime.tryParse(b['updated_at'] ?? '') ?? DateTime.now();
      return dateB.compareTo(dateA);
    });
    return docs.take(5).toList();
  }

  // ── Upload access check ──────────────────────────────────────────────────
  // Worker can upload only if the Head has granted `can_manage_docs`, or if
  // the signed-in user is themself a DEPARTMENT_HEAD (inherent rights).
  bool _canUpload(BuildContext context) {
    final profile = context.watch<AppState>().profile;
    if (profile == null) return false;
    return profile.canManageDocs || profile.role.toUpperCase() == 'DEPARTMENT_HEAD';
  }

  @override
  Widget build(BuildContext context) {
    final currentDocs = _filteredDocs;
    final canUpload = _canUpload(context);

    return Scaffold(
      backgroundColor: Colors.white,
      drawer: buildSharedWorkerDrawer(context),
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
                    onRefresh: _fetchDocuments,
                    color: const Color(0xFF163E75),
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 16),
                          
                          // ── Search Bar ──────────────────────────────────────
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: _buildSearchBar(),
                          ),
                          const SizedBox(height: 14),

                          // ── Filter Chips ────────────────────────────────────
                          if (_filters.length > 1) _buildFilterChips(),
                          if (_filters.length > 1) const SizedBox(height: 22),

                          // ── Recently Accessed (Top 5 Updates) ───────────────
                          if (_searchQuery.isEmpty && _activeFilter == 'All' && _recentlyUpdatedDocs.isNotEmpty) ...[
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: _sectionHeader('Recently Accessed'),
                            ),
                            const SizedBox(height: 12),
                            _buildRecentList(),
                            const SizedBox(height: 24),
                          ],

                          // ── All Documents ────────────────────────────────────
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'All Documents (${currentDocs.length})',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1E293B),
                                  ),
                                ),
                                if (canUpload) _buildUploadButton(),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          
                          if (currentDocs.isEmpty)
                            _buildEmptyState()
                          else
                            _buildAllDocsList(currentDocs),

                          const SizedBox(height: 16),

                          // ── Offline Banner (only shown when genuinely
                          // displaying cached, not live, data) ─────────────
                          if (_isOffline)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                              child: _buildOfflineBanner(),
                            ),
                        ],
                      ),
                    ),
                  ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: WorkerBottomNav(
        activeIndex: 1,
        onTap: _handleNav,
      ),
    );
  }

  // ── Upload button (only rendered when canUpload is true) ───────────────────
  Widget _buildUploadButton() {
    return ElevatedButton.icon(
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const WorkerUploadDocumentScreen(),
          ),
        ).then((_) => _fetchDocuments()); // refresh list after upload
      },
      icon: const Icon(Icons.upload_file, size: 16),
      label: const Text('Upload'),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF163E75),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  // ── Error state (real failure, no cache available) ─────────────────────────
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
              onPressed: _fetchDocuments,
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

  // ── Empty state (successfully loaded, genuinely zero matching docs) ────────
  Widget _buildEmptyState() {
    final hasActiveFilterOrSearch =
        _searchQuery.isNotEmpty || _activeFilter != 'All';
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_off_outlined, size: 36, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              hasActiveFilterOrSearch
                  ? 'No documents match your search or filter.'
                  : 'No documents have been uploaded for your department yet.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  // ── Search Bar ─────────────────────────────────────────────────────────────
  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.search, color: Colors.grey.shade500, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              onChanged: (value) => setState(() => _searchQuery = value),
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search documents by title, keyword...',
                hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                isDense: true,
                filled: false,
              ),
            ),
          ),
          if (_searchQuery.isNotEmpty)
            GestureDetector(
              onTap: () {
                _searchCtrl.clear();
                setState(() => _searchQuery = '');
              },
              child: Icon(Icons.close, color: Colors.grey.shade500, size: 18),
            )
        ],
      ),
    );
  }

  // ── Filter Chips ───────────────────────────────────────────────────────────
  Widget _buildFilterChips() {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _filters.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final label = _filters[i];
          final isActive = label == _activeFilter;
          return GestureDetector(
            onTap: () => setState(() => _activeFilter = label),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              decoration: BoxDecoration(
                color: isActive ? const Color(0xFF334155) : Colors.white,
                border: Border.all(
                    color: isActive ? const Color(0xFF334155) : Colors.grey.shade300),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isActive ? Colors.white : Colors.grey.shade700,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Section header row ─────────────────────────────────────────────────────
  Widget _sectionHeader(String title) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title,
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B))),
      ],
    );
  }

  // ── Recently Accessed horizontal list ──────────────────────────────────────
  Widget _buildRecentList() {
    final recentDocs = _recentlyUpdatedDocs;
    return SizedBox(
      height: 220,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: recentDocs.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (_, i) => _RecentDocCard(
          doc: recentDocs[i],
          onView: () => _handleDocumentAction(recentDocs[i]['id'].toString(), 'view'),
        ),
      ),
    );
  }

 // ── All Documents vertical list ────────────────────────────────────────────
  Widget _buildAllDocsList(List<dynamic> docs) {
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: docs.length,
      separatorBuilder: (_, _) => Divider(height: 1, thickness: 1, color: Colors.grey.shade100),
      itemBuilder: (_, i) => _AllDocRow(
        doc: docs[i],
        onView: () => _handleDocumentAction(docs[i]['id'].toString(), 'view'),
        // Download action yahan se completely hata diya gaya hai
      ),
    );
  }

  // ── Offline banner (only rendered when _isOffline is true) ─────────────────
  Widget _buildOfflineBanner() {
    final timeLabel = _cachedAt != null
        ? '${_cachedAt!.hour.toString().padLeft(2, '0')}:${_cachedAt!.minute.toString().padLeft(2, '0')}'
        : 'earlier';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        border: Border.all(color: Colors.orange.shade200),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_outlined, color: Colors.orange.shade700, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Showing offline data cached at $timeLabel',
                style: TextStyle(
                    fontSize: 13, color: Colors.orange.shade800, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RECENTLY ACCESSED CARD
// ─────────────────────────────────────────────────────────────────────────────
class _RecentDocCard extends StatelessWidget {
  const _RecentDocCard({required this.doc, required this.onView});
  final dynamic doc;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    final title = doc['title'] ?? 'Untitled';
    final type = (doc['file_type'] ?? 'PDF').toString().toUpperCase();
    
    // Get primary tag if exists
    final tags = doc['tags_details'] as List?;
    final primaryTag = (tags != null && tags.isNotEmpty) ? tags.first['name'] : 'General';
    
    // Format date string safely
    String dateStr = '';
    if (doc['updated_at'] != null) {
      final d = DateTime.tryParse(doc['updated_at'].toString());
      if (d != null) dateStr = '${d.day}/${d.month}/${d.year}';
    }

    return Container(
      width: 122,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 12, 10, 0),
            child: Center(child: _FileIconLarge(type: type)),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1E293B), height: 1.3)),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFE3F2FD),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(primaryTag,
                  style: const TextStyle(fontSize: 9, color: Color(0xFF1565C0), fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(dateStr, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
            child: OutlinedButton.icon(
              onPressed: onView,
              icon: Icon(Icons.remove_red_eye_outlined, size: 13, color: Colors.grey.shade700),
              label: Text('View',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: Colors.grey.shade300),
                padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 7),
                minimumSize: const Size(double.infinity, 0),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ALL DOCUMENTS ROW ITEM
// ─────────────────────────────────────────────────────────────────────────────
class _AllDocRow extends StatelessWidget {
  const _AllDocRow({required this.doc, required this.onView}); // onDownload removed
  
  final dynamic doc;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    final title = doc['title'] ?? 'Untitled';
    final type = (doc['file_type'] ?? 'PDF').toString().toUpperCase();
    final version = doc['version'] ?? 'v1.0';
    
    // Get primary tag if exists
    final tags = doc['tags_details'] as List?;
    final primaryTag = (tags != null && tags.isNotEmpty) ? tags.first['name'] : 'General';
    
    String dateStr = '';
    if (doc['updated_at'] != null) {
      final d = DateTime.tryParse(doc['updated_at'].toString());
      if (d != null) dateStr = '${d.day}/${d.month}/${d.year}';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _FileIconSmall(type: type),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(primaryTag,
                      style: const TextStyle(
                          fontSize: 9.5, color: Color(0xFF2E7D32), fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 4),
                Text('Last updated: $dateStr  •  $version',
                    style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Row(
            children: [
              _IconBtn(icon: Icons.remove_red_eye_outlined, onTap: onView),
              // Download ka icon button yahan se completely hata diya gaya hai
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HELPERS
// ─────────────────────────────────────────────────────────────────────────────

class _FileIconLarge extends StatelessWidget {
  const _FileIconLarge({required this.type});
  final String type;

  @override
  Widget build(BuildContext context) {
    final isPdf = type.contains('PDF');
    final iconColor = isPdf ? Colors.red.shade700 : Colors.blue.shade700;
    final bgColor   = isPdf ? Colors.red.shade50  : Colors.blue.shade50;

    return Container(
      width: 64,
      height: 72,
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(8)),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(isPdf ? Icons.picture_as_pdf : Icons.description_outlined, color: iconColor, size: 34),
          const SizedBox(height: 4),
          Text(type.substring(0, type.length > 4 ? 4 : type.length),
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: iconColor)),
        ],
      ),
    );
  }
}

class _FileIconSmall extends StatelessWidget {
  const _FileIconSmall({required this.type});
  final String type;

  @override
  Widget build(BuildContext context) {
    final isPdf = type.contains('PDF');
    final iconColor = isPdf ? Colors.red.shade700 : Colors.blue.shade700;
    final bgColor   = isPdf ? Colors.red.shade50  : Colors.blue.shade50;

    return Container(
      width: 46,
      height: 54,
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(8)),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(isPdf ? Icons.picture_as_pdf : Icons.description_outlined, color: iconColor, size: 22),
          const SizedBox(height: 2),
          Text(type.substring(0, type.length > 4 ? 4 : type.length),
              style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: iconColor)),
        ],
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({required this.icon, required this.onTap});
  final IconData     icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 17, color: Colors.grey.shade600),
      ),
    );
  }
}