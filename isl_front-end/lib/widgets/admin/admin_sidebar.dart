import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:isl_app/core/providers/app_state.dart';
import 'package:isl_app/views/admin/admin_documents_screen.dart';
import 'package:isl_app/views/admin/admin_departments_screen.dart';
import 'package:isl_app/views/admin/admin_upload_document_screen.dart';
// Naya import:
import 'package:isl_app/views/admin/admin_uploaded_document_screen.dart';
import 'package:isl_app/views/admin/admin_activity_log_screen.dart';
import 'package:isl_app/views/admin/admin_users_screen.dart';
import 'package:isl_app/views/admin/admin_dashboard_screen.dart';
import 'package:isl_app/views/admin/admin_settings_screen.dart';
import 'package:isl_app/views/auth/login_screen.dart';

class AdminSidebar extends StatelessWidget {
  final String activeItem;

  const AdminSidebar({super.key, required this.activeItem});

  static const Color _sidebarBg = Color(0xFF0F294D);

  void _navigateTo(BuildContext context, Widget destination) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => destination),
    );
  }

  void _signOut(BuildContext context) {
    context.read<AppState>().logout();
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
                      "Admin Portal",
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

          _NavItem(
            icon: Icons.home_outlined,
            title: "Dashboard",
            isActive: activeItem == "Dashboard",
            onTap: activeItem == "Dashboard"
                ? null
                : () => _navigateTo(context, const AdminDashboardScreen()),
          ),
          _NavItem(
            icon: Icons.business,
            title: "Departments",
            isActive: activeItem == "Departments",
            onTap: activeItem == "Departments"
                ? null
                : () => _navigateTo(context, const AdminDepartmentsScreen()),
          ),
          _NavItem(
            icon: Icons.description_outlined,
            title: "All Documents",
            isActive: activeItem == "Documents",
            onTap: activeItem == "Documents"
                ? null
                : () => _navigateTo(context, const AdminDocumentsScreen()),
          ),
          _NavItem(
            icon: Icons.cloud_upload_outlined,
            title: "Add Document",
            isActive: activeItem == "Upload Document",
            onTap: activeItem == "Upload Document"
                ? null
                : () => _navigateTo(context, AdminUploadDocumentScreen()),
          ),
          // Yahan humne naya "Uploaded Documents" ka tab daal diya hai
          _NavItem(
            icon: Icons.file_present_rounded,
            title: "My Uploads",
            isActive: activeItem == "Uploaded Documents",
            onTap: activeItem == "Uploaded Documents"
                ? null
                : () =>
                      _navigateTo(context, const AdminUploadedDocumentScreen()),
          ),
          _NavItem(
            icon: Icons.history,
            title: "Activity Log",
            isActive: activeItem == "Activity Log",
            onTap: activeItem == "Activity Log"
                ? null
                : () => _navigateTo(context, const AdminActivityLogScreen()),
          ),
          _NavItem(
            icon: Icons.people_outline,
            title: "Users",
            isActive: activeItem == "Users",
            onTap: activeItem == "Users"
                ? null
                : () => _navigateTo(context, const AdminUsersScreen()),
          ),
          _NavItem(
            icon: Icons.settings_outlined,
            title: "Settings",
            isActive: activeItem == "Settings",
            onTap: activeItem == "Settings"
                ? null
                : () => _navigateTo(context, const AdminSettingsScreen()),
          ),

          const Spacer(),

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
