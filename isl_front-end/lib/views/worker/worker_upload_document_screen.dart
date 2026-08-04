import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:isl_app/core/providers/app_state.dart';
import 'package:isl_app/core/services/api_service.dart'; // friendlyApiError() for user-facing error text
import 'package:isl_app/views/worker/worker_documents_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// WORKER UPLOAD DOCUMENT SCREEN
//
// Mobile-friendly counterpart to AdminUploadDocumentScreen. Reuses the same
// backend contract (POST /api/documents/, multipart) but:
//  - Uses a simple AppBar instead of AdminSidebar/AdminTopHeader (which are
//    fixed-width desktop widgets and overflow on a phone).
//  - Locks the Department to the signed-in worker's own department instead
//    of the Head's multi-department picker — a worker uploads into their
//    own department only.
//  - Drops the Active/Inactive status radio: per the approval workflow,
//    every worker upload is created PENDING (is_active = False) on the
//    backend regardless of what's sent, until the Head approves it, so
//    showing that control here would be misleading.
//  - On success, routes back to WorkerDocumentsScreen (not the admin panel).
//
// This screen should only ever be reachable from a "Upload" button that's
// itself gated on `canManageDocs` / DEPARTMENT_HEAD (see
// WorkerDocumentsScreen._canUpload), so no extra role check is done here.
// ─────────────────────────────────────────────────────────────────────────────
/// Worker screen — upload a document file for Department Head approval.
class WorkerUploadDocumentScreen extends StatefulWidget {
  const WorkerUploadDocumentScreen({super.key});

  @override
  State<WorkerUploadDocumentScreen> createState() =>
      _WorkerUploadDocumentScreenState();
}

class _WorkerUploadDocumentScreenState
    extends State<WorkerUploadDocumentScreen> {
  final Color primaryBlue = const Color(0xFF163E75);
  final Color bgLight = const Color(0xFFF8FAFC);
  final Color borderLight = Colors.grey.shade200;

  final String _baseUrl =
      kIsWeb ? 'http://127.0.0.1:8000/api' : 'http://10.0.2.2:8000/api';

  // Form Controllers
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _docNumberCtrl = TextEditingController();
  final TextEditingController _versionCtrl = TextEditingController();

  // Backend Data Lists
  List<dynamic> _departmentsList = [];
  List<dynamic> _categoriesList = [];

  // Worker uploads to a single, locked department — their own.
  String? _myDeptId;
  String? _myDeptName;
  bool _deptAutoDetected = false;

  String? _selectedCategoryId;
  String? _selectedFileType; // 'PDF' / 'DOCX' / 'XLSX'

  PlatformFile? _pickedFile;

  bool _isFetchingData = true;
  bool _isFetchingTags = false;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _fetchDropdownData();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _docNumberCtrl.dispose();
    _versionCtrl.dispose();
    super.dispose();
  }

  // --- FETCH DEPARTMENTS, THEN LOCK TO THE WORKER'S OWN ---
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
        Uri.parse('$_baseUrl/departments/'),
        headers: headers,
      );

      if (deptRes.statusCode == 200) {
        var deptData = jsonDecode(deptRes.body);
        final list = deptData is Map && deptData.containsKey('results')
            ? deptData['results'] as List
            : deptData as List;

        // Match against the signed-in worker's own department name —
        // prefer AppState.profile, fall back to the value saved at login.
        final appState = mounted ? context.read<AppState>() : null;
        final myDeptName = (appState?.profile?.department ??
                prefs.getString('department') ??
                '')
            .trim();

        Map<String, dynamic>? match;
        for (final d in list) {
          final name = (d['name'] ?? '').toString();
          if (name.toLowerCase() == myDeptName.toLowerCase()) {
            match = Map<String, dynamic>.from(d);
            break;
          }
        }

        setState(() {
          _departmentsList = list;
          if (match != null) {
            _myDeptId = match['id'].toString();
            _myDeptName = (match['name'] ?? myDeptName).toString();
            _deptAutoDetected = true;
          } else {
            // Fallback: couldn't match by name — leave unset so the
            // dropdown below prompts the worker to pick manually rather
            // than silently uploading to the wrong department.
            _myDeptName = myDeptName.isEmpty ? null : myDeptName;
            _deptAutoDetected = false;
          }
          _isFetchingData = false;
        });

        if (_myDeptId != null) {
          _fetchTagsForDepartment(_myDeptId!);
        }
      } else {
        _showSnackBar("Failed to load department info.", isError: true);
        setState(() => _isFetchingData = false);
      }
    } catch (e) {
      _showSnackBar("Error connecting to server.", isError: true);
      setState(() => _isFetchingData = false);
    }
  }

  // --- FETCH TAGS (CATEGORIES) FOR THE WORKER'S DEPARTMENT ---
  Future<void> _fetchTagsForDepartment(String departmentId) async {
    setState(() {
      _isFetchingTags = true;
      _categoriesList = [];
      _selectedCategoryId = null;
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
        Uri.parse('$_baseUrl/tags/?department=$departmentId'),
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
        _showSnackBar("Failed to load categories.", isError: true);
        setState(() => _isFetchingTags = false);
      }
    } catch (e) {
      _showSnackBar("Error loading categories.", isError: true);
      setState(() => _isFetchingTags = false);
    }
  }

  // --- MANUAL DEPARTMENT FALLBACK (only used if auto-detect failed) ---
  void _onManualDeptChosen(String? deptId) {
    if (deptId == null) return;
    final dept = _departmentsList.firstWhere(
      (d) => d['id'].toString() == deptId,
      orElse: () => null,
    );
    setState(() {
      _myDeptId = deptId;
      _myDeptName = dept != null ? (dept['name'] ?? '').toString() : null;
    });
    _fetchTagsForDepartment(deptId);
  }

  // --- FILE PICKER ---
  Future<void> _pickFile() async {
    FilePickerResult? result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'xls', 'xlsx'],
      withData: true,
    );

    if (result != null) {
      setState(() {
        _pickedFile = result.files.first;
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

  // --- ADD NEW CATEGORY (TAG) ---
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
              onPressed: () =>
                  Navigator.pop(dialogContext, nameCtrl.text.trim()),
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
    if (_myDeptId == null) return;
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
        Uri.parse('$_baseUrl/tags/'),
        headers: headers,
        body: jsonEncode({'name': name, 'department': _myDeptId}),
      );

      if (res.statusCode == 201) {
        final created = jsonDecode(res.body);
        setState(() {
          _categoriesList = [..._categoriesList, created];
          _selectedCategoryId = created['id'].toString();
        });
        _showSnackBar("Category '$name' added.", isError: false);
      } else {
        _showSnackBar("Could not add category: ${res.body}", isError: true);
      }
    } catch (e) {
      _showSnackBar("Error adding category: ${friendlyApiError(e)}", isError: true);
    }
  }

  // --- UPLOAD DOCUMENT ---
  Future<void> _uploadDocument() async {
    if (_titleCtrl.text.trim().isEmpty) {
      return _showSnackBar("Please enter Document Title.", isError: true);
    }
    if (_docNumberCtrl.text.trim().isEmpty) {
      return _showSnackBar("Please enter Document Number.", isError: true);
    }
    if (_myDeptId == null) {
      return _showSnackBar("Could not determine your department. Please select it below.", isError: true);
    }
    if (_selectedFileType == null) {
      return _showSnackBar("Please select a File Type.", isError: true);
    }
    if (_pickedFile == null) {
      return _showSnackBar("Please attach a file.", isError: true);
    }

    setState(() => _isUploading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final token =
          prefs.getString('access_token') ?? prefs.getString('token') ?? '';

      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$_baseUrl/documents/'),
      );
      request.headers.addAll({'Authorization': 'Bearer $token'});

      request.fields['title'] = _titleCtrl.text.trim();
      request.fields['doc_number'] = _docNumberCtrl.text.trim();
      request.fields['file_type'] = _selectedFileType!;
      request.fields['version'] = _versionCtrl.text.trim().isEmpty
          ? '1.0'
          : _versionCtrl.text.trim();
      // NOTE: Not sending `is_active` at all — the backend forces a
      // Worker's upload to PENDING/is_active=False until the Head
      // approves it, regardless of this value, so it's omitted rather
      // than sending a misleading "Active" that isn't actually honoured.
      request.fields['departments'] = _myDeptId!;

      if (_selectedCategoryId != null) {
        request.fields['tag_ids'] = _selectedCategoryId!;
      }

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
        throw Exception(
          'Selected file has no readable data (bytes/path both null).',
        );
      }

      var response = await request.send();

      if (response.statusCode == 201 || response.statusCode == 200) {
        _showSnackBar(
          "Document submitted! Your Department Head will review it before it goes live.",
          isError: false,
        );
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const WorkerDocumentsScreen()),
          );
        }
      } else {
        String resBody = await response.stream.bytesToString();
        debugPrint('WORKER UPLOAD FAILED (${response.statusCode}): $resBody');
        _showSnackBar(
          "Upload Failed (${response.statusCode}): $resBody",
          isError: true,
        );
      }
    } catch (e, stack) {
      debugPrint('WORKER UPLOAD ERROR: $e');
      debugPrint('$stack');
      _showSnackBar("Upload error: ${friendlyApiError(e)}", isError: true);
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ── UI ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgLight,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        foregroundColor: const Color(0xFF1E293B),
        title: const Text(
          'Upload Document',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: _isFetchingData
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF163E75)))
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, size: 16, color: Colors.blue.shade700),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              "Your upload will be submitted for your Department Head's approval before it becomes visible to others.",
                              style: TextStyle(fontSize: 11.5, color: Colors.blue.shade800),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    _buildInputLabel("Document Title", isRequired: true),
                    _buildTextField(controller: _titleCtrl, hintText: "Enter document title"),
                    const SizedBox(height: 18),

                    _buildInputLabel("Department", isRequired: true),
                    _buildDepartmentField(),
                    const SizedBox(height: 18),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildInputLabel("Document Category (Tag)"),
                        InkWell(
                          onTap: _myDeptId == null ? null : _showAddCategoryDialog,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.add_circle_outline,
                                  size: 14,
                                  color: _myDeptId == null ? Colors.grey.shade400 : primaryBlue,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  "New",
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: _myDeptId == null ? Colors.grey.shade400 : primaryBlue,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    _buildDropdownField(
                      hintText: _myDeptId == null
                          ? "Select a department first"
                          : _isFetchingTags
                              ? "Loading categories..."
                              : _categoriesList.isEmpty
                                  ? "No categories yet — add one above"
                                  : "Select Category",
                      value: _selectedCategoryId,
                      items: _categoriesList.map<DropdownMenuItem<String>>((cat) {
                        return DropdownMenuItem<String>(
                          value: cat['id'].toString(),
                          child: Text(cat['name'] ?? 'Unknown', style: const TextStyle(fontSize: 13)),
                        );
                      }).toList(),
                      onChanged: (val) => setState(() => _selectedCategoryId = val),
                    ),
                    const SizedBox(height: 18),

                    _buildInputLabel("File Type", isRequired: true),
                    _buildDropdownField(
                      hintText: "Select File Type",
                      value: _selectedFileType,
                      items: const [
                        DropdownMenuItem(value: 'PDF', child: Text("PDF (.pdf)", style: TextStyle(fontSize: 13))),
                        DropdownMenuItem(value: 'DOCX', child: Text("Word (.docx)", style: TextStyle(fontSize: 13))),
                        DropdownMenuItem(value: 'XLSX', child: Text("Excel (.xlsx)", style: TextStyle(fontSize: 13))),
                      ],
                      onChanged: (val) => setState(() => _selectedFileType = val),
                    ),
                    const SizedBox(height: 18),

                    _buildInputLabel("Version"),
                    _buildTextField(controller: _versionCtrl, hintText: "e.g. v1.0, v2.1"),
                    const SizedBox(height: 6),
                    Text(
                      "Leave empty for auto versioning (1.0)",
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                    ),
                    const SizedBox(height: 18),

                    _buildInputLabel("Document Number", isRequired: true),
                    _buildTextField(controller: _docNumberCtrl, hintText: "e.g. SOP-001"),
                    const SizedBox(height: 24),

                    const Text(
                      "File Upload",
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.black87),
                    ),
                    const SizedBox(height: 10),
                    _buildDragDropArea(),
                    const SizedBox(height: 28),

                    ElevatedButton.icon(
                      onPressed: _isUploading ? null : _uploadDocument,
                      icon: _isUploading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Icon(Icons.cloud_upload_outlined, color: Colors.white, size: 18),
                      label: Text(
                        _isUploading ? "Uploading..." : "Submit for Approval",
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F47B2),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      onPressed: _isUploading ? null : () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: BorderSide(color: borderLight),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text("Cancel", style: TextStyle(color: Colors.black87, fontSize: 14)),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildInputLabel(String label, {bool isRequired = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: RichText(
        text: TextSpan(
          text: label,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.black87),
          children: isRequired ? [const TextSpan(text: ' *', style: TextStyle(color: Colors.red))] : [],
        ),
      ),
    );
  }

  Widget _buildTextField({required TextEditingController controller, required String hintText}) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: primaryBlue, width: 1.5)),
      ),
    );
  }

  // Locked department display once auto-detected; falls back to a plain
  // dropdown (built from the same /departments/ list) only if the
  // worker's own department couldn't be matched by name.
  Widget _buildDepartmentField() {
    if (_deptAutoDetected && _myDeptName != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.apartment, size: 16, color: Colors.grey.shade600),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _myDeptName!,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87),
              ),
            ),
            Icon(Icons.lock_outline, size: 14, color: Colors.grey.shade400),
          ],
        ),
      );
    }

    // Fallback manual picker.
    return _buildDropdownField(
      hintText: "Select your department",
      value: _myDeptId,
      items: _departmentsList.map<DropdownMenuItem<String>>((d) {
        return DropdownMenuItem<String>(
          value: d['id'].toString(),
          child: Text(d['name'] ?? 'Unknown', style: const TextStyle(fontSize: 13)),
        );
      }).toList(),
      onChanged: _onManualDeptChosen,
    );
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
          hint: Text(hintText, style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
          icon: const Icon(Icons.keyboard_arrow_down, color: Colors.grey),
          items: items.isEmpty
              ? [DropdownMenuItem(value: null, child: Text(hintText, style: TextStyle(color: Colors.grey.shade400, fontSize: 13)))]
              : items,
          onChanged: items.isEmpty ? null : onChanged,
        ),
      ),
    );
  }

  Widget _buildDragDropArea() {
    return InkWell(
      onTap: _pickFile,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
        decoration: BoxDecoration(
          color: _pickedFile != null ? Colors.green.shade50 : Colors.blue.shade50.withOpacity(0.3),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _pickedFile != null ? Colors.green.shade300 : Colors.blue.shade200,
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
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
              ),
              child: Icon(
                _pickedFile != null ? Icons.check_circle : Icons.cloud_upload_outlined,
                size: 26,
                color: _pickedFile != null ? Colors.green : Colors.blue.shade600,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              _pickedFile != null ? "File Ready: ${_pickedFile!.name}" : "Tap to choose a file",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: _pickedFile != null ? Colors.green.shade700 : Colors.black87,
              ),
            ),
            if (_pickedFile != null) ...[
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: _pickFile,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text("Change File"),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              "Supported: PDF, DOCX, XLSX • Max 50MB",
              style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}
