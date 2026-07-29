import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:isl_app/core/providers/app_state.dart';
import 'package:isl_app/views/Head/department_head_documents_screen.dart';
import 'package:isl_app/views/Head/department_head_departments_screen.dart';
import 'package:isl_app/views/Head/department_head_upload_document_screen.dart';
import 'package:isl_app/views/Head/department_head_uploaded_document_screen.dart';
import 'package:isl_app/views/Head/department_head_activity_log_screen.dart';
import 'package:isl_app/views/Head/department_head_users_screen.dart';
import 'package:isl_app/views/Head/department_head_dashboard_screen.dart';
import 'package:isl_app/views/Head/department_head_settings_screen.dart';
import 'package:isl_app/views/auth/login_screen.dart';
// Nayi Notification screen ka import add kiya gaya hai
import 'package:isl_app/views/Head/department_head_send_notification_screen.dart';
// Naya AI Assistant chat screen ka import
import 'package:isl_app/views/Head/department_head_chat_screen.dart';

class DepartmentHeadSidebar extends StatelessWidget {
  final String activeItem;

  const DepartmentHeadSidebar({super.key, required this.activeItem});

  static const Color _sidebarBg = Color(0xFF0F294D);

  void _navigateTo(BuildContext context, Widget destination) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => destination),
    );
  }

  Future<void> _signOut(BuildContext context) async {
    await context.read<AppState>().logout();
    if (!context.mounted) return;
    
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 250,
      color: _sidebarBg,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              vertical: 32.0,
              horizontal: 20.0,
            ),
            child: Row(
              children: [
                const Icon(Icons.settings, color: Colors.white, size: 28),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "ISL",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                    Text(
                      "DepartmentHead Portal",
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Nav items now live in a scrollable, flex-sized area instead of
          // sitting directly in the outer Column. With 10 fixed-height
          // items + header + logout footer, a short browser window (e.g.
          // ~700px tall) doesn't have room for everything, which was
          // throwing "RenderFlex overflowed" here. Expanded+scroll lets it
          // shrink/scroll instead of overflowing; tall windows still look
          // identical to before.
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _NavItem(
                    icon: Icons.home_outlined,
                    title: "Dashboard",
                    isActive: activeItem == "Dashboard",
                    onTap: activeItem == "Dashboard"
                        ? null
                        : () => _navigateTo(context, const DepartmentHeadDashboardScreen()),
                  ),
                  _NavItem(
                    icon: Icons.smart_toy_outlined,
                    title: "AI Assistant",
                    isActive: activeItem == "AI Assistant",
                    onTap: activeItem == "AI Assistant"
                        ? null
                        : () => _navigateTo(context, const DepartmentHeadChatScreen()),
                  ),
                  _NavItem(
                    icon: Icons.business,
                    title: "Departments",
                    isActive: activeItem == "Departments",
                    onTap: activeItem == "Departments"
                        ? null
                        : () => _navigateTo(context, const DepartmentHeadDepartmentsScreen()),
                  ),
                  _NavItem(
                    icon: Icons.description_outlined,
                    title: "All Documents",
                    isActive: activeItem == "Documents",
                    onTap: activeItem == "Documents"
                        ? null
                        : () => _navigateTo(context, const DepartmentHeadDocumentsScreen()),
                  ),
                  _NavItem(
                    icon: Icons.cloud_upload_outlined,
                    title: "Add Document",
                    isActive: activeItem == "Upload Document",
                    onTap: activeItem == "Upload Document"
                        ? null
                        : () => _navigateTo(context, DepartmentHeadUploadDocumentScreen()),
                  ),
                  _NavItem(
                    icon: Icons.file_present_rounded,
                    title: "My Uploads",
                    isActive: activeItem == "Uploaded Documents",
                    onTap: activeItem == "Uploaded Documents"
                        ? null
                        : () => _navigateTo(context, DepartmentHeadUploadedDocumentScreen()),
                  ),
                  _NavItem(
                    icon: Icons.history,
                    title: "Activity Log",
                    isActive: activeItem == "Activity Log",
                    onTap: activeItem == "Activity Log"
                        ? null
                        : () => _navigateTo(context, const DepartmentHeadActivityLogScreen()),
                  ),

                  // ── Naya Notifications Button ──
                  _NavItem(
                    icon: Icons.notifications_active_outlined,
                    title: "Notifications",
                    isActive: activeItem == "Notifications",
                    onTap: activeItem == "Notifications"
                        ? null
                        : () => _navigateTo(context, const DepartmentHeadSendNotificationScreen()),
                  ),

                  _NavItem(
                    icon: Icons.people_outline,
                    title: "Users",
                    isActive: activeItem == "Users",
                    onTap: activeItem == "Users"
                        ? null
                        : () => _navigateTo(context, const DepartmentHeadUsersScreen()),
                  ),
                  _NavItem(
                    icon: Icons.settings_outlined,
                    title: "Settings",
                    isActive: activeItem == "Settings",
                    onTap: activeItem == "Settings"
                        ? null
                        : () => _navigateTo(context, const DepartmentHeadSettingsScreen()),
                  ),
                ],
              ),
            ),
          ),

          Container(
            padding: const EdgeInsets.all(20),
            color: Colors.black.withOpacity(0.1),
            child: GestureDetector(
              onTap: () => _signOut(context),
              child: const Row(
                children: [
                  Icon(Icons.logout, color: Colors.white70, size: 18),
                  SizedBox(width: 8),
                  Text(
                    "Sign out",
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    super.key,
    required this.icon,
    required this.title,
    required this.isActive,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final bool isActive;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFF163E75) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        leading: Icon(
          icon,
          color: isActive ? Colors.white : Colors.grey.shade400,
          size: 20,
        ),
        title: Text(
          title,
          style: TextStyle(
            color: isActive ? Colors.white : Colors.grey.shade300,
            fontSize: 14,
          ),
        ),
        onTap: onTap ?? () {},
      ),
    );
  }
}