import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:isl_app/core/services/api_service.dart';
import 'package:isl_app/widgets/admin/admin_sidebar.dart';
import 'package:isl_app/widgets/admin/admin_top_header.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ADMIN SETTINGS SCREEN
//
// Every control on this screen is backed by the real SystemSettings
// endpoint (GET/PATCH /api/settings/) and actually changes backend
// behavior:
//   - Allow Workers to download documents  -> enforced in the
//     Document `download` action (403 for Workers when off)
//   - Enable document versioning           -> enforced in the
//     Document `replace` action (auto-bumps version when on)
//   - Show inactive documents by default   -> enforced in
//     DocumentViewSet.get_queryset for Department Heads
//   - Enable inline file preview           -> enforced in the
//     Document `view` action (403 for everyone when off)
//   - Default items per page               -> read by the frontend as
//     the default page_size sent on list requests
//
// Visual pass only (Jul 2026): grouped sections, icon-tagged rows, and
// a dirty-state save bar. No new fields, no API shape changes.
// ─────────────────────────────────────────────────────────────────────────────
class AdminSettingsScreen extends StatefulWidget {
  const AdminSettingsScreen({super.key});

  @override
  State<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends State<AdminSettingsScreen> {
  // ── Design tokens ────────────────────────────────────────────────────────
  static const Color _navy = Color(0xFF163E75);
  static const Color _navyDark = Color(0xFF0F2C56);
  static const Color _ink = Color(0xFF1E293B);
  static const Color _body = Color(0xFF475569);
  static const Color _muted = Color(0xFF94A3B8);
  static const Color _bgLight = Color(0xFFF8FAFC);
  static const Color _border = Color(0xFFE2E8F0);
  static final Color _navyTint = _navy.withValues(alpha: 0.07);

  final ApiService _api = ApiService();

  static const List<int> _pageSizeOptions = [10, 20, 25, 50, 100];

  bool _loading = true;
  bool _saving = false;
  String? _loadError;
  bool _canEdit = false; // true only for DEPARTMENT_HEAD / superuser

  int _defaultPageSize = 20;
  bool _allowDownload = true;
  bool _enableVersioning = true;
  bool _showInactive = false;
  bool _enablePreview = true;

  // Snapshot of what's actually saved on the server, used purely to
  // detect unsaved local edits — never sent anywhere.
  int _serverPageSize = 20;
  bool _serverAllowDownload = true;
  bool _serverEnableVersioning = true;
  bool _serverShowInactive = false;
  bool _serverEnablePreview = true;

  String? _lastUpdatedByName;
  String? _lastUpdatedAt;

  bool get _isDirty =>
      _defaultPageSize != _serverPageSize ||
      _allowDownload != _serverAllowDownload ||
      _enableVersioning != _serverEnableVersioning ||
      _showInactive != _serverShowInactive ||
      _enablePreview != _serverEnablePreview;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _checkRole();
  }

  Future<void> _checkRole() async {
    // AdminTopHeader reads the role from the 'user_data' JSON blob saved
    // by AuthService.storeUserSession() — and it works correctly. The
    // plain 'role' / 'user_role' keys and the /api/auth/me/ endpoint
    // both proved unreliable, so this mirrors the one source that's
    // actually confirmed to hold the right value.
    final prefs = await SharedPreferences.getInstance();
    String role = '';
    final userDataString = prefs.getString('user_data');
    if (userDataString != null) {
      try {
        final userData = jsonDecode(userDataString) as Map<String, dynamic>;
        role = (userData['role'] ?? '').toString();
      } catch (_) {
        // fall through to the legacy-key fallback below
      }
    }
    if (role.isEmpty) {
      role = prefs.getString('role') ?? prefs.getString('user_role') ?? '';
    }
    debugPrint('SETTINGS SCREEN — resolved role from user_data: "$role"');
    if (mounted) {
      setState(() => _canEdit = role.trim().toUpperCase() == 'DEPARTMENT_HEAD');
    }
  }

  Future<void> _loadSettings() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final data = await _api.fetchSettings();
      _applyServerData(data);
    } catch (e) {
      setState(() => _loadError = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyServerData(Map<String, dynamic> data) {
    setState(() {
      _allowDownload = data['allow_worker_downloads'] ?? true;
      _enableVersioning = data['enable_document_versioning'] ?? true;
      _showInactive = data['show_inactive_by_default'] ?? false;
      _enablePreview = data['enable_file_preview'] ?? true;
      final rawSize = data['default_page_size'];
      _defaultPageSize = rawSize is int
          ? rawSize
          : int.tryParse('$rawSize') ?? 20;
      if (!_pageSizeOptions.contains(_defaultPageSize)) {
        // Server has a value outside our dropdown's fixed options
        // (e.g. someone PATCHed 33 directly via API/admin) — snap to
        // the nearest option so the dropdown still renders validly.
        _defaultPageSize = _pageSizeOptions.reduce(
          (a, b) => (a - _defaultPageSize).abs() < (b - _defaultPageSize).abs()
              ? a
              : b,
        );
      }

      // Keep the "is this dirty" baseline in sync with whatever the
      // server just confirmed.
      _serverPageSize = _defaultPageSize;
      _serverAllowDownload = _allowDownload;
      _serverEnableVersioning = _enableVersioning;
      _serverShowInactive = _showInactive;
      _serverEnablePreview = _enablePreview;

      final updatedBy = data['updated_by_details'];
      _lastUpdatedByName =
          (updatedBy is Map ? updatedBy['full_name'] : null) as String?;
      _lastUpdatedAt = data['updated_at'] as String?;
    });
  }

  Future<void> _saveSettings() async {
    if (!_canEdit || !_isDirty) return;
    setState(() => _saving = true);
    try {
      final updated = await _api.updateSettings({
        'allow_worker_downloads': _allowDownload,
        'enable_document_versioning': _enableVersioning,
        'show_inactive_by_default': _showInactive,
        'enable_file_preview': _enablePreview,
        'default_page_size': _defaultPageSize,
      });
      _applyServerData(updated);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Settings saved successfully.'),
          backgroundColor: _navy,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save settings: $e'),
          backgroundColor: const Color(0xFFB91C1C),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _discardChanges() {
    // Reverts any unsaved edits back to the last known server state.
    setState(() {
      _defaultPageSize = _serverPageSize;
      _allowDownload = _serverAllowDownload;
      _enableVersioning = _serverEnableVersioning;
      _showInactive = _serverShowInactive;
      _enablePreview = _serverEnablePreview;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgLight,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AdminSidebar(activeItem: 'Settings'),
          Expanded(
            child: Column(
              children: [
                const AdminTopHeader(
                  title: 'Settings',
                  subtitle:
                      'Manage system settings, preferences and configurations.',
                ),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 5,
                        child: Container(
                          margin: const EdgeInsets.fromLTRB(32, 24, 0, 0),
                          constraints: const BoxConstraints(maxWidth: 760),
                          child: _buildFormPanel(),
                        ),
                      ),
                      const SizedBox(width: 32),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    '© 2026 Industrial Solutions Ltd. All rights reserved.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // FORM PANEL
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildFormPanel() {
    return Container(
      margin: const EdgeInsets.only(bottom: 32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCardHeader(),
          const Divider(height: 1, color: _border),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildCardHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: _navyTint,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.tune_rounded,
                  size: 19,
                  color: _navy,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Document & Access Settings',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                            color: _ink,
                          ),
                        ),
                        if (!_loading && _isDirty) ...[
                          const SizedBox(width: 10),
                          _buildUnsavedPill(),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Every setting below is enforced by the server — '
                      'changes take effect immediately for all users '
                      'after saving.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: _body,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (!_loading && _lastUpdatedByName != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.history_rounded, size: 13, color: _muted),
                const SizedBox(width: 5),
                Text(
                  'Last changed by $_lastUpdatedByName'
                  '${_lastUpdatedAt != null ? ' · ${_formatTimestamp(_lastUpdatedAt!)}' : ''}',
                  style: const TextStyle(fontSize: 11.5, color: _muted),
                ),
              ],
            ),
          ],
          if (!_loading && !_canEdit) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.lock_outline_rounded,
                    size: 15,
                    color: Color(0xFF92400E),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Read-only: only a Department Head can change these '
                      'settings.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF92400E),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildUnsavedPill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _navyTint,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: _navy,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          const Text(
            'Unsaved changes',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: _navy,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: _navy, strokeWidth: 2.4),
      );
    }
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.error_outline_rounded,
                  color: Color(0xFFB91C1C),
                  size: 24,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Failed to load settings: $_loadError',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: _body),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _loadSettings,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Retry'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _ink,
                  side: const BorderSide(color: _border),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return AbsorbPointer(
      absorbing: !_canEdit,
      child: Opacity(
        opacity: _canEdit ? 1.0 : 0.55,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionEyebrow('DISPLAY'),
                    const SizedBox(height: 12),
                    _buildSettingRow(
                      icon: Icons.grid_view_rounded,
                      title: 'Default Items Per Page',
                      subtitle:
                          'Default number of items returned per page on '
                          'document, user, and audit log lists.',
                      trailing: _buildPageSizeDropdown(),
                    ),

                    const SizedBox(height: 24),
                    _sectionEyebrow('ACCESS & BEHAVIOR'),
                    const SizedBox(height: 12),

                    _buildSettingRow(
                      icon: Icons.download_outlined,
                      title: 'Allow Workers to download documents',
                      subtitle:
                          'When off, the download endpoint returns "Access '
                          'Denied" for all Worker accounts, regardless of '
                          'department.',
                      trailing: _buildSwitch(
                        _allowDownload,
                        (v) => setState(() => _allowDownload = v),
                      ),
                    ),
                    _rowDivider(),
                    _buildSettingRow(
                      icon: Icons.difference_outlined,
                      title: 'Enable document versioning',
                      subtitle:
                          'When on, replacing a document\'s file '
                          'automatically increments its version number '
                          '(e.g. 1.0 → 1.1).',
                      trailing: _buildSwitch(
                        _enableVersioning,
                        (v) => setState(() => _enableVersioning = v),
                      ),
                    ),
                    _rowDivider(),
                    _buildSettingRow(
                      icon: Icons.visibility_off_outlined,
                      title: 'Show inactive documents by default',
                      subtitle:
                          'Controls whether Department Heads see inactive '
                          'documents by default in list views (Workers '
                          'never see them).',
                      trailing: _buildSwitch(
                        _showInactive,
                        (v) => setState(() => _showInactive = v),
                      ),
                    ),
                    _rowDivider(),
                    _buildSettingRow(
                      icon: Icons.remove_red_eye_outlined,
                      title: 'Enable inline file preview',
                      subtitle:
                          'When off, the in-browser document preview is '
                          'disabled for everyone, including Department '
                          'Heads.',
                      trailing: _buildSwitch(
                        _enablePreview,
                        (v) => setState(() => _enablePreview = v),
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                ),
              ),
            ),
            _buildSaveBar(),
          ],
        ),
      ),
    );
  }

  Widget _sectionEyebrow(String label) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: _muted,
      ),
    );
  }

  Widget _rowDivider() => const Divider(height: 1, color: _border);

  Widget _buildSettingRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            margin: const EdgeInsets.only(top: 1),
            decoration: BoxDecoration(
              color: _navyTint,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 16, color: _navy),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: _body,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          trailing,
        ],
      ),
    );
  }

  Widget _buildPageSizeDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(8),
        color: Colors.white,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: _defaultPageSize,
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: _muted,
            size: 18,
          ),
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: _ink,
          ),
          items: _pageSizeOptions
              .map(
                (e) => DropdownMenuItem(value: e, child: Text('$e items')),
              )
              .toList(),
          onChanged: (v) => setState(() => _defaultPageSize = v!),
        ),
      ),
    );
  }

  Widget _buildSwitch(bool value, ValueChanged<bool> onChanged) {
    return Switch(
      value: value,
      onChanged: onChanged,
      activeThumbColor: Colors.white,
      activeTrackColor: _navy,
      inactiveThumbColor: Colors.white,
      inactiveTrackColor: const Color(0xFFCBD5E1),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    );
  }

  Widget _buildSaveBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _border)),
      ),
      child: Row(
        children: [
          if (_isDirty)
            const Expanded(
              child: Text(
                'You have unsaved changes.',
                style: TextStyle(
                  fontSize: 12,
                  color: _body,
                  fontWeight: FontWeight.w500,
                ),
              ),
            )
          else
            Expanded(
              child: Row(
                children: [
                  Icon(Icons.check_circle_rounded, size: 15, color: _muted),
                  const SizedBox(width: 6),
                  const Text(
                    'All changes saved',
                    style: TextStyle(fontSize: 12, color: _muted),
                  ),
                ],
              ),
            ),
          OutlinedButton.icon(
            onPressed: (_saving || !_isDirty) ? null : _discardChanges,
            icon: const Icon(Icons.close_rounded, size: 16),
            label: const Text('Discard'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _ink,
              disabledForegroundColor: _muted,
              side: BorderSide(
                color: _isDirty ? _border : _border.withValues(alpha: 0.6),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 13,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton.icon(
            onPressed: (_saving || !_isDirty) ? null : _saveSettings,
            icon: _saving
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(
                    Icons.check_rounded,
                    size: 16,
                    color: Colors.white,
                  ),
            label: Text(
              _saving ? 'Saving…' : 'Save Changes',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _navy,
              disabledBackgroundColor: const Color(0xFFCBD5E1),
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 13,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 0,
            ).copyWith(
              overlayColor: WidgetStateProperty.all(
                _navyDark.withValues(alpha: 0.15),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    final local = dt.toLocal();
    final h = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final ampm = local.hour >= 12 ? 'PM' : 'AM';
    final min = local.minute.toString().padLeft(2, '0');
    return '${local.month}/${local.day}/${local.year} $h:$min $ampm';
  }
}