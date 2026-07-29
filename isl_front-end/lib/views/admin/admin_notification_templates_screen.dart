import 'package:flutter/material.dart';
import 'package:isl_app/core/services/api_service.dart';
import 'package:isl_app/widgets/Admin/admin_sidebar.dart';
import 'package:isl_app/widgets/Admin/admin_top_header.dart';

// --- DATA MODEL ---
class TemplateModel {
  final String id;
  final String title;
  final String body;
  final String type;
  final String status;
  final String createdAt;

  TemplateModel({
    required this.id, required this.title, required this.body,
    required this.type, required this.status, required this.createdAt,
  });
}

// --- MAIN SCREEN ---
class AdminNotificationTemplatesScreen extends StatefulWidget {
  const AdminNotificationTemplatesScreen({super.key});

  @override
  State<AdminNotificationTemplatesScreen> createState() => _AdminNotificationTemplatesScreenState();
}

class _AdminNotificationTemplatesScreenState extends State<AdminNotificationTemplatesScreen> {
  final Color sidebarColor = const Color(0xFF0F294D);
  final Color primaryBlue = const Color(0xFF163E75);
  final Color bgLight = const Color(0xFFF8FAFC);
  final Color borderLight = Colors.grey.shade200;

  final ApiService _apiService = ApiService();

  List<TemplateModel> templatesList = [];
  bool _loading = true;
  String? _error;
  String selectedStatus = 'All Status';

  @override
  void initState() {
    super.initState();
    _fetchTemplates();
  }

  Future<void> _fetchTemplates() async {
    setState(() { _loading = true; _error = null; });
    try {
      final raw = await _apiService.fetchNotificationTemplates(status: selectedStatus);
      final items = raw.map((json) => TemplateModel(
        id: (json['id'] ?? '').toString(),
        title: (json['title'] ?? '').toString(),
        body: (json['body'] ?? '').toString(),
        type: (json['type'] ?? 'GENERAL').toString(),
        status: (json['status'] ?? 'NEW').toString(),
        createdAt: (json['created_at'] ?? '').toString().split('T').first,
      )).toList();

      setState(() { templatesList = items; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _showTemplateDialog({TemplateModel? template}) {
    final _formKey = GlobalKey<FormState>();
    String title = template?.title ?? '';
    String body = template?.body ?? '';
    String type = template?.type ?? 'GENERAL';
    bool saving = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(template == null ? "Create Template" : "Edit Template", style: const TextStyle(fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 500,
            child: Form(
              key: _formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      initialValue: title,
                      decoration: const InputDecoration(labelText: 'Template Title', border: OutlineInputBorder()),
                      validator: (v) => v!.isEmpty ? 'Required' : null,
                      onSaved: (v) => title = v!.trim(),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(labelText: 'Alert Type', border: OutlineInputBorder()),
                      value: type,
                      items: ['GENERAL', 'SYSTEM', 'EMERGENCY', 'SAFETY', 'ANNOUNCEMENT', 'MAINTENANCE']
                          .map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                      onChanged: (v) => setDialogState(() => type = v!),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      initialValue: body,
                      decoration: const InputDecoration(labelText: 'Message Body', border: OutlineInputBorder()),
                      maxLines: 5,
                      validator: (v) => v!.isEmpty ? 'Required' : null,
                      onSaved: (v) => body = v!.trim(),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: saving ? null : () => Navigator.pop(ctx), child: const Text("Cancel")),
            ElevatedButton(
              onPressed: saving ? null : () async {
                if (_formKey.currentState!.validate()) {
                  _formKey.currentState!.save();
                  setDialogState(() => saving = true);
                  try {
                    if (template == null) {
                      await _apiService.createNotificationTemplate(title: title, bodyText: body, type: type);
                    } else {
                      await _apiService.updateNotificationTemplate(template.id, title: title, bodyText: body, type: type);
                    }
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Template saved successfully'), backgroundColor: Colors.green));
                    _fetchTemplates();
                  } catch (e) {
                    setDialogState(() => saving = false);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyApiError(e)), backgroundColor: Colors.red));
                  }
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: primaryBlue),
              child: saving 
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                : Text(template == null ? "Create" : "Save", style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteTemplate(String id) async {
    try {
      await _apiService.deleteNotificationTemplate(id);
      _fetchTemplates();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyApiError(e)), backgroundColor: Colors.red));
    }
  }

  Future<void> _setStatus(String id, String status) async {
    try {
      await _apiService.setNotificationTemplateStatus(id, status);
      _fetchTemplates();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyApiError(e)), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgLight,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AdminSidebar(activeItem: "Notification Templates"),
          Expanded(
            child: Column(
              children: [
                const AdminTopHeader(
                  title: "Notification Templates",
                  subtitle: "Manage reusable alert messages to broadcast to departments.",
                ),
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.only(left: 32, bottom: 32, right: 32),
                    decoration: BoxDecoration(
                      color: Colors.white, borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: borderLight),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildToolbar(),
                        const Divider(height: 1),
                        _buildTableHeader(),
                        const Divider(height: 1),
                        Expanded(
                          child: _loading
                              ? const Center(child: CircularProgressIndicator())
                              : _error != null
                              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
                              : templatesList.isEmpty
                              ? const Center(child: Text('No templates found.', style: TextStyle(color: Colors.grey)))
                              : ListView.separated(
                                  itemCount: templatesList.length,
                                  separatorBuilder: (context, index) => const Divider(height: 1),
                                  itemBuilder: (context, index) => _buildTableRow(templatesList[index]),
                                ),
                        ),
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

  Widget _buildToolbar() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Text("Filter: ", style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: selectedStatus,
                items: ['All Status', 'NEW', 'ACTIVE', 'INACTIVE'].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                onChanged: (v) {
                  setState(() => selectedStatus = v!);
                  _fetchTemplates();
                },
              ),
            ],
          ),
          ElevatedButton.icon(
            onPressed: () => _showTemplateDialog(),
            icon: const Icon(Icons.add, size: 18, color: Colors.white),
            label: const Text("Create Template", style: TextStyle(color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryBlue,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      color: Colors.grey.shade50,
      child: Row(
        children: [
          Expanded(flex: 3, child: Text("Title", style: _hStyle())),
          Expanded(flex: 2, child: Text("Type", style: _hStyle())),
          Expanded(flex: 1, child: Text("Status", style: _hStyle())),
          Expanded(flex: 1, child: Text("Created At", style: _hStyle())),
          SizedBox(width: 80, child: Text("Actions", textAlign: TextAlign.center, style: _hStyle())),
        ],
      ),
    );
  }

  TextStyle _hStyle() => const TextStyle(fontWeight: FontWeight.bold, fontSize: 12);

  Widget _buildTableRow(TemplateModel template) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text(template.title, style: const TextStyle(fontWeight: FontWeight.bold))),
          Expanded(flex: 2, child: Text(template.type, style: const TextStyle(fontSize: 12, color: Colors.grey))),
          Expanded(
            flex: 1, 
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: template.status == 'ACTIVE' ? Colors.green.shade50 : (template.status == 'NEW' ? Colors.blue.shade50 : Colors.grey.shade100),
                borderRadius: BorderRadius.circular(4)
              ),
              child: Text(template.status, style: TextStyle(fontSize: 10, color: template.status == 'ACTIVE' ? Colors.green : (template.status == 'NEW' ? Colors.blue : Colors.grey), fontWeight: FontWeight.bold)),
            )
          ),
          Expanded(flex: 1, child: Text(template.createdAt, style: const TextStyle(fontSize: 12))),
          SizedBox(
            width: 80, 
            child: PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 16),
              onSelected: (val) {
                if (val == 'edit') _showTemplateDialog(template: template);
                if (val == 'delete') _deleteTemplate(template.id);
                if (val == 'ACTIVE' || val == 'INACTIVE' || val == 'NEW') _setStatus(template.id, val);
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(value: 'edit', child: Text('Edit Template')),
                if (template.status != 'ACTIVE') const PopupMenuItem(value: 'ACTIVE', child: Text('Mark Active')),
                if (template.status != 'INACTIVE') const PopupMenuItem(value: 'INACTIVE', child: Text('Mark Inactive')),
                const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.red))),
              ]
            )
          )
        ],
      ),
    );
  }
}