import 'package:flutter/material.dart';
import 'package:isl_app/widgets/worker/worker_header.dart';
import 'package:isl_app/widgets/worker/worker_bottom_nav.dart';
import 'package:isl_app/views/worker/worker_chat_screen.dart';
import 'package:isl_app/views/worker/worker_documents_screen.dart';
import 'package:isl_app/views/worker/worker_alerts_screen.dart';
import 'package:isl_app/views/auth/login_screen.dart';
import 'package:isl_app/core/models/auth_models.dart';
import 'package:isl_app/core/services/api_service.dart';
import 'package:isl_app/views/worker/worker_edit_profile_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// WORKER PROFILE SCREEN
//
// Backed by GET /api/auth/me/ via ApiService.getProfile() — no hardcoded
// name/employee-id/department/etc. Note: the backend User model has no
// `phone` field at all today, so that row is shown as "Not provided"
// rather than a made-up number; add a phone field server-side if you
// want it to be real.
// ─────────────────────────────────────────────────────────────────────────────
class WorkerProfileScreen extends StatefulWidget {
  const WorkerProfileScreen({super.key});

  @override
  State<WorkerProfileScreen> createState() => _WorkerProfileScreenState();
}

class _WorkerProfileScreenState extends State<WorkerProfileScreen> {
  final ApiService _api = ApiService();

  bool _isLoading = true;
  String? _errorMessage;
  UserProfile? _profile;

  @override
  void initState() {
    super.initState();
    _fetchProfile();
  }

  Future<void> _fetchProfile() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final profile = await _api.getProfile();
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = friendlyApiError(e);
      });
    }
  }

  // ── Navigation ────────────────────────────────────────────────────────────
  void _handleNav(BuildContext context, int index) {
    if (index == 3) return; // already here
    Widget dest;
    switch (index) {
      case 0:  dest = const WorkerChatScreen();      break;
      case 1:  dest = const WorkerDocumentsScreen(); break;
      case 2:  dest = const WorkerAlertsScreen();    break;
      default: return;
    }
    Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => dest));
  }

  // ── Logout ────────────────────────────────────────────────────────────────
  void _logout(BuildContext context) {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  // ── Edit Profile ──────────────────────────────────────────────────────────
  Future<void> _openEditProfile(BuildContext context) async {
    if (_profile == null) return;
    final updated = await Navigator.push<UserProfile>(
      context,
      MaterialPageRoute(
        builder: (_) => WorkerEditProfileScreen(profile: _profile!),
      ),
    );
    if (updated != null && mounted) {
      setState(() => _profile = updated);
    }
  }

  // ── About ─────────────────────────────────────────────────────────────────
  // Static app info — legitimately doesn't need a backend call.
  void _showAboutDialog(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'ISL App',
      applicationVersion: '1.0.0',
      applicationLegalese: '\u00a9 ${DateTime.now().year} ISL. All rights reserved.',
      children: const [
        SizedBox(height: 12),
        Text('Internal document, alerts, and communication hub for ISL staff.'),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // ── Global header ─────────────────────────────────────────────
            const WorkerHeader(),

            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: Color(0xFF163E75)))
                  : _errorMessage != null
                      ? _buildErrorState()
                      : RefreshIndicator(
                          onRefresh: _fetchProfile,
                          color: const Color(0xFF163E75),
                          child: SingleChildScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 16),

                                // ── Profile overview card ─────────────────
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  child: _buildOverviewCard(_profile!),
                                ),
                                const SizedBox(height: 20),

                                // ── Account settings card ──────────────────
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  child: _buildSettingsCard(context),
                                ),
                                const SizedBox(height: 28),
                              ],
                            ),
                          ),
                        ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: WorkerBottomNav(
        activeIndex: 3,
        onTap: (i) => _handleNav(context, i),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 40, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(_errorMessage ?? 'Something went wrong.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _fetchProfile,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF163E75),
              ),
              child: const Text('Retry', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 1. PROFILE OVERVIEW CARD
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildOverviewCard(UserProfile profile) {
    final roleLabel = _formatRole(profile.role);

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Card header row ─────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Profile Overview',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E293B))),
                // Role badge — reflects the signed-in user's actual role
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEBF2FF),
                    border: Border.all(color: const Color(0xFF90CAF9)),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(roleLabel,
                      style: const TextStyle(
                          color: Color(0xFF163E75),
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: Colors.grey.shade100),

          // ── Info rows ────────────────────────────────────────────────────
          _InfoRow(
            icon:  Icons.person_outline,
            label: 'Full Name',
            value: profile.fullName.isNotEmpty ? profile.fullName : 'Not set',
          ),
          _InfoRow(
            icon:  Icons.badge,
            label: 'Employee ID',
            value: profile.employeeId.isNotEmpty ? profile.employeeId : 'Not set',
          ),
          _InfoRow(
            icon:  Icons.business,
            label: 'Department',
            value: profile.department.isNotEmpty ? profile.department : 'Not assigned',
          ),
          _InfoRow(
            icon:  Icons.access_time,
            label: 'Shift Timing',
            value: profile.shift.isNotEmpty ? profile.shift : 'Not set',
          ),
          _InfoRow(
            icon:  Icons.work_outline,
            label: 'Role',
            value: roleLabel,
          ),
          _InfoRow(
            icon:  Icons.mail_outline,
            label: 'Email',
            value: profile.email.isNotEmpty ? profile.email : 'Not set',
          ),
          _InfoRow(
            icon:   Icons.phone,
            label:  'Phone',
            // The backend User model has no phone field yet — show this
            // honestly instead of a made-up number.
            value:  profile.phone?.isNotEmpty == true ? profile.phone! : 'Not provided',
            isLast: true,
          ),
        ],
      ),
    );
  }

  String _formatRole(String rawRole) {
    switch (rawRole.toUpperCase()) {
      case 'DEPARTMENT_HEAD':
        return 'Department Head';
      case 'WORKER':
        return 'Worker';
      default:
        return rawRole.isEmpty ? 'Worker' : rawRole;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 2. ACCOUNT SETTINGS CARD
  // ─────────────────────────────────────────────────────────────────────────
  //
  // Notification Settings, Language, and Privacy & Security were removed:
  // none of them are backed by anything real yet (no push-notification
  // infra, no localization setup, no password/security endpoint), so a
  // tap did nothing. Help & Support was also removed for now — the
  // backend already has GET /api/help/ (see ApiService.fetchQuickHelp),
  // but building that screen needs the QuickHelpItem model shape, which
  // isn't in what's been shared yet. Send that file over and it can be
  // wired back in properly instead of guessing its fields.
  Widget _buildSettingsCard(BuildContext context) {
    final List<_SettingsItemData> items = [
      _SettingsItemData(
          icon: Icons.manage_accounts,
          label: 'Edit Profile',
          onTap: () => _openEditProfile(context)),
      _SettingsItemData(
          icon: Icons.info_outline,
          label: 'About ISL App',
          onTap: () => _showAboutDialog(context)),
      _SettingsItemData(
          icon: Icons.logout,
          label: 'Logout',
          isDestructive: true,
          onTap: () => _logout(context)),
    ];

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Card title
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 10),
            child: Text('Account Settings',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B))),
          ),
          Divider(height: 1, color: Colors.grey.shade100),

          // Tiles
          ...List.generate(items.length, (i) {
            final item = items[i];
            final isLast = i == items.length - 1;
            return _SettingsTile(item: item, isLast: isLast);
          }),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DATA MODEL for settings items
// ─────────────────────────────────────────────────────────────────────────────
class _SettingsItemData {
  const _SettingsItemData({
    required this.icon,
    required this.label,
    this.trailing,
    this.isDestructive = false,
    this.onTap,
  });
  final IconData      icon;
  final String        label;
  final String?       trailing;
  final bool          isDestructive;
  final VoidCallback? onTap;
}

// ─────────────────────────────────────────────────────────────────────────────
// PRIVATE WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

/// White card with soft shadow, used for both sections
class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 3)),
        ],
      ),
      child: child,
    );
  }
}

/// A single row in the Profile Overview section
class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.isLast = false,
  });
  final IconData icon;
  final String   label;
  final String   value;
  final bool     isLast;

  static const Color _iconBg    = Color(0xFFEDF2F7);
  static const Color _iconColor = Color(0xFF5B7EA7);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Icon container
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _iconBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: _iconColor, size: 18),
              ),
              const SizedBox(width: 14),

              // Label
              Text(label,
                  style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w500)),

              const SizedBox(width: 8),

              // Value — right-aligned, flexible so it wraps if needed
              Expanded(
                child: Text(
                  value,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF1E293B),
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        if (!isLast)
          Divider(
              height: 1,
              indent: 16,
              endIndent: 16,
              color: Colors.grey.shade100),
      ],
    );
  }
}

/// A single ListTile row in the Account Settings section
class _SettingsTile extends StatelessWidget {
  const _SettingsTile({required this.item, required this.isLast});
  final _SettingsItemData item;
  final bool              isLast;

  static const Color _iconBg    = Color(0xFFEDF2F7);
  static const Color _iconColor = Color(0xFF5B7EA7);
  static const Color _redBg     = Color(0xFFFFEBEE);

  @override
  Widget build(BuildContext context) {
    final bool    isRed = item.isDestructive;
    final Color   fg    = isRed ? Colors.red.shade600 : const Color(0xFF1E293B);

    return Column(
      children: [
        ListTile(
          onTap: item.onTap ?? () {},
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isRed ? _redBg : _iconBg,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Icon(item.icon,
                color: isRed ? Colors.red.shade600 : _iconColor,
                size: 18),
          ),
          title: Text(item.label,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: fg)),
          trailing: _buildTrailing(isRed),
          minLeadingWidth: 36,
        ),
        if (!isLast)
          Divider(
              height: 1,
              indent: 68,
              endIndent: 16,
              color: Colors.grey.shade100),
      ],
    );
  }

  Widget _buildTrailing(bool isRed) {
    final Color arrowColor =
        isRed ? Colors.red.shade400 : Colors.grey.shade400;
    if (item.trailing != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(item.trailing!,
              style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade500,
                  fontWeight: FontWeight.w500)),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right, color: arrowColor, size: 20),
        ],
      );
    }
    return Icon(Icons.chevron_right, color: arrowColor, size: 20);
  }
}