import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Shared dark-blue header used across all Worker screens.
// Fetches real user data from SharedPreferences.
// ─────────────────────────────────────────────────────────────────────────────
class WorkerHeader extends StatefulWidget {
  const WorkerHeader({super.key});

  @override
  State<WorkerHeader> createState() => _WorkerHeaderState();
}

class _WorkerHeaderState extends State<WorkerHeader> {
  static const Color _darkBlue = Color(0xFF0F294D);

  String _fullName = 'Loading...';
  String _department = 'Loading...';
  String _shift = '';
  String _initials = '?';

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
        
        // Agar backend response mein data 'user' key ke andar hai, toh usay nikal lein
        final userObj = userData['user'] is Map<String, dynamic> ? userData['user'] : userData;

        if (mounted) {
          setState(() {
            _fullName = (userObj['full_name'] ?? userObj['name'] ?? 'Signed-in User').toString();
            _department = (userObj['department_details']?['name'] ?? userObj['department'] ?? 'General').toString();
            _shift = (userObj['shift_timing'] ?? '').toString();
            _initials = _initialsFor(_fullName);
          });
        }
      } catch (_) {
        _fallbackLoad(prefs);
      }
    } else {
      _fallbackLoad(prefs);
    }
  }

  void _fallbackLoad(SharedPreferences prefs) {
    if (mounted) {
      setState(() {
        _fullName =
            prefs.getString('name') ??
            prefs.getString('full_name') ??
            'Signed-in User';
        _department = prefs.getString('department') ?? 'General';
        _shift = prefs.getString('shift') ?? '';
        _initials = _initialsFor(_fullName);
      });
    }
  }

  String _initialsFor(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _darkBlue,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── Hamburger ──────────────────────────────────────────────────
          const Icon(Icons.menu, color: Colors.white, size: 24),
          const SizedBox(width: 12),

          // ── Avatar + online dot ────────────────────────────────────────
          Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: const Color(0xFF1E88E5),
                child: Text(
                  _initials,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: Colors.greenAccent.shade400,
                    shape: BoxShape.circle,
                    border: Border.all(color: _darkBlue, width: 2),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 10),

          // ── Name / dept / shift ────────────────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      _fullName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green.shade600,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'Online',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '$_department Department',
                  style: const TextStyle(
                    color: Color(0xFFB0BEC5),
                    fontSize: 11,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 1),
                Text(
                  _shift.isEmpty ? 'Shift not set' : 'Shift: $_shift',
                  style: const TextStyle(color: Color(0xFFB0BEC5), fontSize: 10),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          // ── Emergency button ───────────────────────────────────────────
          ElevatedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.phone, size: 13, color: Colors.white),
            label: const Text(
              'Emergency\nContact',
              style: TextStyle(fontSize: 9, color: Colors.white, height: 1.4),
              textAlign: TextAlign.center,
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 0,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }
}