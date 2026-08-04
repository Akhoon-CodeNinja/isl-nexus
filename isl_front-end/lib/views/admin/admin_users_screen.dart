import 'package:flutter/material.dart';
import 'package:isl_app/core/services/api_service.dart';
import 'package:isl_app/widgets/Admin/admin_sidebar.dart';
import 'package:isl_app/widgets/Admin/admin_top_header.dart';

// --- DATA MODEL ---
/// Admin screen — manage user accounts: role assignment, department, per-user AI chat limit override, activation.
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
  final bool canManageDocs;
  final int? chatDailyLimitOverride; // NAYA: Chat Limit ke liye

  UserModel({
    required this.id, required this.name, required this.email, required this.initials,
    required this.avatarColor, required this.department, required this.role,
    required this.isActive, required this.lastLogin, required this.canManageDocs,
    this.chatDailyLimitOverride,
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
  List<Map<String, dynamic>> _departmentsList = []; // Add User form mein department select karne ke liye
  bool _loading = true;
  String? _error;
  
  final TextEditingController _searchCtrl = TextEditingController();

  String _selectedRole = "All Roles";
  String _selectedStatus = "All Status";
  String _selectedPerPage = "10 per page";
  final List<String> _perPageOptions = ["10 per page", "20 per page", "30 per page"];

  static const List<Color> _avatarColorCycle = [
    Color(0xFF163E75), Color(0xFF14B8A6), Color(0xFFA78BFA),
    Color(0xFFFB923C), Color(0xFF4ADE80), Color(0xFFF87171),
  ];
  
  @override
  void initState() {
    super.initState();
    _fetchUsers();
    _fetchDepartmentsList();
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
  
  Future<void> _fetchDepartmentsList() async {
    try {
      final depts = await _apiService.fetchDepartmentsRaw();
      if (mounted) setState(() => _departmentsList = depts);
    } catch (e) {
      debugPrint("Could not fetch departments for dropdown: $e");
    }
  }

  Future<void> _fetchUsers() async {
    setState(() { _loading = true; _error = null; });
    try {
      final raw = await _apiService.fetchUsersRaw(); 
      final items = raw.asMap().entries.map((entry) {
        final i = entry.key;
        final json = entry.value;
        final deptDetails = json['department_details'];
        final departmentName = (deptDetails is Map ? deptDetails['name'] : null) as String? ?? 
            (json['department'] is String ? json['department'] as String : null) ?? '—';
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
          lastLogin: lastLoginRaw.isEmpty ? 'Never' : lastLoginRaw.split('T').first,
          canManageDocs: json['can_manage_docs'] ?? false,
          chatDailyLimitOverride: json['chat_daily_limit_override'] as int?,
        );
      }).toList();

      setState(() { usersList = items; _loading = false; });
    } catch (e) {
      setState(() { _error = friendlyApiError(e); _loading = false; });
    }
  }

  // --- DIALOGS & ACTIONS ---
  
  void _showAddUserDialog() {
    final formKey = GlobalKey<FormState>();
    String name = '', empId = '', email = '', password = '';
    String role = 'WORKER';
    String? selectedDept;
    bool saving = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("Add New User", style: TextStyle(fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 400,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      decoration: const InputDecoration(labelText: 'Full Name', border: OutlineInputBorder()),
                      validator: (v) => v!.isEmpty ? 'Required' : null,
                      onSaved: (v) => name = v!.trim(),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      decoration: const InputDecoration(labelText: 'Employee ID', border: OutlineInputBorder()),
                      validator: (v) => v!.isEmpty ? 'Required' : null,
                      onSaved: (v) => empId = v!.trim(),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      decoration: const InputDecoration(labelText: 'Email Address', border: OutlineInputBorder()),
                      validator: (v) => v!.isEmpty || !v.contains('@') ? 'Valid email required' : null,
                      onSaved: (v) => email = v!.trim(),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
                      obscureText: true,
                      validator: (v) => v!.length < 6 ? 'Min 6 chars' : null,
                      onSaved: (v) => password = v!,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(labelText: 'Role', border: OutlineInputBorder()),
                      value: role,
                      items: ['WORKER', 'DEPARTMENT_HEAD', 'ADMIN']
                          .map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                      onChanged: (v) => role = v!,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(labelText: 'Department', border: OutlineInputBorder()),
                      value: selectedDept,
                      items: _departmentsList.map((d) => DropdownMenuItem(
                        value: d['name'].toString(), 
                        child: Text(d['name'].toString())
                      )).toList(),
                      onChanged: (v) => selectedDept = v,
                      validator: (v) => v == null ? 'Select a department' : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: saving ? null : () => Navigator.pop(ctx), child: const Text("Cancel")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: primaryBlue),
              onPressed: saving ? null : () async {
                if (formKey.currentState!.validate()) {
                  formKey.currentState!.save();
                  setDialogState(() => saving = true);
                  try {
                    await _apiService.addUser(
                      employeeId: empId, name: name, email: email, 
                      password: password, role: role, department: selectedDept!
                    );
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User added successfully'), backgroundColor: Colors.green));
                    _fetchUsers();
                  } catch (e) {
                    setDialogState(() => saving = false);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyApiError(e)), backgroundColor: Colors.red));
                  }
                }
              },
              child: saving 
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                : const Text("Create User", style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _showChangeRoleDialog(UserModel user) {
    String newRole = user.role;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Change Role for ${user.name}"),
        content: DropdownButtonFormField<String>(
          decoration: const InputDecoration(labelText: 'Select New Role', border: OutlineInputBorder()),
          value: newRole,
          items: ['WORKER', 'DEPARTMENT_HEAD', 'ADMIN']
              .map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
          onChanged: (v) => newRole = v!,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: primaryBlue),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await _apiService.changeUserRole(user.id, newRole);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Role updated'), backgroundColor: Colors.green));
                _fetchUsers();
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyApiError(e)), backgroundColor: Colors.red));
              }
            },
            child: const Text("Update", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showSetChatLimitDialog(UserModel user) {
    final ctrl = TextEditingController(text: user.chatDailyLimitOverride?.toString() ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Set Chat Limit for ${user.name}"),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Daily Chat Limit',
            hintText: 'Leave empty for default role limit',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: primaryBlue),
            onPressed: () async {
              Navigator.pop(ctx);
              final limitVal = int.tryParse(ctrl.text.trim());
              try {
                await _apiService.setChatLimit(user.id, limitVal); // null passes if empty, which resets it
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Chat limit updated'), backgroundColor: Colors.green));
                _fetchUsers();
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyApiError(e)), backgroundColor: Colors.red));
              }
            },
            child: const Text("Save", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _handleToggleUploadAccess(UserModel user) async {
    try {
      await _apiService.toggleUploadAccess(user.id, !user.canManageDocs);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${user.name} access updated.'), backgroundColor: Colors.green),
        );
        _fetchUsers(); 
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: ${friendlyApiError(e)}'), backgroundColor: Colors.red));
      }
    }
  }

  // --- UI BUILDING ---

  List<String> get _roleOptions {
    final roles = usersList.map((u) => u.role).toSet().toList();
    roles.sort();
    return ["All Roles", ...roles];
  }

  List<String> get _statusOptions => ["All Status", "Active", "Inactive"];

  List<UserModel> get _filteredUsers {
    return usersList.where((u) {
      final matchRole = _selectedRole == "All Roles" || u.role == _selectedRole;
      final matchStatus = _selectedStatus == "All Status" || (_selectedStatus == "Active" ? u.isActive : !u.isActive);
      final matchName = u.name.toLowerCase().contains(_searchCtrl.text.toLowerCase().trim());
      return matchRole && matchStatus && matchName;
    }).toList();
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
                  title: "Users Management", 
                  subtitle: "Manage workers, roles, upload access, and chat limits.",
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final mainTableCard = Container(
                        margin: EdgeInsets.only(left: 32, bottom: 32, right: constraints.maxWidth < 980 ? 32 : 16),
                        decoration: BoxDecoration(
                          color: Colors.white, borderRadius: BorderRadius.circular(12), 
                          border: Border.all(color: borderLight), 
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))]
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
                                      : displayList.isEmpty
                                          ? const Center(child: Text('No users found.', style: TextStyle(color: Colors.grey)))
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
                      );

                      if (constraints.maxWidth < 980) {
                        return SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(height: 600, child: mainTableCard),
                              _buildRightPanel(),
                            ],
                          ),
                        );
                      }

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: mainTableCard),
                          SizedBox(width: 260, child: _buildRightPanel()),
                        ],
                      );
                    },
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
        children: [
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              onChanged: (val) => setState(() {}),
              decoration: InputDecoration(
                hintText: "Search workers by name...", 
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
          const SizedBox(width: 16),
          _buildDropdown(_selectedRole, _roleOptions, (val) => setState(() => _selectedRole = val!)),
          const SizedBox(width: 12),
          _buildDropdown(_selectedStatus, _statusOptions, (val) => setState(() => _selectedStatus = val!)),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: _showAddUserDialog,
            icon: const Icon(Icons.add, size: 18, color: Colors.white),
            label: const Text("Add User", style: TextStyle(color: Colors.white)),
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

  Widget _buildDropdown(String currentValue, List<String> items, ValueChanged<String?> onChanged) {
    if (!items.contains(currentValue) && items.isNotEmpty) currentValue = items.first;
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
          Expanded(flex: 3, child: Text("Worker", style: _hStyle())), 
          Expanded(flex: 2, child: Text("Role & Limit", style: _hStyle())), 
          Expanded(flex: 2, child: Text("Upload Access", style: _hStyle())), 
          Expanded(flex: 1, child: Text("Status", style: _hStyle())), 
          SizedBox(width: 80, child: Text("Actions", textAlign: TextAlign.center, style: _hStyle())) 
        ]
      )
    );
  }

  Widget _buildTableRow(UserModel user) {
    final limitText = user.chatDailyLimitOverride != null ? '${user.chatDailyLimitOverride}' : 'Default';
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12), 
      child: Row(
        children: [
          Expanded(flex: 3, child: Row(children: [
            CircleAvatar(radius: 16, backgroundColor: user.avatarColor, child: Text(user.initials, style: const TextStyle(color: Colors.white, fontSize: 10))), 
            const SizedBox(width: 12), 
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(user.name, style: const TextStyle(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis), 
              Text("${user.id} • ${user.email}", style: const TextStyle(fontSize: 11, color: Colors.grey), overflow: TextOverflow.ellipsis)
            ]))
          ])), 
          Expanded(flex: 2, child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(user.role, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              Text("Chat Limit: $limitText", style: const TextStyle(fontSize: 10, color: Colors.grey)),
            ],
          )),
          Expanded(flex: 2, child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), 
              decoration: BoxDecoration(color: (user.canManageDocs || user.role != 'WORKER') ? Colors.blue.shade50 : Colors.grey.shade100, borderRadius: BorderRadius.circular(4)), 
              child: Text(
                user.role != 'WORKER' ? 'FULL ACCESS' : (user.canManageDocs ? 'ALLOWED' : 'NO ACCESS'), 
                style: TextStyle(color: (user.canManageDocs || user.role != 'WORKER') ? primaryBlue : Colors.grey, fontSize: 10, fontWeight: FontWeight.bold), 
                overflow: TextOverflow.ellipsis
              )
            ),
          )), 
          Expanded(flex: 1, child: Row(children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: user.isActive ? Colors.green : Colors.grey, shape: BoxShape.circle)), 
            const SizedBox(width: 6), 
            Expanded(child: Text(user.isActive ? "Active" : "Inactive", overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)))
          ])), 
          SizedBox(
            width: 80, 
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center, 
              children: [
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 16), 
                  padding: EdgeInsets.zero,
                  onSelected: (value) {
                    if (value == 'toggle_access' && user.role == 'WORKER') _handleToggleUploadAccess(user);
                    if (value == 'change_role') _showChangeRoleDialog(user);
                    if (value == 'set_limit') _showSetChatLimitDialog(user);
                  },
                  itemBuilder: (context) => [
                    if (user.role == 'WORKER')
                      PopupMenuItem(
                        value: 'toggle_access', 
                        child: Text(user.canManageDocs ? 'Revoke Upload Access' : 'Grant Upload Access')
                      ),
                    const PopupMenuItem(value: 'change_role', child: Text('Change Role')),
                    const PopupMenuItem(value: 'set_limit', child: Text('Set Chat Limit')),
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
          Expanded(
            child: Text("Showing ${currentCount == 0 ? 0 : 1}-$currentCount of ${usersList.length} total users", overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ),
          SizedBox(
            height: 32,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(onPressed: () {}, icon: const Icon(Icons.chevron_left, size: 18)), 
                const Text("1", style: TextStyle(fontSize: 12)), 
                IconButton(onPressed: () {}, icon: const Icon(Icons.chevron_right, size: 18))
              ]
            ),
          ), 
          _buildDropdown(_selectedPerPage, _perPageOptions, (val) => setState(() => _selectedPerPage = val!))
        ]
      )
    );
  }

  Widget _buildRightPanel() {
    final displayList = _filteredUsers; 
    final total = displayList.length;
    final active = displayList.where((u) => u.isActive).length;
    final canUpload = displayList.where((u) => u.canManageDocs || u.role != 'WORKER').length;
    
    return Container(
      margin: const EdgeInsets.only(right: 32, bottom: 32), 
      padding: const EdgeInsets.all(24), 
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(12), 
        border: Border.all(color: borderLight), 
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))]
      ), 
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, 
        children: [
          const Text("Overview", style: TextStyle(fontWeight: FontWeight.bold)), 
          const SizedBox(height: 16), 
          _sCard(total.toString(), "Total Users", Colors.blue), 
          const SizedBox(height: 8), 
          _sCard(active.toString(), "Active Users", Colors.green), 
          const SizedBox(height: 8), 
          _sCard(canUpload.toString(), "Upload Access", Colors.orange), 
        ]
      )
    );
  }

  Widget _sCard(String c, String l, Color clr) => ListTile(
    leading: Icon(Icons.person, color: clr), 
    title: Text(c, style: const TextStyle(fontWeight: FontWeight.bold)), 
    subtitle: Text(l, style: const TextStyle(fontSize: 11)),
    contentPadding: EdgeInsets.zero,
  );
}