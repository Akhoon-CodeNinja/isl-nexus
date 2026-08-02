import 'package:flutter/material.dart';
import 'package:http/http.dart' as http; // NAYA: HTTP package import kiya gaya
import 'package:isl_app/core/models/document_models.dart';
import 'package:isl_app/core/providers/app_state.dart';
import 'package:isl_app/widgets/Head/department_head_sidebar.dart';
import 'package:isl_app/widgets/Head/department_head_top_header.dart';
import 'package:isl_app/views/Head/department_head_upload_document_screen.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────────────────────
// "MY UPLOADS" SCREEN
//
// BUG FIX: This file used to be a byte-for-byte duplicate of
// DepartmentHeadUploadDocumentScreen (the upload FORM) — same title, same fields,
// even the same hardcoded `DepartmentHeadSidebar(activeItem: "Upload Document")`.
// So tapping "My Uploads" in the sidebar re-rendered the exact same screen
// you were already looking at (visually indistinguishable, sidebar
// highlight didn't even move), which looked like navigation wasn't
// happening at all.
//
// This is now what "My Uploads" should actually be: a read-only list of
// documents *uploaded by the signed-in user themself* — including ones
// still PENDING their own department's approval — with quick View/Download
// actions. Uploading a *new* document still happens on the separate
// "Add Document" screen (DepartmentHeadUploadDocumentScreen).
// ─────────────────────────────────────────────────────────────────────────────
class DepartmentHeadUploadedDocumentScreen extends StatefulWidget {
  const DepartmentHeadUploadedDocumentScreen({super.key});

  @override
  State<DepartmentHeadUploadedDocumentScreen> createState() =>
      _DepartmentHeadUploadedDocumentScreenState();
}

class _DepartmentHeadUploadedDocumentScreenState
    extends State<DepartmentHeadUploadedDocumentScreen> {
  final Color primaryBlue = const Color(0xFF163E75);
  final Color bgLight = const Color(0xFFF8FAFC);
  final Color borderLight = Colors.grey.shade200;

  List<DocumentItem> _myDocuments = [];
  List<DocumentItem> _filtered = [];
  bool _loading = true;
  String? _error;

  String _searchQuery = '';
  String _selectedStatus = 'All Status';
  final List<String> _statusOptions = [
    'All Status',
    'Active',
    'Inactive',
    'Pending Approval',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchMyUploads());
  }

  Future<void> _fetchMyUploads() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final appState = context.read<AppState>();
    await appState.loadDocuments();

    if (!mounted) return;

    // Documents endpoint doesn't filter by "uploaded by me" server-side,
    // so scope it down here using the signed-in user's own id — same id
    // shape as DocumentItem.uploadedById (see DocumentItem.fromJson).
    final myId = appState.profile?.id ?? appState.session?.userId ?? '';

    setState(() {
      _myDocuments =
          appState.documents.where((d) => d.uploadedById == myId).toList();
      _error = appState.error;
      _loading = false;
      _applyFilters();
    });
  }

  void _applyFilters() {
    List<DocumentItem> filtered = List.from(_myDocuments);

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filtered = filtered
          .where((d) =>
              d.title.toLowerCase().contains(q) ||
              d.documentNumber.toLowerCase().contains(q))
          .toList();
    }

    if (_selectedStatus == 'Active') {
      filtered = filtered.where((d) => d.isActive).toList();
    } else if (_selectedStatus == 'Inactive') {
      filtered = filtered
          .where((d) => !d.isActive && d.approvalStatus.toUpperCase() != 'PENDING')
          .toList();
    } else if (_selectedStatus == 'Pending Approval') {
      filtered =
          filtered.where((d) => d.approvalStatus.toUpperCase() == 'PENDING').toList();
    }

    filtered.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    setState(() => _filtered = filtered);
  }

  Future<void> _openFile(String documentId, String action) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token =
          prefs.getString('access_token') ?? prefs.getString('token') ?? '';
      final url = Uri.parse(
        'http://127.0.0.1:8000/api/documents/$documentId/$action/?token=$token',
      );
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the document URL.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error opening file: $e')),
        );
      }
    }
  }

  // NAYA: Delete Document Logic 
  Future<void> _deleteDocument(String documentId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Document'),
        content: const Text('Are you sure you want to delete this document? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false), 
            child: const Text('Cancel')
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token') ?? prefs.getString('token') ?? '';
      
      final url = Uri.parse('http://127.0.0.1:8000/api/documents/$documentId/');
      
      final response = await http.delete(
        url,
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 204) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Document deleted successfully.'), backgroundColor: Colors.green),
          );
          _fetchMyUploads(); // Refresh list after deletion
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to delete document.'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _myDocuments.length;
    final pending = _myDocuments
        .where((d) => d.approvalStatus.toUpperCase() == 'PENDING')
        .length;
    final active = _myDocuments.where((d) => d.isActive).length;

    return Scaffold(
      backgroundColor: bgLight,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const DepartmentHeadSidebar(activeItem: "Uploaded Documents"),
          Expanded(
            child: Column(
              children: [
                const DepartmentHeadTopHeader(
                  title: "My Uploads",
                  subtitle: "Documents you've uploaded yourself, including any still awaiting approval.",
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final mainListCard = Container(
                        margin: EdgeInsets.only(
                          left: 32,
                          bottom: 32,
                          right: constraints.maxWidth < 980 ? 32 : 16,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: borderLight),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4)),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildToolbar(),
                            const Divider(height: 1),
                            Expanded(
                              child: _loading
                                  ? const Center(child: CircularProgressIndicator())
                                  : _error != null
                                      ? _buildErrorState()
                                      : _filtered.isEmpty
                                          ? _buildEmptyState()
                                          : ListView.separated(
                                              itemCount: _filtered.length,
                                              separatorBuilder: (_, _) => const Divider(height: 1),
                                              itemBuilder: (_, i) => _buildRow(_filtered[i]),
                                            ),
                            ),
                          ],
                        ),
                      );

                      // Narrow window: stack the list above the summary
                      // panel, both full-width, instead of squeezing them
                      // side-by-side (which wrapped row text letter-by-letter).
                      if (constraints.maxWidth < 980) {
                        return SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(height: 600, child: mainListCard),
                              _buildSummaryPanel(total, active, pending),
                            ],
                          ),
                        );
                      }

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: mainListCard),
                          _buildSummaryPanel(total, active, pending),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: primaryBlue,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Upload New', style: TextStyle(color: Colors.white)),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const DepartmentHeadUploadDocumentScreen()),
          ).then((_) => _fetchMyUploads());
        },
      ),
    );
  }

  Widget _buildToolbar() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              onChanged: (v) {
                _searchQuery = v.trim();
                _applyFilters();
              },
              decoration: InputDecoration(
                hintText: "Search your uploads by title or document number...",
                hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: borderLight),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border.all(color: borderLight),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedStatus,
                icon: const Icon(Icons.keyboard_arrow_down, size: 16, color: Colors.grey),
                items: _statusOptions
                    .map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontSize: 12))))
                    .toList(),
                onChanged: (v) {
                  if (v != null) {
                    _selectedStatus = v;
                    _applyFilters();
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(DocumentItem doc) {
    final displayType = doc.type.trim().toUpperCase();
    final isPending = doc.approvalStatus.toUpperCase() == 'PENDING';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: displayType == 'PDF' ? Colors.red.shade50 : Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              displayType == 'PDF' ? Icons.picture_as_pdf : Icons.description_outlined,
              color: displayType == 'PDF' ? Colors.red.shade700 : Colors.blue.shade700,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  doc.title.isNotEmpty ? doc.title : 'Untitled',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87),
                ),
                const SizedBox(height: 4),
                Text(
                  '${doc.documentNumber.isNotEmpty ? doc.documentNumber : "-"}  •  ${doc.department}  •  v${doc.version}',
                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (isPending)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(20)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.hourglass_empty, size: 12, color: Colors.orange.shade800),
                  const SizedBox(width: 4),
                  Text('Awaiting Approval', style: TextStyle(fontSize: 11, color: Colors.orange.shade800, fontWeight: FontWeight.w600)),
                ],
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: doc.isActive ? Colors.green.shade50 : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                doc.isActive ? 'Active' : 'Inactive',
                style: TextStyle(
                  fontSize: 11,
                  color: doc.isActive ? Colors.green.shade700 : Colors.grey.shade600,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          const SizedBox(width: 16),
          if (displayType == 'PDF')
            IconButton(
              icon: const Icon(Icons.remove_red_eye_outlined, size: 18),
              onPressed: () => _openFile(doc.id, 'view'),
              tooltip: 'View',
            ),
          IconButton(
            icon: const Icon(Icons.download_outlined, size: 18),
            onPressed: () => _openFile(doc.id, 'download'),
            tooltip: 'Download',
          ),
          // NAYA: Delete Button UI mein add kiya gaya
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
            onPressed: () => _deleteDocument(doc.id),
            tooltip: 'Delete',
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.upload_file_outlined, size: 40, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              _searchQuery.isNotEmpty || _selectedStatus != 'All Status'
                  ? 'No uploads match your search or filter.'
                  : "You haven't uploaded any documents yet.",
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: Colors.red.shade400, size: 32),
            const SizedBox(height: 12),
            Text(_error ?? 'Something went wrong.', style: const TextStyle(color: Colors.black87)),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _fetchMyUploads, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryPanel(int total, int active, int pending) {
    return Container(
      width: 260,
      margin: const EdgeInsets.only(right: 32, bottom: 32),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderLight),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Your Upload Summary", style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          _statCard(total.toString(), "Total Uploads", Icons.description_outlined, Colors.blue),
          const SizedBox(height: 8),
          _statCard(active.toString(), "Active", Icons.check_circle_outline, Colors.green),
          const SizedBox(height: 8),
          _statCard(pending.toString(), "Awaiting Approval", Icons.hourglass_empty, Colors.orange),
        ],
      ),
    );
  }

  Widget _statCard(String count, String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(border: Border.all(color: borderLight), borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(count, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Text(label, style: const TextStyle(fontSize: 10.5, color: Colors.grey)),
            ],
          ),
        ],
      ),
    );
  }
}