import 'package:flutter/material.dart';
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
  final bool canManageDocs; // Naya field

  UserModel({
    required this.id, required this.name, required this.email, required this.initials,
    required this.avatarColor, required this.department, required this.role,
    required this.isActive, required this.lastLogin, required this.canManageDocs,
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

  String _selectedRole = "All Roles";
  String _selectedStatus = "All Status";
  
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
          canManageDocs: json['can_manage_docs'] ?? false, // Mapping new field
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

  // --- NAYA FUNCTION: Upload Rights Delegate Karne Ke Liye ---
  Future<void> _handleToggleUploadAccess(UserModel user) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Updating permissions for ${user.name}...')),
    );
    
    try {
      await _apiService.toggleUploadAccess(user.id, !user.canManageDocs);
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${user.name} now has ${!user.canManageDocs ? "UPLOAD" : "NO UPLOAD"} access.'),
            backgroundColor: Colors.green,
          ),
        );
        _fetchUsers(); 
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update access: $e'), backgroundColor: Colors.red),
        );
      }
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
                  title: "Department Users", // Text updated to reflect Head perspective
                  subtitle: "Manage your department's workers and their upload permissions.",
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final mainTableCard = Container(
                        margin: EdgeInsets.only(
                          left: 32,
                          bottom: 32,
                          right: constraints.maxWidth < 980 ? 32 : 16,
                        ),
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
                      );

                      // Narrow window: stack the table above the overview
                      // panel, both full-width, instead of squeezing them
                      // side-by-side (which wrapped column headers letter-
                      // by-letter, as seen in the "Department Users" screenshot).
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 700;

          final searchField = TextField(
            controller: _searchCtrl,
            onChanged: (val) => setState(() {}),
            decoration: InputDecoration(
              hintText: "Search workers by name...", // Changed placeholder
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
              // Add User button has been completely removed from here
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
          Expanded(flex: 3, child: Text("Worker", style: _hStyle())), 
          Expanded(flex: 2, child: Text("Upload Access", style: _hStyle())), // Changed Column Name
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
          Expanded(flex: 2, child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), 
              decoration: BoxDecoration(color: user.canManageDocs ? Colors.blue.shade50 : Colors.grey.shade100, borderRadius: BorderRadius.circular(4)), 
              child: Text(
                user.role == 'DEPARTMENT_HEAD' ? 'FULL ACCESS (Head)' : (user.canManageDocs ? 'ALLOWED' : 'NO ACCESS'), 
                style: TextStyle(color: user.canManageDocs ? primaryBlue : Colors.grey, fontSize: 10, fontWeight: FontWeight.bold), 
                overflow: TextOverflow.ellipsis
              )
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
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 16), 
                  padding: EdgeInsets.zero,
                  onSelected: (value) {
                    if (value == 'toggle_access' && user.role != 'DEPARTMENT_HEAD') {
                      _handleToggleUploadAccess(user);
                    }
                  },
                  itemBuilder: (context) => [
                    if (user.role != 'DEPARTMENT_HEAD')
                      PopupMenuItem(
                        value: 'toggle_access', 
                        child: Text(
                          user.canManageDocs ? 'Revoke Upload Access' : 'Grant Upload Access',
                          style: TextStyle(color: user.canManageDocs ? Colors.red : Colors.green),
                        )
                      ),
                    if (user.role == 'DEPARTMENT_HEAD')
                      const PopupMenuItem(
                        value: 'no_action',
                        enabled: false,
                        child: Text('Head has inherent rights'),
                      )
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
            child: Text(
              "Showing ${currentCount == 0 ? 0 : 1}-$currentCount of ${usersList.length} total users",
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            height: 32,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(onPressed: () {}, icon: const Icon(Icons.chevron_left)), 
                  const Text("1"), 
                  IconButton(onPressed: () {}, icon: const Icon(Icons.chevron_right))
                ]
              ),
            ),
          ), 
          const SizedBox(width: 12),
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
    final canUpload = displayList.where((u) => u.canManageDocs || u.role == 'DEPARTMENT_HEAD').length;
    
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
          const Text("Department Overview", style: TextStyle(fontWeight: FontWeight.bold)), 
          const SizedBox(height: 16), 
          _sCard(total.toString(), "Total Workers", Colors.blue), 
          const SizedBox(height: 8), 
          _sCard(active.toString(), "Active Workers", Colors.green), 
          const SizedBox(height: 8), 
          _sCard(canUpload.toString(), "Have Upload Access", Colors.orange), 
        ]
      )
    );
  }

  Widget _sCard(String c, String l, Color clr) => ListTile(
    leading: Icon(Icons.person, color: clr), 
    title: Text(c, style: const TextStyle(fontWeight: FontWeight.bold)), 
    subtitle: Text(l)
  );
}