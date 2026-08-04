import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter_quill/flutter_quill.dart' as quill; // Quill Editor Import

import 'package:isl_app/core/providers/app_state.dart';
import 'package:isl_app/core/services/api_service.dart'; // friendlyApiError() for user-facing error text
import 'package:isl_app/views/worker/worker_documents_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// WORKER CREATE DOCUMENT SCREEN (MS WORD STYLE)
//
// Allows workers to type a document directly in the app using a rich text
// editor (flutter_quill) that looks like MS Word.
// ─────────────────────────────────────────────────────────────────────────────
/// Worker screen — compose a new document with a rich-text editor and generate a PDF for submission.
class WorkerCreateDocumentScreen extends StatefulWidget {
  const WorkerCreateDocumentScreen({super.key});

  @override
  State<WorkerCreateDocumentScreen> createState() => _WorkerCreateDocumentScreenState();
}

class _WorkerCreateDocumentScreenState extends State<WorkerCreateDocumentScreen> {
  final Color primaryBlue = const Color(0xFF163E75);
  final Color bgLight = const Color(0xFFF8FAFC);
  final Color borderLight = Colors.grey.shade200;

  final String _baseUrl = kIsWeb ? 'http://127.0.0.1:8000/api' : 'http://10.0.2.2:8000/api';

  // Form Controllers
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _docNumberCtrl = TextEditingController();
  
  // MS Word style editor ka controller
  final quill.QuillController _quillController = quill.QuillController.basic();

  // Backend Data Lists
  List<dynamic> _departmentsList = [];
  List<dynamic> _categoriesList = [];

  String? _myDeptId;
  String? _myDeptName;
  bool _deptAutoDetected = false;
  String? _selectedCategoryId;

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
    _quillController.dispose();
    super.dispose();
  }

  // --- FETCH DEPARTMENTS AND LOCK ---
  Future<void> _fetchDropdownData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token') ?? '';
      
      final deptRes = await http.get(
        Uri.parse('$_baseUrl/departments/'),
        headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
      );

      if (deptRes.statusCode == 200) {
        var deptData = jsonDecode(deptRes.body);
        final list = deptData is Map && deptData.containsKey('results') ? deptData['results'] as List : deptData as List;

        final appState = mounted ? context.read<AppState>() : null;
        final myDeptName = (appState?.profile?.department ?? prefs.getString('department') ?? '').trim();

        Map<String, dynamic>? match;
        for (final d in list) {
          if ((d['name'] ?? '').toString().toLowerCase() == myDeptName.toLowerCase()) {
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
            _myDeptName = myDeptName.isEmpty ? null : myDeptName;
            _deptAutoDetected = false;
          }
          _isFetchingData = false;
        });

        if (_myDeptId != null) _fetchTagsForDepartment(_myDeptId!);
      } else {
        _showSnackBar("Failed to load department info.", isError: true);
        setState(() => _isFetchingData = false);
      }
    } catch (e) {
      _showSnackBar("Error connecting to server.", isError: true);
      setState(() => _isFetchingData = false);
    }
  }

  Future<void> _fetchTagsForDepartment(String departmentId) async {
    setState(() {
      _isFetchingTags = true;
      _categoriesList = [];
      _selectedCategoryId = null;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token') ?? '';
      
      final tagRes = await http.get(
        Uri.parse('$_baseUrl/tags/?department=$departmentId'),
        headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
      );

      if (tagRes.statusCode == 200) {
        var tagData = jsonDecode(tagRes.body);
        setState(() {
          _categoriesList = tagData is Map && tagData.containsKey('results') ? tagData['results'] : tagData;
          _isFetchingTags = false;
        });
      } else {
        setState(() => _isFetchingTags = false);
      }
    } catch (e) {
      setState(() => _isFetchingTags = false);
    }
  }

  Future<void> _showAddCategoryDialog() async {
    final nameCtrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text("New Category"),
          content: TextField(
            controller: nameCtrl,
            autofocus: true,
            decoration: const InputDecoration(hintText: "e.g. Policies", border: OutlineInputBorder()),
            onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, nameCtrl.text.trim()),
              style: ElevatedButton.styleFrom(backgroundColor: primaryBlue),
              child: const Text("Add", style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );

    if (result != null && result.isNotEmpty) _createTag(result);
  }

  Future<void> _createTag(String name) async {
    if (_myDeptId == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token') ?? '';
      
      final res = await http.post(
        Uri.parse('$_baseUrl/tags/'),
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
        body: jsonEncode({'name': name, 'department': _myDeptId}),
      );

      if (res.statusCode == 201) {
        final created = jsonDecode(res.body);
        setState(() {
          _categoriesList = [..._categoriesList, created];
          _selectedCategoryId = created['id'].toString();
        });
        _showSnackBar("Category '$name' added.");
      } else {
        _showSnackBar("Could not add category.", isError: true);
      }
    } catch (e) {
      _showSnackBar("Error adding category.", isError: true);
    }
  }

  // --- PDF GENERATOR & UPLOADER ---
  Future<void> _generateAndUpload() async {
    final plainTextContent = _quillController.document.toPlainText().trim();

    if (_titleCtrl.text.trim().isEmpty) return _showSnackBar("Enter Document Title.", isError: true);
    if (_docNumberCtrl.text.trim().isEmpty) return _showSnackBar("Enter Document Number.", isError: true);
    if (_myDeptId == null) return _showSnackBar("Department missing.", isError: true);
    if (plainTextContent.isEmpty) return _showSnackBar("Document content cannot be empty.", isError: true);

    setState(() => _isUploading = true);

    try {
      // 1. Generate PDF from Editor Content
      final pdf = pw.Document();
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (pw.Context context) {
            return [
              pw.Header(
                level: 0,
                child: pw.Text(
                  _titleCtrl.text.trim(),
                  style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
                ),
              ),
              pw.SizedBox(height: 10),
              pw.Text("Doc Number: ${_docNumberCtrl.text.trim()} | Department: $_myDeptName", style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
              pw.SizedBox(height: 20),
              pw.Paragraph(
                text: plainTextContent,
                style: const pw.TextStyle(fontSize: 12, lineSpacing: 1.5),
              ),
            ];
          }
        )
      );

      // 2. Upload the PDF straight from memory (MultipartFile.fromBytes)
      // instead of writing it to a temp file first. This previously used
      // getTemporaryDirectory() (path_provider) + dart:io's File, which
      // has no implementation on Flutter web -- browsers don't expose a
      // filesystem temp directory -- and threw MissingPluginException
      // there. Uploading the bytes directly works the same way on web,
      // mobile, and desktop, and is simpler besides.
      final pdfBytes = await pdf.save();
      final safeTitle = _titleCtrl.text.trim().replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
      final fileName = '${safeTitle}_${DateTime.now().millisecondsSinceEpoch}.pdf';

      // 3. Upload exactly like normal file upload
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token') ?? '';

      var request = http.MultipartRequest('POST', Uri.parse('$_baseUrl/documents/'));
      request.headers.addAll({'Authorization': 'Bearer $token'});

      request.fields['title'] = _titleCtrl.text.trim();
      request.fields['doc_number'] = _docNumberCtrl.text.trim();
      request.fields['file_type'] = 'PDF'; 
      request.fields['version'] = '1.0';
      request.fields['departments'] = _myDeptId!;
      if (_selectedCategoryId != null) {
        request.fields['tag_ids'] = _selectedCategoryId!;
      }

      request.files.add(
        http.MultipartFile.fromBytes('file_url', pdfBytes, filename: fileName),
      );

      var response = await request.send();

      if (response.statusCode == 201 || response.statusCode == 200) {
        _showSnackBar("Document created and submitted for approval!");
        if (mounted) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const WorkerDocumentsScreen()));
        }
      } else {
        String resBody = await response.stream.bytesToString();
        _showSnackBar("Failed to upload: $resBody", isError: true);
      }
    } catch (e) {
      _showSnackBar("Error generating document: ${friendlyApiError(e)}", isError: true);
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: isError ? Colors.red : Colors.green),
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
        title: const Text('Create New Document', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
                      child: Row(
                        children: [
                          Icon(Icons.edit_document, size: 16, color: Colors.blue.shade700),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              "Write your document using the MS Word style editor below. It will automatically be converted to a PDF.",
                              style: TextStyle(fontSize: 11.5, color: Colors.blue.shade800),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    _buildInputLabel("Document Title", isRequired: true),
                    _buildTextField(controller: _titleCtrl, hintText: "e.g. Leave Policy 2026"),
                    const SizedBox(height: 18),

                    _buildInputLabel("Document Number", isRequired: true),
                    _buildTextField(controller: _docNumberCtrl, hintText: "e.g. POL-001"),
                    const SizedBox(height: 18),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildInputLabel("Category (Tag)"),
                        InkWell(
                          onTap: _myDeptId == null ? null : _showAddCategoryDialog,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: Text("+ New", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: primaryBlue)),
                          ),
                        ),
                      ],
                    ),
                    _buildDropdownField(
                      hintText: _categoriesList.isEmpty ? "No categories yet" : "Select Category",
                      value: _selectedCategoryId,
                      items: _categoriesList.map<DropdownMenuItem<String>>((cat) {
                        return DropdownMenuItem<String>(
                          value: cat['id'].toString(),
                          child: Text(cat['name'] ?? 'Unknown', style: const TextStyle(fontSize: 13)),
                        );
                      }).toList(),
                      onChanged: (val) => setState(() => _selectedCategoryId = val),
                    ),
                    const SizedBox(height: 24),

                    // ── MS WORD STYLE EDITOR (FLUTTER QUILL v10.8 API) ──
                    // v10 dropped the QuillProvider/*Configurations wrapper
                    // pattern used in v8/v9 -- the controller now goes
                    // straight on QuillSimpleToolbar/QuillEditor.basic, and
                    // the config classes were renamed *Configurations ->
                    // *Config (param renamed configurations: -> config:).
                    _buildInputLabel("Document Body (Content)", isRequired: true),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // TOOLBAR (Bold, Italic, Bullets etc)
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
                              borderRadius: const BorderRadius.only(topLeft: Radius.circular(8), topRight: Radius.circular(8)),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                            child: quill.QuillSimpleToolbar(
                              controller: _quillController,
                              config: const quill.QuillSimpleToolbarConfig(
                                showFontFamily: false,
                                showFontSize: false,
                                showSearchButton: false,
                                showInlineCode: false,
                                showCodeBlock: false,
                                showColorButton: true,
                                showBackgroundColorButton: true,
                              ),
                            ),
                          ),
                          // WRITING AREA
                          Container(
                            height: 350,
                            padding: const EdgeInsets.all(16),
                            child: quill.QuillEditor.basic(
                              controller: _quillController,
                              config: const quill.QuillEditorConfig(
                                placeholder: 'Start typing your professional document here...',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),

                    ElevatedButton.icon(
                      onPressed: _isUploading ? null : _generateAndUpload,
                      icon: _isUploading
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.picture_as_pdf, color: Colors.white, size: 18),
                      label: Text(
                        _isUploading ? "Generating PDF..." : "Generate PDF & Submit",
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
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: primaryBlue, width: 1.5)),
      ),
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
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          hint: Text(hintText, style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
          items: items,
          onChanged: items.isEmpty ? null : onChanged,
        ),
      ),
    );
  }
}