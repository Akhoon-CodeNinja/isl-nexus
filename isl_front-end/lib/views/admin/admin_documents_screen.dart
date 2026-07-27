import 'package:flutter/material.dart';
import 'package:isl_app/core/models/document_models.dart';
import 'package:isl_app/core/providers/app_state.dart';
import 'package:isl_app/core/services/api_service.dart';
import 'package:isl_app/widgets/admin/admin_sidebar.dart';
import 'package:isl_app/widgets/admin/admin_top_header.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AdminDocumentsScreen extends StatefulWidget {
  const AdminDocumentsScreen({super.key});

  @override
  State<AdminDocumentsScreen> createState() => _AdminDocumentsScreenState();
}

class _AdminDocumentsScreenState extends State<AdminDocumentsScreen> {
  final Color sidebarColor = const Color(0xFF0F294D);
  final Color primaryBlue = const Color(0xFF163E75);
  final Color bgLight = const Color(0xFFF8FAFC);
  final Color borderLight = Colors.grey.shade200;

  final ApiService _apiService = ApiService();

  List<DocumentItem> allDocuments = [];
  List<DocumentItem> documentsList = [];
  // Populated from GET /api/departments/ in _fetchDocuments() — starts with
  // just the "All" option until the real list loads, rather than a
  // hardcoded guess at department names.
  List<String> dynamicDepartments = ["All Departments"];

  bool isAllSelected = false;
  bool _pendingOnly = false; // NEW: Head's "Pending Approval" tab/filter

  // Head's own department id — used ONLY to restrict the "Pending Approval"
  // tab. "All Documents" tab stays unrestricted (all departments).
  // NOTE: adjust `appState.departmentId` below if your AppState exposes
  // the logged-in user's department id under a different name/path
  // (e.g. `appState.currentUser?.departmentId`).
  String? _myDepartmentId;

  String selectedDept = 'All Departments';
  String selectedStatus = 'All Status';
  String selectedFileType = 'All File Types';
  String selectedSort = 'Newest First';
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchDocuments());
  }

  Future<void> _fetchDocuments() async {
    final appState = context.read<AppState>();
    await appState.loadDocuments();

    if (!mounted) return;

    _myDepartmentId = appState.departmentId;

    // The Department filter should only ever show departments that actually
    // exist in the Department table — not whatever strings happen to show
    // up in document records (which could be stale, mistyped, or deleted).
    List<String> deptNames = [];
    try {
      final rawDepartments = await _apiService.fetchDepartmentsRaw();
      deptNames = rawDepartments
          .map((d) => (d['name'] ?? '').toString())
          .where((n) => n.isNotEmpty)
          .toList()
        ..sort();
    } catch (_) {
      // If the departments endpoint fails, fall back to an empty filter
      // list rather than guessing — showing a department that may not
      // exist is worse than showing none.
    }

    if (!mounted) return;

    setState(() {
      allDocuments = appState.documents;
      dynamicDepartments = ["All Departments", ...deptNames];

      if (!dynamicDepartments.contains(selectedDept)) {
        selectedDept = "All Departments";
      }

      _applyFilters();
    });
  }

  void _applyFilters() {
    List<DocumentItem> filtered = List.from(allDocuments);

    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((doc) {
        return doc.title.toLowerCase().contains(_searchQuery) ||
            doc.documentNumber.toLowerCase().contains(_searchQuery) ||
            doc.department.toLowerCase().contains(_searchQuery);
      }).toList();
    }

    if (_pendingOnly) {
      filtered = filtered
          .where((doc) => doc.approvalStatus.toUpperCase() == 'PENDING')
          .toList();

      // Restriction is only for the Pending Approval tab — Head sees
      // every department's documents in "All Documents", but only their
      // own department's pending items here.
      if (_myDepartmentId != null && _myDepartmentId!.isNotEmpty) {
        filtered = filtered
            .where((doc) => doc.departmentIds.contains(_myDepartmentId))
            .toList();
      }
    }

    if (selectedDept != 'All Departments') {
      filtered = filtered
          .where(
            (doc) => doc.department.toUpperCase() == selectedDept.toUpperCase(),
          )
          .toList();
    }

    if (selectedStatus != 'All Status') {
      bool wantActive = selectedStatus == 'Active';
      filtered = filtered.where((doc) => doc.isActive == wantActive).toList();
    }

    if (selectedFileType != 'All File Types') {
      filtered = filtered.where((doc) {
        String docType = doc.type.toUpperCase();
        if (selectedFileType == 'PDF') return docType.contains('PDF');
        if (selectedFileType == 'DOCX') return docType.contains('DOC');
        if (selectedFileType == 'EXCEL') {
          return docType.contains('XLS') || docType.contains('EXCEL');
        }
        return true;
      }).toList();
    }

    if (selectedSort == 'Newest First') {
      filtered.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    } else {
      filtered.sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
    }

    setState(() {
      documentsList = filtered;
      isAllSelected = false;
      for (var doc in documentsList) {
        doc.isSelected = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgLight,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AdminSidebar(activeItem: "Documents"),
          Expanded(
            child: Column(
              children: [
                const AdminTopHeader(
                  title: "Document Management",
                  subtitle:
                      "Manage all AI knowledge documents, SOPs, manuals and policies.",
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, outerConstraints) {
                      final mainDocsCard = Container(
                        margin: EdgeInsets.only(
                          left: 32,
                          bottom: 32,
                          right: outerConstraints.maxWidth < 980 ? 32 : 16,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: borderLight),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.02),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildTabsRow(),
                            _buildToolbar(),
                            const Divider(height: 1),
                            _buildFiltersRow(),
                            const Divider(height: 1),

                            Expanded(
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  double minWidth = 1400;
                                  double tableWidth =
                                      constraints.maxWidth > minWidth
                                      ? constraints.maxWidth
                                      : minWidth;

                                  return SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: SizedBox(
                                      width: tableWidth,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          _buildTableHeader(),
                                          const Divider(height: 1),
                                          Expanded(
                                            child: ListView.separated(
                                              itemCount: documentsList.length,
                                              separatorBuilder:
                                                  (context, index) =>
                                                      const Divider(
                                                        height: 1,
                                                      ),
                                              itemBuilder: (context, index) =>
                                                  _buildTableRow(
                                                    documentsList[index],
                                                  ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                            const Divider(height: 1),
                            _buildPaginationFooter(),
                          ],
                        ),
                      );

                      // Narrow window: stack the docs table above the AI
                      // panel, both full-width, instead of squeezing them
                      // side-by-side (which overflowed the tabs row).
                      if (outerConstraints.maxWidth < 980) {
                        return SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(height: 650, child: mainDocsCard),
                              _buildAIPanel(),
                            ],
                          ),
                        );
                      }

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: mainDocsCard),
                          _buildAIPanel(),
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
    );
  }

  // NEW: "All Documents" / "Pending Approval" tabs — Head's document
  // approval workflow entry point.
  Widget _buildTabsRow() {
    final pendingCount = allDocuments
        .where((d) => d.approvalStatus.toUpperCase() == 'PENDING')
        .where(
          (d) =>
              _myDepartmentId == null ||
              _myDepartmentId!.isEmpty ||
              d.departmentIds.contains(_myDepartmentId),
        )
        .length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        children: [
          _buildTabChip(
            'All Documents',
            selected: !_pendingOnly,
            onTap: () => setState(() {
              _pendingOnly = false;
              _applyFilters();
            }),
          ),
          const SizedBox(width: 10),
          _buildTabChip(
            'Pending Approval ($pendingCount)',
            selected: _pendingOnly,
            highlight: pendingCount > 0,
            onTap: () => setState(() {
              _pendingOnly = true;
              _applyFilters();
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildTabChip(
    String label, {
    required bool selected,
    required VoidCallback onTap,
    bool highlight = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? primaryBlue : Colors.white,
          border: Border.all(
            color: selected
                ? primaryBlue
                : (highlight ? Colors.orange.shade300 : borderLight),
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected
                ? Colors.white
                : (highlight ? Colors.orange.shade800 : Colors.black87),
          ),
        ),
      ),
    );
  }

  // NEW: Approves a pending document via AppState -> ApiService.approveDocument,
  // then refreshes the list so it moves out of "Pending Approval".
  Future<void> _handleApprove(DocumentItem doc) async {
    final appState = context.read<AppState>();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Approving "${doc.title}"...')),
    );

    await appState.approveDocument(doc.id);

    if (!mounted) return;

    if (appState.error == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '"${doc.title}" approved — now active and synced to AI knowledge base.',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to approve: ${appState.error}'),
          backgroundColor: Colors.red,
        ),
      );
    }

    await _fetchDocuments();
  }

  Widget _buildToolbar() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              onChanged: (value) {
                setState(() {
                  _searchQuery = value.trim().toLowerCase();
                  _applyFilters();
                });
              },
              decoration: InputDecoration(
                hintText: "Search documents by title, keyword...",
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
        ],
      ),
    );
  }

  Widget _buildFiltersRow() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildSmallDropdown(
              "Department",
              selectedDept,
              dynamicDepartments,
              onChanged: (v) {
                if (v != null) {
                  setState(() {
                    selectedDept = v;
                    _applyFilters();
                  });
                }
              },
            ),
            const SizedBox(width: 16),
            _buildSmallDropdown(
              "Status",
              selectedStatus,
              ["All Status", "Active", "Inactive"],
              onChanged: (v) {
                if (v != null) {
                  setState(() {
                    selectedStatus = v;
                    _applyFilters();
                  });
                }
              },
            ),
            const SizedBox(width: 16),
            _buildSmallDropdown(
              "File Type",
              selectedFileType,
              ["All File Types", "PDF", "DOCX", "EXCEL"],
              onChanged: (v) {
                if (v != null) {
                  setState(() {
                    selectedFileType = v;
                    _applyFilters();
                  });
                }
              },
            ),
            const SizedBox(width: 32),
            _buildSmallDropdown(
              "Sort By",
              selectedSort,
              ["Newest First", "Oldest First"],
              icon: Icons.sort,
              onChanged: (v) {
                if (v != null) {
                  setState(() {
                    selectedSort = v;
                    _applyFilters();
                  });
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSmallDropdown(
    String label,
    String value,
    List<String> items, {
    IconData? icon,
    required ValueChanged<String?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: Colors.grey,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border.all(color: borderLight),
            borderRadius: BorderRadius.circular(6),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              icon: const Icon(
                Icons.keyboard_arrow_down,
                color: Colors.grey,
                size: 16,
              ),
              items: items
                  .map(
                    (String item) => DropdownMenuItem(
                      value: item,
                      child: Row(
                        children: [
                          if (icon != null) ...[
                            Icon(icon, size: 14, color: Colors.black54),
                            const SizedBox(width: 6),
                          ],
                          Text(
                            item,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black87,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Colors.grey.shade50,
      child: Row(
        children: [
          Expanded(
            flex: 1,
            child: Checkbox(
              value: isAllSelected,
              onChanged: (v) {
                setState(() {
                  isAllSelected = v ?? false;
                  for (var doc in documentsList) doc.isSelected = isAllSelected;
                });
              },
            ),
          ),
          Expanded(flex: 1, child: Text("File", style: _headerStyle())),
          Expanded(
            flex: 5,
            child: Row(
              children: [
                Text("Title", style: _headerStyle()),
                const Icon(Icons.unfold_more, size: 14, color: Colors.grey),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Text("Department", style: _headerStyle()),
                const Icon(Icons.unfold_more, size: 14, color: Colors.grey),
              ],
            ),
          ),
          Expanded(flex: 1, child: Text("Type", style: _headerStyle())),
          Expanded(flex: 1, child: Text("Version", style: _headerStyle())),
          Expanded(flex: 2, child: Text("Status", style: _headerStyle())),
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Text("Updated", style: _headerStyle()),
                const Icon(Icons.unfold_more, size: 14, color: Colors.grey),
              ],
            ),
          ),
          Expanded(flex: 3, child: Text("Uploaded By", style: _headerStyle())),
          Expanded(
            flex: 4,
            child: Text(
              "Actions",
              style: _headerStyle(),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  TextStyle _headerStyle() => const TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.bold,
    color: Colors.black87,
  );

  Widget _buildTableRow(DocumentItem doc) {
    Color iconBgColor;
    Color iconTextColor;
    String displayType = doc.type.trim().toUpperCase();
    String shortType;

    if (displayType == 'PDF') {
      iconBgColor = Colors.red.shade50;
      iconTextColor = Colors.red;
      shortType = 'PDF';
    } else if (displayType.contains('XLS') || displayType.contains('EXCEL')) {
      iconBgColor = Colors.green.shade50;
      iconTextColor = Colors.green;
      shortType = 'XLS';
    } else {
      iconBgColor = Colors.blue.shade50;
      iconTextColor = Colors.blue;
      shortType = displayType.isEmpty ? 'DOC' : displayType;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: doc.isSelected
          ? Colors.blue.shade50.withOpacity(0.3)
          : Colors.white,
      child: Row(
        children: [
          Expanded(
            flex: 1,
            child: Checkbox(
              value: doc.isSelected,
              onChanged: (v) => setState(() {
                doc.isSelected = v ?? false;
                if (!doc.isSelected) isAllSelected = false;
              }),
            ),
          ),
          Expanded(
            flex: 1,
            child: Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: iconBgColor,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                shortType,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: iconTextColor,
                ),
              ),
            ),
          ),
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  doc.title.isNotEmpty ? doc.title : 'Untitled',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    doc.documentNumber.isNotEmpty ? doc.documentNumber : '-',
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  doc.department.isNotEmpty ? doc.department : 'General',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.blue.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              doc.type.isNotEmpty ? doc.type : '-',
              style: const TextStyle(fontSize: 12, color: Colors.black87),
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              doc.version.isNotEmpty ? doc.version : '1.0',
              style: const TextStyle(fontSize: 12, color: Colors.black87),
            ),
          ),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: doc.isActive ? Colors.green : Colors.grey,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      doc.isActive ? "Active" : "Inactive",
                      style: TextStyle(
                        fontSize: 12,
                        color: doc.isActive
                            ? Colors.green.shade700
                            : Colors.grey.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                if (doc.approvalStatus.toUpperCase() == 'PENDING') ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'PENDING',
                      style: TextStyle(
                        fontSize: 9,
                        color: Colors.orange.shade800,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  doc.updatedAt.isNotEmpty ? doc.updatedAt : '-',
                  style: const TextStyle(fontSize: 12, color: Colors.black87),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: doc.uploadedByInitials == 'DK'
                      ? primaryBlue
                      : Colors.teal.shade300,
                  child: Text(
                    doc.uploadedByInitials.isNotEmpty
                        ? doc.uploadedByInitials
                        : 'U',
                    style: const TextStyle(fontSize: 9, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    doc.uploadedByName.isNotEmpty
                        ? doc.uploadedByName
                        : 'Unknown',
                    style: const TextStyle(fontSize: 12, color: Colors.black87),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            flex: 4,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // --- CONDITION: VIEW BUTTON WILL ONLY BE DISPLAYED FOR PDF FILES ---
                if (displayType == 'PDF')
                  GestureDetector(
                    onTap: () async {
                      try {
                        final prefs = await SharedPreferences.getInstance();
                        final token =
                            prefs.getString('access_token') ??
                            prefs.getString('token') ??
                            '';

                        final url = Uri.parse(
                          'http://127.0.0.1:8000/api/documents/${doc.id}/view/?token=$token',
                        );

                        if (await canLaunchUrl(url)) {
                          await launchUrl(
                            url,
                            mode: LaunchMode.externalApplication,
                          );
                        } else {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Could not open file URL.'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Error launching URL.'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
                    child: _buildActionIcon(Icons.remove_red_eye_outlined),
                  ),

                // --- DOWNLOAD BUTTON WILL BE DISPLAYED FOR ALL FILES ---
                GestureDetector(
                  onTap: () async {
                    try {
                      final prefs = await SharedPreferences.getInstance();
                      final token =
                          prefs.getString('access_token') ??
                          prefs.getString('token') ??
                          '';

                      final url = Uri.parse(
                        'http://127.0.0.1:8000/api/documents/${doc.id}/download/?token=$token',
                      );

                      if (await canLaunchUrl(url)) {
                        await launchUrl(
                          url,
                          mode: LaunchMode.externalApplication,
                        );
                      } else {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Could not trigger download.'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Error launching URL.'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
                  child: _buildActionIcon(Icons.download_outlined),
                ),

                // --- APPROVE BUTTON: only shown for documents still
                // awaiting Head approval ---
                if (doc.approvalStatus.toUpperCase() == 'PENDING')
                  GestureDetector(
                    onTap: () => _handleApprove(doc),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check_circle_outline,
                            size: 14,
                            color: Colors.green.shade700,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Approve',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.green.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Switch(
                    value: doc.isActive,
                    activeColor: Colors.green,
                    onChanged: (val) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Status cannot be changed from this read-only view.',
                          ),
                          backgroundColor: Colors.orange,
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionIcon(IconData icon) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        border: Border.all(color: borderLight),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(icon, size: 16, color: Colors.black87),
    );
  }

  Widget _buildPaginationFooter() {
    final total = documentsList.length;
    final showing = total > 10 ? 10 : total;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 16,
        children: [
          Text(
            "Showing 1–$showing of $total documents",
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildPageBox(Icons.chevron_left, isIcon: true),
              _buildPageBox("1", isActive: true),
              const Text(" ... ", style: TextStyle(color: Colors.grey)),
              _buildPageBox(Icons.chevron_right, isIcon: true),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              border: Border.all(color: borderLight),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("10 per page", style: TextStyle(fontSize: 12)),
                SizedBox(width: 8),
                Icon(Icons.keyboard_arrow_down, size: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPageBox(
    dynamic content, {
    bool isActive = false,
    bool isIcon = false,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: isActive ? primaryBlue : Colors.white,
        border: Border.all(color: isActive ? primaryBlue : borderLight),
        borderRadius: BorderRadius.circular(4),
      ),
      alignment: Alignment.center,
      child: isIcon
          ? Icon(content as IconData, size: 16, color: Colors.black87)
          : Text(
              content as String,
              style: TextStyle(
                color: isActive ? Colors.white : Colors.black87,
                fontSize: 12,
              ),
            ),
    );
  }

  Widget _buildAIPanel() {
    final totalDocs = documentsList.length.toString();
    final activeDocs = documentsList.where((d) => d.isActive).length.toString();
    final inactiveDocs =
        documentsList.where((d) => !d.isActive).length.toString();

    return Container(
      width: 280,
      margin: const EdgeInsets.only(right: 32, bottom: 32),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderLight),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.psychology_outlined, color: primaryBlue, size: 28),
              const SizedBox(width: 10),
              const Text(
                "AI Knowledge Base",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text(
            "Sync Status",
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                "Synced",
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.black87,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildStatCard(
            totalDocs,
            "Total Documents",
            Icons.description_outlined,
            Colors.blue,
          ),
          const SizedBox(height: 12),
          _buildStatCard(
            activeDocs,
            "Active Documents",
            Icons.check_circle_outline,
            Colors.green,
          ),
          const SizedBox(height: 12),
          _buildStatCard(
            inactiveDocs,
            "Inactive Documents",
            Icons.pause_circle_outline,
            Colors.orange,
          ),
          const SizedBox(height: 24),
          const Text(
            "Last Sync",
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Row(
            children: [
              Icon(Icons.access_time, size: 14, color: Colors.black54),
              SizedBox(width: 8),
              Text(
                "Just now",
                style: TextStyle(fontSize: 13, color: Colors.black87),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    String count,
    String label,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: borderLight),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                count,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              Text(
                label,
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
        ],
      ),
    );
  }
}