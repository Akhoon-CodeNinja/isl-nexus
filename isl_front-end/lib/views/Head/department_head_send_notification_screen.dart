import 'package:flutter/material.dart';
import 'package:isl_app/core/services/api_service.dart';
import 'package:isl_app/widgets/Head/department_head_sidebar.dart';
import 'package:isl_app/widgets/Head/department_head_top_header.dart';

/// Department Head screen — send an alert/notification to their department.
class DepartmentHeadSendNotificationScreen extends StatefulWidget {
  const DepartmentHeadSendNotificationScreen({super.key});

  @override
  State<DepartmentHeadSendNotificationScreen> createState() => _DepartmentHeadSendNotificationScreenState();
}

class _DepartmentHeadSendNotificationScreenState extends State<DepartmentHeadSendNotificationScreen> {
  static const Color _primaryBlue = Color(0xFF163E75);
  final ApiService _apiService = ApiService();
  
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _descCtrl = TextEditingController();

  bool _isLoading = false;
  bool _isLoadingDepartments = true;

  // Dropdown states updated to match Django models.py exact values
  String _selectedType = 'ANNOUNCEMENT'; 
  String? _selectedDepartmentId; // null means 'All Departments'
  
  List<Map<String, dynamic>> _departments = [];

  @override
  void initState() {
    super.initState();
    _fetchDepartments();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchDepartments() async {
    try {
      final depts = await _apiService.fetchDepartmentsRaw();
      if (mounted) {
        setState(() {
          _departments = depts;
          _isLoadingDepartments = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingDepartments = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to load departments'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _sendNotification() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      await _apiService.sendNotification(
        title: _titleCtrl.text.trim(),
        description: _descCtrl.text.trim(),
        type: _selectedType,
        targetDepartmentId: _selectedDepartmentId,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Notification sent successfully! ✅'),
            backgroundColor: Colors.green,
          ),
        );
        // Clear form after success
        _titleCtrl.clear();
        _descCtrl.clear();
        setState(() {
          _selectedType = 'ANNOUNCEMENT';
          _selectedDepartmentId = null;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyApiError(e)),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Row(
        children: [
          // ── Sidebar ──────────────────────────────────────────────────────────
          const DepartmentHeadSidebar(activeItem: 'Notifications'),

          // ── Main Content Area ──────────────────────────────────────────────
          Expanded(
            child: Column(
              children: [
                // ── Header ───────────────────────────────────────────────────
                const DepartmentHeadTopHeader(
                  title: 'Send Notification',
                  subtitle: 'Broadcast alerts or updates to workers and departments.',
                ),

                // ── Form Area ────────────────────────────────────────────────
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 700),
                        padding: const EdgeInsets.all(32),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.shade200),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.02),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildSectionTitle('Notification Details'),
                              const SizedBox(height: 20),
                              
                              // Target Department Dropdown
                              _buildLabel('Target Audience (Department)'),
                              _isLoadingDepartments
                                  ? const Padding(
                                      padding: EdgeInsets.symmetric(vertical: 12),
                                      child: CircularProgressIndicator(),
                                    )
                                  : DropdownButtonFormField<String?>(
                                      initialValue: _selectedDepartmentId,
                                      decoration: _inputDecoration(),
                                      items: [
                                        const DropdownMenuItem(
                                          value: null,
                                          child: Text('All Departments (Broadcast)'),
                                        ),
                                        ..._departments.map((dept) {
                                          return DropdownMenuItem(
                                            value: strId(dept['id']),
                                            child: Text(dept['name'].toString()),
                                          );
                                        }),
                                      ],
                                      onChanged: (val) => setState(() => _selectedDepartmentId = val),
                                    ),
                              
                              const SizedBox(height: 20),

                              // Alert Type Dropdown (Updated based on models.py)
                              _buildLabel('Alert Type'),
                              DropdownButtonFormField<String>(
                                initialValue: _selectedType,
                                decoration: _inputDecoration(),
                                items: const [
                                  DropdownMenuItem(value: 'ANNOUNCEMENT', child: Text('Announcement')),
                                  DropdownMenuItem(value: 'MAINTENANCE', child: Text('Maintenance (System Update)')),
                                  DropdownMenuItem(value: 'EMERGENCY', child: Text('Emergency Alert (Red)')),
                                  DropdownMenuItem(value: 'SAFETY', child: Text('Safety Notice')),
                                ],
                                onChanged: (val) => setState(() => _selectedType = val!),
                              ),

                              const SizedBox(height: 20),

                              // Title Input
                              _buildLabel('Title'),
                              TextFormField(
                                controller: _titleCtrl,
                                decoration: _inputDecoration().copyWith(hintText: 'e.g., Server Maintenance Tonight'),
                                validator: (v) => v == null || v.isEmpty ? 'Title is required' : null,
                              ),
                              
                              const SizedBox(height: 20),

                              // Message Input
                              _buildLabel('Message Description'),
                              TextFormField(
                                controller: _descCtrl,
                                maxLines: 5,
                                decoration: _inputDecoration().copyWith(
                                  hintText: 'Type your message details here...',
                                ),
                                validator: (v) => v == null || v.isEmpty ? 'Message is required' : null,
                              ),
                              
                              const SizedBox(height: 32),

                              // Submit Button
                              SizedBox(
                                width: double.infinity,
                                height: 50,
                                child: ElevatedButton.icon(
                                  onPressed: _isLoading ? null : _sendNotification,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _primaryBlue,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  icon: _isLoading 
                                      ? const SizedBox.shrink() 
                                      : const Icon(Icons.send_rounded, size: 20),
                                  label: _isLoading
                                      ? const SizedBox(
                                          width: 24, height: 24,
                                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                        )
                                      : const Text(
                                          'Broadcast Notification',
                                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
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

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
      ),
    );
  }

  InputDecoration _inputDecoration() {
    return InputDecoration(
      filled: true,
      fillColor: Colors.grey.shade50,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _primaryBlue, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }

  String strId(dynamic id) => id.toString();
}