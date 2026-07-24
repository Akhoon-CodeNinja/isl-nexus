import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:isl_app/widgets/admin/admin_sidebar.dart';
import 'package:isl_app/widgets/admin/admin_top_header.dart';
import 'package:isl_app/views/admin/admin_documents_screen.dart'; 

class AdminUploadDocumentScreen extends StatefulWidget {
  const AdminUploadDocumentScreen({super.key});

  @override
  State<AdminUploadDocumentScreen> createState() =>
      _AdminUploadDocumentScreenState();
}

class _AdminUploadDocumentScreenState extends State<AdminUploadDocumentScreen> {
  // Brand Colors
  final Color sidebarColor = const Color(0xFF0F294D);
  final Color primaryBlue = const Color(0xFF163E75);
  final Color bgLight = const Color(0xFFF8FAFC);
  final Color borderLight = Colors.grey.shade200;

  // Form Controllers
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _docNumberCtrl =
      TextEditingController(); // Replacing Description with Document Number
  final TextEditingController _versionCtrl = TextEditingController();

  // Backend Data Lists
  List<dynamic> _departmentsList = [];
  List<dynamic> _categoriesList = [];

  // Selected Values (Storing UUIDs for API)
  // Multi-department documents: a document can now be linked to more than
  // one department, so the actual selection lives in this Set. _selectedDeptId
  // is kept alongside it as the "primary" department (the first one picked) —
  // that's what drives the Document Category (Tag) dropdown, since tags are
  // still scoped to a single department on the backend.
  final Set<String> _selectedDeptIds = {};
  String? _selectedDeptId;
  String? _selectedCategoryId;
  String? _selectedFileType; // 'PDF' or 'DOCX'

  bool _isActive = true;
  PlatformFile? _pickedFile;

  bool _isFetchingData = true;
  bool _isFetchingTags = false;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _fetchDropdownData();
  }

  // --- API 1: FETCH DEPARTMENTS ---
  Future<void> _fetchDropdownData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token =
          prefs.getString('access_token') ?? prefs.getString('token') ?? '';
      final headers = {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      };

      final deptRes = await http.get(
        Uri.parse('http://127.0.0.1:8000/api/departments/'),
        headers: headers,
      );

      if (deptRes.statusCode == 200) {
        var deptData = jsonDecode(deptRes.body);
        setState(() {
          _departmentsList = deptData is Map && deptData.containsKey('results')
              ? deptData['results']
              : deptData;
          _isFetchingData = false;
        });
      } else {
        _showSnackBar(
          "Failed to load departments from server.",
          isError: true,
        );
        setState(() => _isFetchingData = false);
      }
    } catch (e) {
      _showSnackBar("Error connecting to server.", isError: true);
      setState(() => _isFetchingData = false);
    }
  }

  // --- API 1b: FETCH TAGS (CATEGORIES) FOR THE SELECTED DEPARTMENT ---
  // Tags are department-scoped on the backend (Tag.unique_together =
  // ('name', 'department')), so the category list has to be re-fetched
  // for whichever department the admin picks here — it can't just load
  // once at page-open using the logged-in admin's own department, which
  // is what caused "No items available" whenever that didn't match the
  // department being uploaded to.
  Future<void> _fetchTagsForDepartment(String departmentId) async {
    setState(() {
      _isFetchingTags = true;
      _categoriesList = [];
      _selectedCategoryId = null; // old selection may not belong to this dept
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      final token =
          prefs.getString('access_token') ?? prefs.getString('token') ?? '';
      final headers = {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      };

      final tagRes = await http.get(
        Uri.parse('http://127.0.0.1:8000/api/tags/?department=$departmentId'),
        headers: headers,
      );

      if (tagRes.statusCode == 200) {
        var tagData = jsonDecode(tagRes.body);
        setState(() {
          _categoriesList = tagData is Map && tagData.containsKey('results')
              ? tagData['results']
              : tagData;
          _isFetchingTags = false;
        });
      } else {
        _showSnackBar("Failed to load categories for this department.", isError: true);
        setState(() => _isFetchingTags = false);
      }
    } catch (e) {
      _showSnackBar("Error loading categories.", isError: true);
      setState(() => _isFetchingTags = false);
    }
  }

  // --- FILE PICKER LOGIC ---
  Future<void> _pickFile() async {
    FilePickerResult? result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'xls', 'xlsx'],
      withData: true, // ensures .bytes is populated on Web
    );

    if (result != null) {
      setState(() {
        _pickedFile = result.files.first;

        // Auto-detect file type for dropdown based on extension
        String ext = _pickedFile!.extension?.toLowerCase() ?? '';
        if (ext == 'pdf') {
          _selectedFileType = 'PDF';
        } else if (ext == 'doc' || ext == 'docx') {
          _selectedFileType = 'DOCX';
        } else if (ext == 'xls' || ext == 'xlsx') {
          _selectedFileType = 'XLSX';
        }
      });
    }
  }

  // --- API 2: UPLOAD DOCUMENT ---
  Future<void> _uploadDocument() async {
    // 1. Validation
    if (_titleCtrl.text.trim().isEmpty)
      return _showSnackBar("Please enter Document Title.", isError: true);
    if (_docNumberCtrl.text.trim().isEmpty)
      return _showSnackBar("Please enter Document Number.", isError: true);
    if (_selectedDeptIds.isEmpty)
      return _showSnackBar("Please select at least one Department.", isError: true);
    if (_selectedFileType == null)
      return _showSnackBar("Please select a File Type.", isError: true);
    if (_pickedFile == null)
      return _showSnackBar("Please attach a file.", isError: true);

    setState(() => _isUploading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final token =
          prefs.getString('access_token') ?? prefs.getString('token') ?? '';

      var request = http.MultipartRequest(
        'POST',
        Uri.parse('http://127.0.0.1:8000/api/documents/'),
      );
      request.headers.addAll({'Authorization': 'Bearer $token'});

      // Map Text Fields — names must match the Django serializer exactly
      request.fields['title'] = _titleCtrl.text.trim();
      request.fields['doc_number'] = _docNumberCtrl.text.trim();
      request.fields['file_type'] = _selectedFileType!;
      request.fields['version'] = _versionCtrl.text.trim().isEmpty
          ? '1.0'
          : _versionCtrl.text.trim();
      request.fields['is_active'] = _isActive ? 'True' : 'False';
      // Comma-separated list of department IDs — the backend
      // (DocumentViewSet.perform_create) splits this and links the
      // document to every department named here, so all of their
      // employees can see it once it's active.
      request.fields['departments'] = _selectedDeptIds.join(',');

      if (_selectedCategoryId != null) {
        request.fields['tag_ids'] = _selectedCategoryId!; // was 'tags'
      }

      // Handle File Attach (Works for Web & Mobile)
      if (_pickedFile!.bytes != null) {
        request.files.add(
          http.MultipartFile.fromBytes(
            'file_url',
            _pickedFile!.bytes!,
            filename: _pickedFile!.name,
          ),
        );
      } else if (_pickedFile!.path != null) {
        request.files.add(
          await http.MultipartFile.fromPath('file_url', _pickedFile!.path!),
        );
      } else {
        // Neither bytes nor path available — surfaces instantly instead
        // of silently sending a file-less request.
        throw Exception(
          'Selected file has no readable data (bytes/path both null).',
        );
      }

      var response = await request.send();

      if (response.statusCode == 201 || response.statusCode == 200) {
        _showSnackBar("Document Uploaded Successfully!", isError: false);
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const AdminDocumentsScreen()),
          );
        }
      } else {
        String resBody = await response.stream.bytesToString();
        debugPrint('UPLOAD FAILED (${response.statusCode}): $resBody');
        _showSnackBar(
          "Upload Failed (${response.statusCode}): $resBody",
          isError: true,
        );
      }
    } catch (e, stack) {
      debugPrint('UPLOAD ERROR: $e');
      debugPrint('$stack');
      _showSnackBar("Upload error: $e", isError: true);
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  // --- ADD NEW CATEGORY (TAG) FOR THE SELECTED DEPARTMENT ---
  // This is what actually unblocks the Category dropdown when a
  // department has zero tags yet — without it, "No categories for this
  // department" was a dead end with no way forward from this screen.
  Future<void> _showAddCategoryDialog() async {
    final nameCtrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text("New Document Category"),
          content: TextField(
            controller: nameCtrl,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: "e.g. Safety Procedures",
              border: OutlineInputBorder(),
            ),
            onSubmitted: (v) => Navigator.pop(dialogContext, v.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, nameCtrl.text.trim()),
              style: ElevatedButton.styleFrom(backgroundColor: primaryBlue),
              child: const Text("Add", style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );

    if (result != null && result.isNotEmpty) {
      await _createTag(result);
    }
  }

  Future<void> _createTag(String name) async {
    if (_selectedDeptId == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final token =
          prefs.getString('access_token') ?? prefs.getString('token') ?? '';
      final headers = {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

      final res = await http.post(
        Uri.parse('http://127.0.0.1:8000/api/tags/'),
        headers: headers,
        body: jsonEncode({'name': name, 'department': _selectedDeptId}),
      );

      if (res.statusCode == 201) {
        final created = jsonDecode(res.body);
        setState(() {
          _categoriesList = [..._categoriesList, created];
          _selectedCategoryId = created['id'].toString();
        });
        _showSnackBar("Category '$name' added.", isError: false);
      } else {
        // Surfaces backend validation errors directly, e.g. a duplicate
        // name for this department (Tag.unique_together).
        _showSnackBar("Could not add category: ${res.body}", isError: true);
      }
    } catch (e) {
      _showSnackBar("Error adding category: $e", isError: true);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _docNumberCtrl.dispose();
    _versionCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgLight,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AdminSidebar(activeItem: "Upload Document"),
          Expanded(
            child: Column(
              children: [
                const AdminTopHeader(
                  title: "Upload Document",
                  subtitle:
                      "Upload and organize documents to sync with ISL AI Assistant.",
                ),
                Expanded(
                  child: _isFetchingData
                      ? const Center(child: CircularProgressIndicator())
                      : SingleChildScrollView(
                          padding: const EdgeInsets.only(
                            left: 32,
                            right: 32,
                            bottom: 32,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(flex: 13, child: _buildFormContainer()),
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

  Widget _buildFormContainer() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(28),
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
              const Text(
                "Document Information",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 24),

              _buildInputLabel("Document Title", isRequired: true),
              _buildTextField(
                controller: _titleCtrl,
                hintText: "Enter document title",
              ),

              const SizedBox(height: 20),

              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildInputLabel("Department(s)", isRequired: true),
                        _buildDepartmentMultiSelect(),
                      ],
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _buildInputLabel("Document Category (Tag)"),
                            InkWell(
                              onTap: _selectedDeptId == null ? null : _showAddCategoryDialog,
                              borderRadius: BorderRadius.circular(4),
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 8.0),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.add_circle_outline,
                                      size: 14,
                                      color: _selectedDeptId == null ? Colors.grey.shade400 : primaryBlue,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      "New Category",
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: _selectedDeptId == null ? Colors.grey.shade400 : primaryBlue,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        _buildDropdownField(
                          hintText: _selectedDeptId == null
                              ? "Select a department first"
                              : _isFetchingTags
                                  ? "Loading categories..."
                                  : _categoriesList.isEmpty
                                      ? "No categories yet — add one above"
                                      : "Select Category",
                          value: _selectedCategoryId,
                          // Dynamic Tags from API, scoped to the selected department
                          items: _categoriesList.map<DropdownMenuItem<String>>((
                            cat,
                          ) {
                            return DropdownMenuItem<String>(
                              value: cat['id'].toString(),
                              child: Text(
                                cat['name'] ?? 'Unknown',
                                style: const TextStyle(fontSize: 13),
                              ),
                            );
                          }).toList(),
                          onChanged: (val) =>
                              setState(() => _selectedCategoryId = val),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildInputLabel("File Type", isRequired: true),
                        _buildDropdownField(
                          hintText: "Select File Type",
                          value: _selectedFileType,
                          // Only strict choices matching the DB models
                          items: const [
                            DropdownMenuItem(
                              value: 'PDF',
                              child: Text(
                                "PDF (.pdf)",
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'DOCX',
                              child: Text(
                                "Word (.docx)",
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'XLSX',
                              child: Text(
                                "Excel (.xlsx)",
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                          onChanged: (val) =>
                              setState(() => _selectedFileType = val),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildInputLabel("Version"),
                        _buildTextField(
                          controller: _versionCtrl,
                          hintText: "e.g. v1.0, v2.1",
                        ),
                        const SizedBox(height: 6),
                        Text(
                          "Leave empty for auto versioning (1.0)",
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // REPLACED Description with Document Number to match Models.py
              _buildInputLabel("Document Number", isRequired: true),
              _buildTextField(
                controller: _docNumberCtrl,
                hintText: "e.g. SOP-001",
              ),

              const SizedBox(height: 24),

              const Text(
                "Status",
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _buildStatusRadio(
                    true,
                    "Active",
                    "Document is available for AI and users",
                  ),
                  const SizedBox(width: 30),
                  _buildStatusRadio(
                    false,
                    "Inactive",
                    "Document will be stored but not active",
                  ),
                ],
              ),

              const SizedBox(height: 32),

              const Text(
                "File Upload",
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 12),
              _buildDragDropArea(),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // Action Buttons Row
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: _isUploading ? null : _uploadDocument,
              icon: _isUploading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(
                      Icons.cloud_upload_outlined,
                      color: Colors.white,
                      size: 18,
                    ),
              label: Text(
                _isUploading ? "Uploading..." : "Upload Document",
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F47B2),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 18,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(width: 16),
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 18,
                ),
                side: BorderSide(color: borderLight),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                "Cancel",
                style: TextStyle(color: Colors.black87, fontSize: 14),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildInputLabel(String label, {bool isRequired = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: RichText(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: Colors.black87,
          ),
          children: isRequired
              ? [
                  const TextSpan(
                    text: ' *',
                    style: TextStyle(color: Colors.red),
                  ),
                ]
              : [],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: primaryBlue, width: 1.5),
        ),
      ),
    );
  }

  // --- MULTI-SELECT DEPARTMENT PICKER ---
  // A document can now be linked to more than one department at once.
  // Tapping a chip toggles it in/out of _selectedDeptIds, which is what
  // actually gets sent to the backend on upload (see _uploadDocument).
  Widget _buildDepartmentMultiSelect() {
    if (_departmentsList.isEmpty) {
      return Container(
        height: 44,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          _isFetchingData ? "Loading departments..." : "No departments available",
          style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: _departmentsList.map<Widget>((dept) {
          final id = dept['id'].toString();
          final name = dept['name'] ?? 'Unknown';
          final isSelected = _selectedDeptIds.contains(id);
          return FilterChip(
            label: Text(name, style: const TextStyle(fontSize: 12)),
            selected: isSelected,
            onSelected: (_) => _toggleDepartment(id),
            selectedColor: primaryBlue.withOpacity(0.15),
            checkmarkColor: primaryBlue,
            labelStyle: TextStyle(
              color: isSelected ? primaryBlue : Colors.black87,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
            side: BorderSide(color: isSelected ? primaryBlue : Colors.grey.shade300),
          );
        }).toList(),
      ),
    );
  }

  void _toggleDepartment(String deptId) {
    setState(() {
      if (_selectedDeptIds.contains(deptId)) {
        _selectedDeptIds.remove(deptId);
      } else {
        _selectedDeptIds.add(deptId);
      }
    });

    // Document Category (Tag) stays scoped to a single "primary"
    // department — the first one picked — since tags themselves are
    // still per-department on the backend. Re-fetch only when that
    // primary department actually changes.
    final newPrimary = _selectedDeptIds.isEmpty ? null : _selectedDeptIds.first;
    if (newPrimary != _selectedDeptId) {
      setState(() {
        _selectedDeptId = newPrimary;
        _selectedCategoryId = null;
      });
      if (newPrimary != null) {
        _fetchTagsForDepartment(newPrimary);
      } else {
        setState(() => _categoriesList = []);
      }
    }
  }

  Widget _buildDropdownField({
    required String hintText,
    required String? value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          hint: Text(
            hintText,
            style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
          ),
          icon: const Icon(Icons.keyboard_arrow_down, color: Colors.grey),
          items: items.isEmpty
              ? [
                  DropdownMenuItem(
                    value: null,
                    child: Text(
                      hintText,
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ]
              : items,
          onChanged: items.isEmpty ? null : onChanged,
        ),
      ),
    );
  }

  Widget _buildStatusRadio(bool value, String title, String subtitle) {
    return InkWell(
      onTap: () => setState(() => _isActive = value),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Radio<bool>(
            value: value,
            groupValue: _isActive,
            activeColor: const Color(0xFF0F47B2),
            onChanged: (val) => setState(() => _isActive = val!),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDragDropArea() {
    return InkWell(
      onTap: _pickFile,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 36),
        decoration: BoxDecoration(
          color: _pickedFile != null
              ? Colors.green.shade50
              : Colors.blue.shade50.withOpacity(0.3),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _pickedFile != null
                ? Colors.green.shade300
                : Colors.blue.shade200,
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: Icon(
                _pickedFile != null
                    ? Icons.check_circle
                    : Icons.cloud_upload_outlined,
                size: 28,
                color: _pickedFile != null
                    ? Colors.green
                    : Colors.blue.shade600,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _pickedFile != null
                  ? "File Ready: ${_pickedFile!.name}"
                  : "Drag and drop your file here",
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _pickedFile != null
                    ? Colors.green.shade700
                    : Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            if (_pickedFile == null) ...[
              const Text(
                "or",
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _pickFile,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F47B2),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                child: const Text(
                  "Choose File",
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
            if (_pickedFile != null) ...[
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: _pickFile,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text("Change File"),
              ),
            ],
            const SizedBox(height: 20),
            Text(
              "Supported formats: PDF, DOCX, XLSX • Max file size: 50MB",
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}