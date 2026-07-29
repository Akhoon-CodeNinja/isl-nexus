import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Reusable top header for all DepartmentHead Portal screens. Shows the page
/// title/subtitle on the left, and the signed-in user's real name +
/// designation on the right.
class DepartmentHeadTopHeader extends StatefulWidget {
  final String title;
  final String subtitle;

  const DepartmentHeadTopHeader({
    super.key,
    required this.title,
    required this.subtitle,
  });

  @override
  State<DepartmentHeadTopHeader> createState() => _DepartmentHeadTopHeaderState();
}

class _DepartmentHeadTopHeaderState extends State<DepartmentHeadTopHeader> {
  static const Color _primaryBlue = Color(0xFF163E75);

  String _fullName = '';
  String _role = '';

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final userDataString = prefs.getString('user_data');

    if (userDataString != null) {
      try {
        final userData = jsonDecode(userDataString) as Map<String, dynamic>;
        if (mounted) {
          setState(() {
            _fullName = (userData['full_name'] ?? userData['name'] ?? '').toString();
            _role = (userData['role'] ?? '').toString();
          });
        }
      } catch (_) {
        // Fallback to plain keys if JSON string parsing fails
        if (mounted) {
          setState(() {
            _fullName = prefs.getString('name') ?? prefs.getString('full_name') ?? '';
            _role = prefs.getString('role') ?? prefs.getString('user_role') ?? '';
          });
        }
      }
    } else {
      // Fallback if 'user_data' key completely missing
      if (mounted) {
        setState(() {
          _fullName = prefs.getString('name') ?? prefs.getString('full_name') ?? '';
          _role = prefs.getString('role') ?? prefs.getString('user_role') ?? '';
        });
      }
    }
  }

  String _initialsFor(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
        .toUpperCase();
  }

  /// Turns a raw backend role like "DEPARTMENT_HEAD" into a proper
  /// designation label like "Department Head" for a professional look.
  String _displayRole(String role) {
    if (role.trim().isEmpty) return 'Team Member';
    return role
        .split('_')
        .where((w) => w.isNotEmpty)
        .map((w) => '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final borderLight = Colors.grey.shade200;

    final hasName = _fullName.isNotEmpty;
    final displayName = hasName ? _fullName : 'Signed-in user';
    final displayRole = hasName ? _displayRole(_role) : '—';
    final initials = hasName ? _initialsFor(_fullName) : '?';

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 32, 32, 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // ── Left: page title + subtitle ──────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  widget.subtitle,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ],
            ),
          ),

          const SizedBox(width: 16),

          // ── Right: real signed-in user, sourced from SharedPreferences ────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: borderLight),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: _primaryBlue,
                  child: Text(
                    initials,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        displayName,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        displayRole,
                        style: TextStyle(
                            fontSize: 10, color: Colors.grey.shade600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.keyboard_arrow_down,
                    size: 16, color: Colors.grey),
              ],
            ),
          ),
        ],
      ),
    );
  }
}