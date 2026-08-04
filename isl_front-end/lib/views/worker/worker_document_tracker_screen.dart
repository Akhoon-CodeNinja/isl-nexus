import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

import 'package:isl_app/widgets/worker/worker_header.dart';
import 'package:isl_app/widgets/worker/worker_bottom_nav.dart';
import 'package:isl_app/widgets/worker/worker_shared_drawer.dart';
import 'package:isl_app/views/worker/worker_chat_screen.dart';
import 'package:isl_app/views/worker/worker_alerts_screen.dart';
import 'package:isl_app/views/worker/worker_profile_screen.dart';
import 'package:isl_app/views/worker/worker_documents_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// WORKER DOCUMENT TRACKER SCREEN
// Shows the status of documents uploaded by the signed-in worker.
// ─────────────────────────────────────────────────────────────────────────────
/// Worker screen — track the approval status (pending/approved/rejected) of documents they've submitted.
class WorkerDocumentTrackerScreen extends StatefulWidget {
  const WorkerDocumentTrackerScreen({super.key});

  @override
  State<WorkerDocumentTrackerScreen> createState() => _WorkerDocumentTrackerScreenState();
}

class _WorkerDocumentTrackerScreenState extends State<WorkerDocumentTrackerScreen> {
  final String _baseUrl = kIsWeb ? 'http://127.0.0.1:8000/api' : 'http://10.0.2.2:8000/api';
  
  bool _isLoading = true;
  String? _errorMessage;
  List<dynamic> _myUploads = [];
  String _activeFilter = 'ALL';

  @override
  void initState() {
    super.initState();
    _fetchMyUploads();
  }

  Future<void> _fetchMyUploads() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token') ?? '';

      // Calling the new custom backend action
      final response = await http.get(
        Uri.parse('$_baseUrl/documents/my_uploads/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final List<dynamic> data = decoded is List ? decoded : (decoded['results'] ?? []);
        
        if (mounted) {
          setState(() {
            _myUploads = data;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _errorMessage = 'Failed to load tracker data.';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Network error — could not reach the server.';
          _isLoading = false;
        });
      }
    }
  }

  void _handleNav(int index) {
    Widget dest;
    switch (index) {
      case 0: dest = const WorkerChatScreen(); break;
      case 1: dest = const WorkerDocumentsScreen(); break;
      case 2: dest = const WorkerAlertsScreen(); break;
      case 3: dest = const WorkerProfileScreen(); break;
      default: return;
    }
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => dest));
  }

  List<dynamic> get _filteredUploads {
    if (_activeFilter == 'ALL') return _myUploads;
    return _myUploads.where((doc) => (doc['approval_status'] ?? '').toString().toUpperCase() == _activeFilter).toList();
  }

  @override
  Widget build(BuildContext context) {
    final docs = _filteredUploads;

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
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF163E75)))
                  : _errorMessage != null
                      ? _buildErrorState()
                      : RefreshIndicator(
                          onRefresh: _fetchMyUploads,
                          color: const Color(0xFF163E75),
                          child: SingleChildScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
                                  child: Row(
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.arrow_back),
                                        onPressed: () => Navigator.pop(context),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                      ),
                                      const SizedBox(width: 12),
                                      const Text(
                                        'My Upload Tracker',
                                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                                      ),
                                    ],
                                  ),
                                ),
                                _buildFilterTabs(),
                                const SizedBox(height: 16),
                                if (docs.isEmpty)
                                  _buildEmptyState()
                                else
                                  ListView.separated(
                                    physics: const NeverScrollableScrollPhysics(),
                                    shrinkWrap: true,
                                    padding: const EdgeInsets.symmetric(horizontal: 16),
                                    itemCount: docs.length,
                                    separatorBuilder: (_, _) => Divider(height: 1, thickness: 1, color: Colors.grey.shade100),
                                    itemBuilder: (_, i) => _TrackerCard(doc: docs[i]),
                                  ),
                                const SizedBox(height: 24),
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

  Widget _buildFilterTabs() {
    final filters = ['ALL', 'PENDING', 'APPROVED', 'REJECTED'];
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: filters.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final filter = filters[i];
          final isActive = filter == _activeFilter;
          return GestureDetector(
            onTap: () => setState(() => _activeFilter = filter),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isActive ? const Color(0xFF163E75) : Colors.white,
                border: Border.all(
                  color: isActive ? const Color(0xFF163E75) : Colors.grey.shade300,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                filter == 'ALL' ? 'All Uploads' : filter,
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

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 40, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(_errorMessage!, style: TextStyle(color: Colors.grey.shade700)),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: _fetchMyUploads, child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.upload_file_outlined, size: 40, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              _activeFilter == 'ALL' ? "You haven't uploaded any documents yet." : "No documents match this status.",
              style: const TextStyle(color: Colors.grey, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _TrackerCard extends StatelessWidget {
  const _TrackerCard({required this.doc});
  final dynamic doc;

  @override
  Widget build(BuildContext context) {
    final title = doc['title'] ?? 'Untitled';
    final type = (doc['file_type'] ?? 'PDF').toString().toUpperCase();
    final status = (doc['approval_status'] ?? 'PENDING').toString().toUpperCase();
    final date = doc['created_at'] != null ? DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.parse(doc['created_at']).toLocal()) : '';

    Color statusBg, statusText;
    IconData statusIcon;

    if (status == 'APPROVED') {
      statusBg = Colors.green.shade50;
      statusText = Colors.green.shade700;
      statusIcon = Icons.check_circle_outline;
    } else if (status == 'REJECTED') {
      statusBg = Colors.red.shade50;
      statusText = Colors.red.shade700;
      statusIcon = Icons.cancel_outlined;
    } else {
      statusBg = Colors.orange.shade50;
      statusText = Colors.orange.shade800;
      statusIcon = Icons.hourglass_empty;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: type == 'PDF' ? Colors.red.shade50 : Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              type == 'PDF' ? Icons.picture_as_pdf : Icons.description_outlined,
              color: type == 'PDF' ? Colors.red.shade700 : Colors.blue.shade700,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                ),
                const SizedBox(height: 6),
                Text('Uploaded: $date', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(20)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(statusIcon, size: 14, color: statusText),
                const SizedBox(width: 4),
                Text(
                  status,
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: statusText),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}