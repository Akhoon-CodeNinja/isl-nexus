import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:isl_app/core/services/api_service.dart';
import 'package:isl_app/widgets/admin/admin_sidebar.dart';
import 'package:isl_app/widgets/admin/admin_top_header.dart';

// --- DATA MODEL ---
class UserModel {
  final String id;
  final String name;
  final String email;
  final String initials;
  final Color avatarColor;
  final String department;
  final String role;
  final bool isActive;
  final String lastLogin;

  UserModel({
    required this.id, required this.name, required this.email, required this.initials,
    required this.avatarColor, required this.department, required this.role,
    required this.isActive, required this.lastLogin,
  });
}

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  final Color sidebarColor = const Color(0xFF0F294D);
  final Color primaryBlue = const Color(0xFF163E75);
  final Color bgLight = const Color(0xFFF8FAFC);
  final Color borderLight = Colors.grey.shade200;

  final ApiService _apiService = ApiService();

  List<UserModel> usersList = [];
  bool _loading = true;
  String? _error;
  
  final TextEditingController _searchCtrl = TextEditingController();

  // Dropdown States
  String _selectedRole = "All Roles";
  String _selectedStatus = "All Status";
  
  // Pagination State
  String _selectedPerPage = "10 per page";
  final List<String> _perPageOptions = ["10 per page", "20 per page", "30 per page"];

  static const List<Color> _avatarColorCycle = [
    Color(0xFF163E75),
    Color(0xFF14B8A6),
    Color(0xFFA78BFA),
    Color(0xFFFB923C),
    Color(0xFF4ADE80),
    Color(0xFFF87171),
  ];
  
  @override
  void initState() {
    super.initState();
    _fetchUsers();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String _initialsFor(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  Future<void> _handleToggleStatus(UserModel user) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Updating status for ${user.name}...')),
    );
    
    try {
      await _apiService.toggleUserStatus(user.id, !user.isActive);
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${user.name} is now ${!user.isActive ? "Active" : "Inactive"}.'),
            backgroundColor: Colors.green,
          ),
        );
        _fetchUsers(); 
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
  
  Future<void> _fetchUsers() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await _apiService.fetchUsersRaw(); 
      final items = raw.asMap().entries.map((entry) {
        final i = entry.key;
        final json = entry.value;
        final deptDetails = json['department_details'];
        final departmentName = (deptDetails is Map ? deptDetails['name'] : null)
                as String? ??
            (json['department'] is String ? json['department'] as String : null) ??
            '—';
        final fullName = (json['full_name'] ?? json['name'] ?? 'Unknown user').toString();
        final lastLoginRaw = (json['last_login'] ?? '').toString();
        return UserModel(
          id: (json['id'] ?? '').toString(),
          name: fullName,
          email: (json['email'] ?? '').toString(),
          initials: _initialsFor(fullName),
          avatarColor: _avatarColorCycle[i % _avatarColorCycle.length],
          department: departmentName,
          role: (json['role'] ?? 'WORKER').toString(),
          isActive: json['is_active'] is bool ? json['is_active'] as bool : true,
          lastLogin: lastLoginRaw.isEmpty ? 'Never' : lastLoginRaw,
        );
      }).toList();

      setState(() {
        usersList = items;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  List<String> get _roleOptions {
    final roles = usersList.map((u) => u.role).toSet().toList();
    roles.sort();
    return ["All Roles", ...roles];
  }

  List<String> get _statusOptions => ["All Status", "Active", "Inactive"];

  List<UserModel> get _filteredUsers {
    return usersList.where((u) {
      final matchRole = _selectedRole == "All Roles" || u.role == _selectedRole;
      final matchStatus = _selectedStatus == "All Status" || 
                          (_selectedStatus == "Active" ? u.isActive : !u.isActive);
      final matchName = u.name.toLowerCase().contains(_searchCtrl.text.toLowerCase().trim());
      
      return matchRole && matchStatus && matchName;
    }).toList();
  }

  Future<void> _handleChangeRole(UserModel user) async {
    final newRole = user.role == 'DEPARTMENT_HEAD' ? 'WORKER' : 'DEPARTMENT_HEAD';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Updating role for ${user.name}...')),
    );
    
    try {
      await _apiService.changeUserRole(user.id, newRole);
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${user.name} is now a $newRole.'),
            backgroundColor: Colors.green,
          ),
        );
        _fetchUsers(); 
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update role: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _handleDeleteUser(UserModel user) async {
    // Confirm before deleting — this is permanent, so make sure the admin
    // means it before we ever call the backend.
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete User"),
        content: Text(
          "Are you sure you want to permanently delete ${user.name}? This action cannot be undone.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Deleting ${user.name}...')),
    );

    try {
      await _apiService.deleteUser(user.id);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${user.name} deleted successfully.'),
            backgroundColor: Colors.green,
          ),
        );
        _fetchUsers(); // Refresh the list
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete user: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  
  
  void _showAddUserDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    String dialogRole = 'WORKER';
    String dialogDept = 'Information Technology';
    bool isSubmitting = false;

    showDialog(
      context: context,
      barrierDismissible: false, 
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text("Add New User"),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl, 
                      decoration: const InputDecoration(labelText: "Full Name"),
                      enabled: !isSubmitting,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: emailCtrl, 
                      decoration: const InputDecoration(labelText: "Email address"),
                      enabled: !isSubmitting,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: dialogRole,
                      decoration: const InputDecoration(labelText: "Role"),
                      items: const [
                        DropdownMenuItem(value: 'WORKER', child: Text('WORKER')),
                        DropdownMenuItem(value: 'DEPARTMENT_HEAD', child: Text('DEPARTMENT_HEAD')),
                      ],
                      onChanged: isSubmitting ? null : (val) => setStateDialog(() => dialogRole = val!),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      initialValue: dialogDept,
                      decoration: const InputDecoration(labelText: "Department"),
                      enabled: !isSubmitting,
                      onChanged: (val) => dialogDept = val,
                    )
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.pop(context), 
                  child: const Text("Cancel")
                ),
                ElevatedButton(
                  onPressed: isSubmitting ? null : () async {
                    final name = nameCtrl.text.trim();
                    final email = emailCtrl.text.trim();
                    
                    if (name.isEmpty || email.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Name and Email are required.'))
                      );
                      return;
                    }

                    setStateDialog(() => isSubmitting = true);

                    try {
                      await _apiService.addUser(
                        name: name,
                        email: email,
                        role: dialogRole,
                        department: dialogDept,
                      );

                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('User $name added successfully!'), backgroundColor: Colors.green)
                        );
                        _fetchUsers(); 
                      }
                    } catch (e) {
                      setStateDialog(() => isSubmitting = false);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error adding user: $e'), backgroundColor: Colors.red)
                        );
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: primaryBlue, foregroundColor: Colors.white),
                  child: isSubmitting 
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text("Save User"),
                ),
              ],
            );
          }
        );
      }
    );
  }

  void _showEditUserDialog(BuildContext context, UserModel user) {
    final nameCtrl = TextEditingController(text: user.name);
    final emailCtrl = TextEditingController(text: user.email);
    String dialogDept = user.department;
    bool isSubmitting = false;

    showDialog(
      context: context,
      barrierDismissible: false, 
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text("Edit User"),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl, 
                      decoration: const InputDecoration(labelText: "Full Name"),
                      enabled: !isSubmitting,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: emailCtrl, 
                      decoration: const InputDecoration(labelText: "Email address"),
                      enabled: !isSubmitting,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      initialValue: dialogDept,
                      decoration: const InputDecoration(labelText: "Department"),
                      enabled: !isSubmitting,
                      onChanged: (val) => dialogDept = val,
                    )
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.pop(context), 
                  child: const Text("Cancel")
                ),
                ElevatedButton(
                  onPressed: isSubmitting ? null : () async {
                    final name = nameCtrl.text.trim();
                    final email = emailCtrl.text.trim();
                    
                    if (name.isEmpty || email.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Name and Email are required.'))
                      );
                      return;
                    }

                    setStateDialog(() => isSubmitting = true);

                    try {
                      await _apiService.updateUser(
                        user.id,
                        name: name,
                        email: email,
                        department: dialogDept,
                      );

                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('User updated successfully!'), backgroundColor: Colors.green)
                        );
                        _fetchUsers(); 
                      }
                    } catch (e) {
                      setStateDialog(() => isSubmitting = false);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error updating user: $e'), backgroundColor: Colors.red)
                        );
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: primaryBlue, foregroundColor: Colors.white),
                  child: isSubmitting 
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text("Save Changes"),
                ),
              ],
            );
          }
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    final displayList = _filteredUsers;

    return Scaffold(
      backgroundColor: bgLight,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AdminSidebar(activeItem: "Users"),
          Expanded(
            child: Column(
              children: [
                const AdminTopHeader(
                  title: "Users",
                  subtitle: "Manage system users and their access permissions.",
                ),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Container(
                          margin: const EdgeInsets.only(left: 32, bottom: 32, right: 16),
                          decoration: BoxDecoration(
                            color: Colors.white, 
                            borderRadius: BorderRadius.circular(12), 
                            border: Border.all(color: borderLight), 
                            boxShadow: [
                              BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))
                            ]
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
                                        ? Center(
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.error_outline, color: Colors.red.shade400, size: 32),
                                                const SizedBox(height: 12),
                                                Text(_error!, style: const TextStyle(color: Colors.black87)),
                                                const SizedBox(height: 12),
                                                OutlinedButton(
                                                  onPressed: _fetchUsers,
                                                  child: const Text('Retry'),
                                                ),
                                              ],
                                            ),
                                          )
                                        : displayList.isEmpty
                                            ? const Center(
                                                child: Text('No users found matching filters.', style: TextStyle(color: Colors.grey)),
                                              )
                                            : ListView.separated(
                                                itemCount: displayList.length,
                                                separatorBuilder: (context, index) => const Divider(height: 1),
                                                itemBuilder: (context, index) => _buildTableRow(displayList[index]),
                                              ),
                              ),
                              const Divider(height: 1),
                              _buildPagination(displayList.length),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 260, 
                        child: _buildRightPanel(),
                      ),
                    ],
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Below this width, the search field + two dropdowns + button
          // can't all fit on one line without clipping — this is exactly
          // what was overflowing before. Stack them instead of forcing
          // a single Row.
          final isNarrow = constraints.maxWidth < 700;

          final searchField = TextField(
            controller: _searchCtrl,
            onChanged: (val) => setState(() {}),
            decoration: InputDecoration(
              hintText: "Search users by name...",
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          );

          final controls = Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _buildDropdown(_selectedRole, _roleOptions, (val) => setState(() => _selectedRole = val!)),
              _buildDropdown(_selectedStatus, _statusOptions, (val) => setState(() => _selectedStatus = val!)),
              ElevatedButton.icon(
                onPressed: () => _showAddUserDialog(context),
                style: ElevatedButton.styleFrom(backgroundColor: primaryBlue, foregroundColor: Colors.white),
                icon: const Icon(Icons.add, size: 18),
                label: const Text("Add User"),
              ),
            ],
          );

          if (isNarrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                searchField,
                const SizedBox(height: 12),
                controls,
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: searchField),
              const SizedBox(width: 16),
              Flexible(child: controls),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDropdown(String currentValue, List<String> items, ValueChanged<String?> onChanged) {
    if (!items.contains(currentValue) && items.isNotEmpty) {
      currentValue = items.first;
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12), 
      decoration: BoxDecoration(border: Border.all(color: borderLight), borderRadius: BorderRadius.circular(6)), 
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: currentValue, 
          items: items.map((i) => DropdownMenuItem(value: i, child: Text(i, style: const TextStyle(fontSize: 12)))).toList(), 
          onChanged: onChanged
        )
      )
    );
  }

  TextStyle _hStyle() => const TextStyle(fontWeight: FontWeight.bold, fontSize: 12);

  Widget _buildTableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12), 
      color: Colors.grey.shade50, 
      child: Row(
        children: [
          Expanded(flex: 3, child: Text("User", style: _hStyle())), 
          Expanded(flex: 2, child: Text("Department", style: _hStyle())), 
          Expanded(flex: 2, child: Text("Role", style: _hStyle())), 
          Expanded(flex: 1, child: Text("Status", style: _hStyle())), 
          Expanded(flex: 2, child: Text("Last Login", style: _hStyle())), 
          SizedBox(width: 80, child: Text("Actions", textAlign: TextAlign.center, style: _hStyle())) 
        ]
      )
    );
  }

  Widget _buildTableRow(UserModel user) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12), 
      child: Row(
        children: [
          Expanded(flex: 3, child: Row(children: [
            CircleAvatar(radius: 16, backgroundColor: user.avatarColor, child: Text(user.initials, style: const TextStyle(color: Colors.white, fontSize: 10))), 
            const SizedBox(width: 12), 
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(user.name, style: const TextStyle(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis), 
              Text(user.email, style: const TextStyle(fontSize: 11, color: Colors.grey), overflow: TextOverflow.ellipsis)
            ]))
          ])), 
          Expanded(flex: 2, child: Text(user.department, overflow: TextOverflow.ellipsis)), 
          Expanded(flex: 2, child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), 
              decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(4)), 
              child: Text(user.role, style: TextStyle(color: primaryBlue, fontSize: 10, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)
            ),
          )), 
          Expanded(flex: 1, child: Row(children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: user.isActive ? Colors.green : Colors.grey, shape: BoxShape.circle)), 
            const SizedBox(width: 6), 
            Expanded(child: Text(user.isActive ? "Active" : "Inactive", overflow: TextOverflow.ellipsis))
          ])), 
          Expanded(flex: 2, child: Text(user.lastLogin, style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis, maxLines: 2)), 
          SizedBox(
            width: 80, 
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center, 
              children: [
                IconButton(
                  icon: const Icon(Icons.edit, size: 16), 
                  onPressed: () => _showEditUserDialog(context, user), 
                  padding: EdgeInsets.zero, 
                  constraints: const BoxConstraints()
                ), 
                const SizedBox(width: 8), 
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 16), 
                  padding: EdgeInsets.zero,
                  onSelected: (value) {
                    if (value == 'toggle_status') {
                      _handleToggleStatus(user);
                    } else if (value == 'change_role') {
                      _handleChangeRole(user);
                    } else if (value == 'delete_user') {
                      _handleDeleteUser(user);
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(value: 'toggle_status', child: Text(user.isActive ? 'Deactivate User' : 'Activate User')),
                    PopupMenuItem(value: 'change_role', child: Text(user.role == 'DEPARTMENT_HEAD' ? 'Make Worker' : 'Make Admin')),
                    // Only show delete for inactive users — an active
                    // account should be deactivated first, not deleted
                    // outright, to avoid accidentally nuking someone
                    // currently using the system.
                    if (!user.isActive)
                      const PopupMenuItem(
                        value: 'delete_user',
                        child: Text(
                          'Delete User',
                          style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                        ),
                      ),
                  ],
                )
              ]
            )
          )
        ]
      )
    );
  }

  Widget _buildPagination(int currentCount) {
    return Padding(
      padding: const EdgeInsets.all(16.0), 
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween, 
        children: [
          Text("Showing ${currentCount == 0 ? 0 : 1}-$currentCount of ${usersList.length} total users"), 
          Row(
            children: [
              IconButton(onPressed: () {}, icon: const Icon(Icons.chevron_left)), 
              const Text("1"), 
              IconButton(onPressed: () {}, icon: const Icon(Icons.chevron_right))
            ]
          ), 
          _buildDropdown(
            _selectedPerPage, 
            _perPageOptions, 
            (val) => setState(() => _selectedPerPage = val!)
          )
        ]
      )
    );
  }

  Widget _buildRightPanel() {
    final displayList = _filteredUsers; 
    final total = displayList.length;
    final active = displayList.where((u) => u.isActive).length;
    final inactive = total - active;
    
    final Map<String, int> roleCounts = {};
    for (var user in displayList) {
      roleCounts[user.role] = (roleCounts[user.role] ?? 0) + 1;
    }

    final List<Color> chartColors = [
      primaryBlue,
      const Color(0xFF14B8A6), 
      const Color(0xFFFB923C), 
      const Color(0xFFA78BFA), 
    ];

    int colorIndex = 0;
    final pieSections = roleCounts.entries.map((entry) {
      final color = chartColors[colorIndex % chartColors.length];
      colorIndex++;
      final percentage = total > 0 ? (entry.value / total * 100) : 0.0;
      
      return PieChartSectionData(
        color: color,
        value: entry.value.toDouble(),
        title: '${percentage.toStringAsFixed(0)}%',
        radius: 25,
        titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
      );
    }).toList();

    return Container(
      margin: const EdgeInsets.only(right: 32, bottom: 32), 
      padding: const EdgeInsets.all(24), 
      decoration: BoxDecoration(
        color: Colors.white, 
        borderRadius: BorderRadius.circular(12), 
        border: Border.all(color: borderLight), 
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))
        ]
      ), 
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, 
        children: [
          const Text("User Overview", style: TextStyle(fontWeight: FontWeight.bold)), 
          const SizedBox(height: 16), 
          _sCard(total.toString(), "Total Users", Colors.blue), 
          const SizedBox(height: 8), 
          _sCard(active.toString(), "Active Users", Colors.green), 
          const SizedBox(height: 8), 
          _sCard(inactive.toString(), "Inactive Users", Colors.grey), 
          const SizedBox(height: 24), 
          const Text("Role Distribution", style: TextStyle(fontWeight: FontWeight.bold)), 
          const SizedBox(height: 16), 
          
          Expanded(
            child: total == 0 
              ? const Center(child: Text("No users found", style: TextStyle(color: Colors.grey)))
              : Column(
                  children: [
                    Expanded(
                      child: PieChart(
                        PieChartData(
                          sectionsSpace: 2,
                          centerSpaceRadius: 30,
                          sections: pieSections,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: roleCounts.keys.toList().asMap().entries.map((entry) {
                        final idx = entry.key;
                        final roleName = entry.value;
                        return ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 110),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 12, 
                                height: 12, 
                                decoration: BoxDecoration(
                                  color: chartColors[idx % chartColors.length],
                                  shape: BoxShape.circle,
                                )
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  roleName, 
                                  style: const TextStyle(fontSize: 11),
                                  overflow: TextOverflow.ellipsis,
                                )
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    )
                  ],
                )
          )
        ]
      )
    );
  }

  Widget _sCard(String c, String l, Color clr) => ListTile(leading: Icon(Icons.person, color: clr), title: Text(c, style: const TextStyle(fontWeight: FontWeight.bold)), subtitle: Text(l));
}