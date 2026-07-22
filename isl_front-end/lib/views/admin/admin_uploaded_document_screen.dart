import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:isl_app/core/models/document_models.dart';
import 'package:isl_app/core/services/api_service.dart';
import 'package:isl_app/views/admin/admin_upload_document_screen.dart';
import 'package:isl_app/widgets/admin/admin_sidebar.dart';
import 'package:isl_app/widgets/admin/admin_top_header.dart';
import 'package:fl_chart/fl_chart.dart';

// --- DATA MODEL ---
class DashboardDocModel {
  final String id;
  String title; 
  String docNumber; 
  final String type;
  final String department;
  final String version;
  final String updatedAt;
  final String uploadedByName;
  final String uploadedByInitials;
  bool isActive;
  bool isSelected;

  DashboardDocModel({
    required this.id,
    required this.title,
    required this.docNumber,
    required this.type,
    required this.department,
    required this.version,
    required this.updatedAt,
    required this.uploadedByName,
    required this.uploadedByInitials,
    required this.isActive,
    this.isSelected = false,
  });
}

// --- MAIN SCREEN ---
class AdminUploadedDocumentScreen extends StatefulWidget {
  const AdminUploadedDocumentScreen({super.key});

  @override
  State<AdminUploadedDocumentScreen> createState() => _AdminUploadedDocumentScreenState();
}

class _AdminUploadedDocumentScreenState extends State<AdminUploadedDocumentScreen> {
  final Color sidebarColor = const Color(0xFF0F294D);
  final Color primaryBlue = const Color(0xFF163E75);
  final Color bgLight = const Color(0xFFF8FAFC);
  final Color borderLight = Colors.grey.shade200;

  List<DashboardDocModel> allMyDocuments = [];
  List<DashboardDocModel> documentsList = [];

  bool isAllSelected = false;
  bool _isLoading = false;
  String? _errorMessage;

  String _fullName = "Loading...";
  String _employeeId = "";
  String _role = "";
  String _userDepartment = "IT";

  String _searchQuery = '';
  
  // Dynamic Pagination State
  int _itemsPerPage = 10;
  int _currentPage = 1;

  // --- Real-time Stats Variables ---
  int _totalUploads = 0;
  int _activeUploads = 0;
  int _inactiveUploads = 0;
  int _pdfUploads = 0;

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  Future<void> _initializeData() async {
    await _loadUserData();
    await _fetchDocuments();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();

    // Fix: Direct keys se properly data load karein
    final savedDept = prefs.getString('department');
    _userDepartment = (savedDept != null && savedDept.isNotEmpty) ? savedDept : 'IT';
    
    final name = prefs.getString('name');
    final empId = prefs.getString('user_id'); 
    final role = prefs.getString('role');

    if (mounted) {
      setState(() {
        if (name != null && name.isNotEmpty) _fullName = name;
        if (empId != null && empId.isNotEmpty) _employeeId = empId;
        if (role != null && role.isNotEmpty) _role = role;
      });
    }
  }

  bool _isAuthorizedToDelete(String docDepartment) {
    String dDept = docDepartment.toUpperCase().trim();
    String uDept = _userDepartment.toUpperCase().trim();

    if (dDept == 'INFORMATION TECHNOLOGY') dDept = 'IT';
    if (uDept == 'INFORMATION TECHNOLOGY') uDept = 'IT';
    
    if (dDept == 'HUMAN RESOURCES') dDept = 'HR';
    if (uDept == 'HUMAN RESOURCES') uDept = 'HR';

    return dDept == uDept || dDept.contains(uDept) || uDept.contains(dDept);
  }

  int _pdfCount = 0;
  int _xlsCount = 0;
  int _otherCount = 0;

  void _calculateStats() {
    setState(() {
      _totalUploads = allMyDocuments.length;
      // Categories count
      _pdfCount = allMyDocuments.where((doc) => doc.type.toUpperCase().contains('PDF')).length;
      _xlsCount = allMyDocuments.where((doc) => doc.type.toUpperCase().contains('XLS')).length;
      _otherCount = _totalUploads - (_pdfCount + _xlsCount); 

      // NOTE: these three were declared but never assigned before — the
      // Overview panel's "Active Documents", "Inactive Documents", and
      // "PDF Files" rows always showed 0 regardless of real data.
      _activeUploads = allMyDocuments.where((doc) => doc.isActive).length;
      _inactiveUploads = _totalUploads - _activeUploads;
      _pdfUploads = _pdfCount;
    });
}

  Future<void> _fetchDocuments() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final apiService = ApiService();
      final items = await apiService.fetchDocuments();

      if (!mounted) return;

      final myItems = items.where((item) {
        String uName = item.uploadedByName.trim().toLowerCase();
        String myName = _fullName.trim().toLowerCase();

        if (uName.isEmpty || myName.isEmpty) return false;
        
        return uName == myName || uName.contains(myName) || myName.contains(uName);
      }).toList();

      setState(() {
        allMyDocuments = myItems
            .map(
              (item) => DashboardDocModel(
                id: item.id,
                title: item.title,
                docNumber: item.documentNumber,
                type: item.type,
                department: item.department,
                version: item.version,
                updatedAt: item.updatedAt,
                uploadedByName: item.uploadedByName,
                uploadedByInitials: _getInitials(item.uploadedByName),
                isActive: item.isActive,
                isSelected: false,
              ),
            )
            .toList();

        _applyFilters();
        _calculateStats(); // Calculate stats immediately after fetch
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        documentsList = [];
        _errorMessage = e.toString();
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _applyFilters() {
    List<DashboardDocModel> filtered = List.from(allMyDocuments);

    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((doc) {
        return doc.title.toLowerCase().contains(_searchQuery) ||
            doc.docNumber.toLowerCase().contains(_searchQuery) ||
            doc.department.toLowerCase().contains(_searchQuery);
      }).toList();
    }

    filtered.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    setState(() {
      documentsList = filtered;
      isAllSelected = false;
      _currentPage = 1; 
      for (var doc in documentsList) {
        doc.isSelected = false;
      }
    });
  }

  List<DashboardDocModel> get _paginatedDocuments {
    final startIndex = (_currentPage - 1) * _itemsPerPage;
    final endIndex = startIndex + _itemsPerPage;
    if (startIndex >= documentsList.length) return [];
    return documentsList.sublist(
        startIndex, endIndex > documentsList.length ? documentsList.length : endIndex);
  }

  int get _totalPages => (documentsList.length / _itemsPerPage).ceil();

  void _handleBulkAction(String action) {
    final selectedDocs = documentsList.where((d) => d.isSelected).toList();
    if (selectedDocs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one document first.')),
      );
      return;
    }

    if (action == 'delete') {
      bool hasUnauthorizedDocs = selectedDocs.any((d) => !_isAuthorizedToDelete(d.department));

      if (hasUnauthorizedDocs) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Permission Denied: You can only delete files belonging to your department.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    setState(() {
      for (var doc in selectedDocs) {
        if (action == 'activate') doc.isActive = true;
        if (action == 'deactivate') doc.isActive = false;
      }

      if (action == 'delete') {
        documentsList.removeWhere((d) => d.isSelected);
        allMyDocuments.removeWhere((d) => selectedDocs.any((sd) => sd.id == d.id));
      }

      isAllSelected = false;
      for (var doc in documentsList) {
        doc.isSelected = false;
      }
      
      _calculateStats(); // Recalculate stats after bulk action
    });

    String actionName = action == 'activate' ? 'activated' : action == 'deactivate' ? 'deactivated' : 'deleted';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Successfully $actionName ${selectedDocs.length} documents.'),
        backgroundColor: action == 'delete' ? Colors.green : Colors.blue,
      ),
    );
  }

  String _getInitials(String value) {
    if (value.trim().isEmpty) return 'U';
    final parts = value.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return 'U';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'.toUpperCase();
  }

  void _showEditDialog(DashboardDocModel doc) {
    TextEditingController titleCtrl = TextEditingController(text: doc.title);
    TextEditingController docNumCtrl = TextEditingController(text: doc.docNumber);
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Edit Document', style: TextStyle(fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: InputDecoration(
                    labelText: 'Document Title',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: docNumCtrl,
                  decoration: InputDecoration(
                    labelText: 'Document Number',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel', style: TextStyle(color: Colors.black54)),
              ),
              ElevatedButton(
                onPressed: isSubmitting
                    ? null
                    : () async {
                        if (titleCtrl.text.trim().isEmpty || docNumCtrl.text.trim().isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fields cannot be empty')));
                          return;
                        }
                        
                        setDialogState(() => isSubmitting = true);
                        
                        try {
                          await ApiService().updateDocument(doc.id, {
                            'title': titleCtrl.text.trim(),
                            'doc_number': docNumCtrl.text.trim(), 
                          });
                          
                          setState(() {
                            doc.title = titleCtrl.text.trim();
                            doc.docNumber = docNumCtrl.text.trim();
                          });
                          
                          if (mounted) {
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Document updated successfully!'), backgroundColor: Colors.green),
                            );
                          }
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Update failed: ${e.toString().replaceAll("Exception: ", "")}'), backgroundColor: Colors.red),
                          );
                        } finally {
                          if (mounted) setDialogState(() => isSubmitting = false);
                        }
                      },
                style: ElevatedButton.styleFrom(backgroundColor: primaryBlue),
                child: isSubmitting
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Save Changes', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgLight,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AdminSidebar(activeItem: "Uploaded Documents"),
          Expanded(
            child: Column(
              children: [
                AdminTopHeader(
                  title: "Uploaded Documents",
                  subtitle: "View and manage the documents you have uploaded.",
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 32, right: 32, bottom: 32),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // --- Main Data Table (Left Side) ---
                        Expanded(
                          child: Container(
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
                                _buildTableHeader(),
                                const Divider(height: 1),
                                Expanded(
                                  child: _isLoading
                                      ? const Center(child: CircularProgressIndicator())
                                      : _errorMessage != null
                                      ? Center(
                                          child: Padding(
                                            padding: const EdgeInsets.all(24),
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(Icons.error_outline, size: 42, color: Colors.red),
                                                const SizedBox(height: 12),
                                                Text(_errorMessage!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
                                              ],
                                            ),
                                          ),
                                        )
                                      : _paginatedDocuments.isEmpty
                                      ? Center(
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.folder_open, size: 48, color: Colors.grey.shade300),
                                              const SizedBox(height: 16),
                                              const Text("No documents found.", style: TextStyle(color: Colors.grey, fontSize: 16)),
                                            ],
                                          ),
                                        )
                                      : ListView.separated(
                                          itemCount: _paginatedDocuments.length,
                                          separatorBuilder: (context, index) => const Divider(height: 1),
                                          itemBuilder: (context, index) => _buildTableRow(_paginatedDocuments[index]),
                                        ),
                                ),
                                const Divider(height: 1),
                                _buildPaginationFooter(),
                              ],
                            ),
                          ),
                        ),
                        
                        const SizedBox(width: 24), // Gap between table and side panel
                        
                        // --- Real-time Overview Panel (Right Side) ---
                        _buildOverviewPanel(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- New Widget: Right-Hand Side Summary Panel ---
  Widget _buildOverviewPanel() {
    return Container(
      width: 280, // Fixed width like the images provided
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderLight),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Icon Box (Similar to design images)
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.description_outlined, color: primaryBlue, size: 24),
          ),
          const SizedBox(height: 16),
          
          const Text(
            "Uploads Overview",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
          ),
          const SizedBox(height: 24),

          // Real-time API Data Rows
          _buildOverviewRow("Total Uploaded", _totalUploads.toString(), Colors.blue.shade700),
          Divider(color: Colors.grey.shade200, height: 32),
          
          _buildOverviewRow("Active Documents", _activeUploads.toString(), Colors.green.shade700),
          Divider(color: Colors.grey.shade200, height: 32),
          
          _buildOverviewRow("Inactive Documents", _inactiveUploads.toString(), Colors.orange.shade700),
          Divider(color: Colors.grey.shade200, height: 32),
          
          _buildOverviewRow("PDF Files", _pdfUploads.toString(), Colors.red.shade600),

          const SizedBox(height: 24),
          const Text(
            "By File Type",
            style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          _totalUploads == 0
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'No documents yet',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ),
                )
              : SizedBox(
                  height: 180,
                  child: PieChart(
                    PieChartData(
                      sectionsSpace: 2,
                      centerSpaceRadius: 40, // Donut-style hole in the middle
                      sections: [
                        if (_pdfCount > 0)
                          PieChartSectionData(
                            color: Colors.red.shade400,
                            value: _pdfCount.toDouble(),
                            title: 'PDF',
                            radius: 35,
                            titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        if (_xlsCount > 0)
                          PieChartSectionData(
                            color: Colors.green.shade400,
                            value: _xlsCount.toDouble(),
                            title: 'XLS',
                            radius: 35,
                            titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        if (_otherCount > 0)
                          PieChartSectionData(
                            color: Colors.blue.shade400,
                            value: _otherCount.toDouble(),
                            title: 'Other',
                            radius: 35,
                            titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                      ],
                    ),
                  ),
                ),
        ],
      ),

      
    );
    
  }

  // --- Helper for Overview Rows ---
  Widget _buildOverviewRow(String label, String value, Color valueColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 13, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
        ),
        Text(
          value,
          style: TextStyle(fontSize: 16, color: valueColor, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildToolbar() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                // Fix: Removed const
                MaterialPageRoute(builder: (_) => AdminUploadDocumentScreen()),
              ).then((_) => _fetchDocuments()); // Refetch if new upload
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryBlue,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.cloud_upload_outlined, color: Colors.white, size: 18),
            label: const Text("Upload Document", style: TextStyle(color: Colors.white)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: TextField(
              onChanged: (value) {
                setState(() {
                  _searchQuery = value.trim().toLowerCase();
                  _applyFilters();
                });
              },
              decoration: InputDecoration(
                hintText: "Search your documents by title, keyword...",
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
            decoration: BoxDecoration(
              border: Border.all(color: borderLight),
              borderRadius: BorderRadius.circular(8),
            ),
            child: PopupMenuButton<String>(
              offset: const Offset(0, 45),
              onSelected: _handleBulkAction,
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'activate', child: Text('Activate Selected')),
                const PopupMenuItem(value: 'deactivate', child: Text('Deactivate Selected')),
                const PopupMenuDivider(),
                const PopupMenuItem(value: 'delete', child: Text('Delete Selected', style: TextStyle(color: Colors.red))),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: const [
                    Text("Bulk Actions", style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w500)),
                    SizedBox(width: 8),
                    Icon(Icons.keyboard_arrow_down, color: Colors.black87, size: 18),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableHeader() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Container(
        width: 1200,
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
                    for (var doc in _paginatedDocuments) {
                      doc.isSelected = isAllSelected;
                    }
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
            Expanded(flex: 4, child: Text("Actions", style: _headerStyle(), textAlign: TextAlign.center)),
          ],
        ),
      ),
    );
  }

  TextStyle _headerStyle() => const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87);

  Widget _buildTableRow(DashboardDocModel doc) {
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

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Container(
        width: 1200,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: doc.isSelected ? Colors.blue.shade50.withOpacity(0.3) : Colors.white,
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
                decoration: BoxDecoration(color: iconBgColor, borderRadius: BorderRadius.circular(6)),
                child: Text(shortType, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: iconTextColor)),
              ),
            ),
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(doc.title.isNotEmpty ? doc.title : 'Untitled', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87), overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(4)),
                    child: Text(doc.docNumber.isNotEmpty ? doc.docNumber : '-', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(12)),
                  child: Text(doc.department.isNotEmpty ? doc.department : 'General', style: TextStyle(fontSize: 11, color: Colors.blue.shade700, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                ),
              ),
            ),
            Expanded(flex: 1, child: Text(doc.type.isNotEmpty ? doc.type : '-', style: const TextStyle(fontSize: 12, color: Colors.black87))),
            Expanded(flex: 1, child: Text(doc.version.isNotEmpty ? doc.version : '1.0', style: const TextStyle(fontSize: 12, color: Colors.black87))),
            Expanded(
              flex: 2,
              child: Row(
                children: [
                  Container(width: 8, height: 8, decoration: BoxDecoration(color: doc.isActive ? Colors.green : Colors.grey, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text(doc.isActive ? "Active" : "Inactive", style: TextStyle(fontSize: 12, color: doc.isActive ? Colors.green.shade700 : Colors.grey.shade700, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(doc.updatedAt.isNotEmpty ? doc.updatedAt : '-', style: const TextStyle(fontSize: 12, color: Colors.black87), overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: primaryBlue,
                    child: Text(doc.uploadedByInitials, style: const TextStyle(fontSize: 9, color: Colors.white)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(doc.uploadedByName.isNotEmpty ? doc.uploadedByName : 'Unknown', style: const TextStyle(fontSize: 12, color: Colors.black87), overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 4,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildActionIcon(Icons.remove_red_eye_outlined),
                  _buildActionIcon(Icons.download_outlined),
                  
                  GestureDetector(
                    onTap: () => _showEditDialog(doc),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(border: Border.all(color: borderLight), borderRadius: BorderRadius.circular(6)),
                      child: const Icon(Icons.edit_outlined, size: 16, color: Colors.black87),
                    ),
                  ),

                  GestureDetector(
                    onTap: () {
                      if (!_isAuthorizedToDelete(doc.department)) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Permission Denied: You can only delete files belonging to your department.'),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }

                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Delete Document'),
                          content: const Text('Are you sure you want to delete this document permanently?'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                            TextButton(
                              onPressed: () async {
                                Navigator.pop(ctx); 
                                try {
                                  await ApiService().deleteDocument(doc.id);
                                  setState(() {
                                    documentsList.removeWhere((d) => d.id == doc.id);
                                    allMyDocuments.removeWhere((d) => d.id == doc.id);
                                    if (_paginatedDocuments.isEmpty && _currentPage > 1) {
                                      _currentPage--;
                                    }
                                    _calculateStats(); // Recalculate dynamically
                                  });
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Document deleted.'), backgroundColor: Colors.green));
                                  }
                                } catch (e) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete: ${e.toString().replaceAll("Exception: ", "")}'), backgroundColor: Colors.red));
                                  }
                                }
                              },
                              child: const Text('Delete', style: TextStyle(color: Colors.red)),
                            ),
                          ],
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(border: Border.all(color: borderLight), borderRadius: BorderRadius.circular(6)),
                      child: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                    ),
                  ),

                  Switch(
                    value: doc.isActive,
                    activeColor: Colors.green,
                    onChanged: (val) async {
                      final previous = doc.isActive;
                      setState(() { 
                        doc.isActive = val; 
                        _calculateStats(); // Update stats locally instantly
                      }); 
                      try {
                        await ApiService().toggleDocumentStatus(doc.id, val);
                      } catch (e) {
                        setState(() { 
                          doc.isActive = previous; 
                          _calculateStats(); // Revert stats if API fails
                        }); 
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to update status: $e'), backgroundColor: Colors.red));
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionIcon(IconData icon) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(border: Border.all(color: borderLight), borderRadius: BorderRadius.circular(6)),
      child: Icon(icon, size: 16, color: Colors.black87),
    );
  }

  Widget _buildPaginationFooter() {
    final total = documentsList.length;
    if (total == 0) return const SizedBox.shrink();

    final startIndex = (_currentPage - 1) * _itemsPerPage + 1;
    final endIndex = (startIndex + _itemsPerPage - 1) > total ? total : (startIndex + _itemsPerPage - 1);

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text("Showing $startIndex–$endIndex of $total documents", style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          Row(
            children: [
              GestureDetector(
                onTap: _currentPage > 1 ? () => setState(() => _currentPage--) : null,
                child: _buildPageBox(Icons.chevron_left, isIcon: true, disabled: _currentPage == 1),
              ),
              for (int i = 1; i <= _totalPages; i++) 
                GestureDetector(
                  onTap: () => setState(() => _currentPage = i),
                  child: _buildPageBox(i.toString(), isActive: _currentPage == i),
                ),

              GestureDetector(
                onTap: _currentPage < _totalPages ? () => setState(() => _currentPage++) : null,
                child: _buildPageBox(Icons.chevron_right, isIcon: true, disabled: _currentPage == _totalPages),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(border: Border.all(color: borderLight), borderRadius: BorderRadius.circular(6)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _itemsPerPage,
                icon: const Icon(Icons.keyboard_arrow_down, size: 16),
                isDense: true,
                style: const TextStyle(fontSize: 12, color: Colors.black87),
                items: [5, 10, 20, 50].map((int value) {
                  return DropdownMenuItem<int>(value: value, child: Text("$value per page"));
                }).toList(),
                onChanged: (newValue) {
                  if (newValue != null) {
                    setState(() {
                      _itemsPerPage = newValue;
                      _currentPage = 1; 
                    });
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPageBox(dynamic content, {bool isActive = false, bool isIcon = false, bool disabled = false}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      width: 28, height: 28,
      decoration: BoxDecoration(
        color: isActive ? primaryBlue : (disabled ? Colors.grey.shade100 : Colors.white), 
        border: Border.all(color: isActive ? primaryBlue : borderLight), 
        borderRadius: BorderRadius.circular(4)
      ),
      alignment: Alignment.center,
      child: isIcon 
          ? Icon(content as IconData, size: 16, color: disabled ? Colors.grey.shade400 : Colors.black87) 
          : Text(content as String, style: TextStyle(color: isActive ? Colors.white : Colors.black87, fontSize: 12)),
    );
  }
}