import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:isl_app/core/services/api_service.dart';
import 'package:isl_app/widgets/Admin/admin_sidebar.dart';
import 'package:isl_app/widgets/Admin/admin_top_header.dart';

// --- DATA MODEL ---
/// Admin screen — browse and filter the system-wide audit log (who did what, on which module, and when) across all departments.
class ActivityModel {
  final String id;
  final String time;
  final String userName;
  final String userInitials;
  final Color userAvatarColor;
  final String action;
  final Color actionColor;
  final Color actionBgColor;
  final String module;
  final String details;
  final String ipAddress;

  ActivityModel({
    required this.id,
    required this.time,
    required this.userName,
    required this.userInitials,
    required this.userAvatarColor,
    required this.action,
    required this.actionColor,
    required this.actionBgColor,
    required this.module,
    required this.details,
    required this.ipAddress,
  });
}

// --- MAIN SCREEN ---
class AdminActivityLogScreen extends StatefulWidget {
  const AdminActivityLogScreen({super.key});

  @override
  State<AdminActivityLogScreen> createState() => _AdminActivityLogScreenState();
}

class _AdminActivityLogScreenState extends State<AdminActivityLogScreen> {
  final Color sidebarColor = const Color(0xFF0F294D);
  final Color primaryBlue = const Color(0xFF163E75);
  final Color bgLight = const Color(0xFFF8FAFC);
  final Color borderLight = Colors.grey.shade200;

  final ApiService _apiService = ApiService();

  List<ActivityModel> activitiesList = [];
  bool _loading = true;
  String? _error; // THIS WAS THE ERROR VARIABLE DISPLAYED IN ORANGE
  int _currentPage = 1;
  int _totalCount = 0;
  bool _hasNext = false;
  bool _hasPrevious = false;
  final TextEditingController _searchCtrl = TextEditingController();

  // DYNAMIC FILTERS DATA — all three lists are now populated from the
  // backend (see _fetchDropdownData) instead of being hard-coded, so any
  // new action/module type added later shows up automatically.
  List<String> _userDropdownItems = ['All Users'];
  List<String> _actionDropdownItems = ['All Actions'];
  List<String> _moduleDropdownItems = ['All Modules'];

  String selectedUser = 'All Users';
  String selectedAction = 'All Actions';
  String selectedModule = 'All Modules';

  // Real date-range filter (replaces the old static "All Time" label)
  DateTimeRange? selectedDateRange;

  // Dynamic RHS Stats
  int _docsCount = 0;
  int _usersCount = 0;
  int _systemCount = 0;

  @override
  void initState() {
    super.initState();
    _fetchDropdownData();
    _fetchActivities();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // --- FETCH USERS + DISTINCT ACTIONS + DISTINCT MODULES FROM API ---
  Future<void> _fetchDropdownData() async {
    // Users dropdown
    try {
      final usersRaw = await _apiService.fetchUsersRaw();
      final List<String> fetchedUsers = ['All Users'];

      for (var u in usersRaw) {
        final name = u['full_name']?.toString() ?? '';
        if (name.isNotEmpty && !fetchedUsers.contains(name)) {
          fetchedUsers.add(name);
        }
      }

      if (mounted) {
        setState(() {
          _userDropdownItems = fetchedUsers;
          if (!_userDropdownItems.contains(selectedUser)) {
            selectedUser = 'All Users';
          }
        });
      }
    } catch (e) {
      debugPrint("Could not load users for dropdown: $e");
    }

    // Actions dropdown — pulled from real AuditLog data instead of a
    // hard-coded list, so it always matches what's actually stored.
    try {
      final actionsRaw = await _apiService.fetchDistinctActivityValues(field: 'action');
      final List<String> fetchedActions = ['All Actions'];
      for (var a in actionsRaw) {
        final value = a.toString();
        if (value.isNotEmpty && !fetchedActions.contains(value)) {
          fetchedActions.add(value);
        }
      }
      if (mounted) {
        setState(() {
          _actionDropdownItems = fetchedActions;
          if (!_actionDropdownItems.contains(selectedAction)) {
            selectedAction = 'All Actions';
          }
        });
      }
    } catch (e) {
      debugPrint("Could not load actions for dropdown: $e");
    }

    // Modules dropdown — pulled from real AuditLog `entity_type` values.
    try {
      final modulesRaw = await _apiService.fetchDistinctActivityValues(field: 'module');
      final List<String> fetchedModules = ['All Modules'];
      for (var m in modulesRaw) {
        final value = m.toString();
        if (value.isNotEmpty && !fetchedModules.contains(value)) {
          fetchedModules.add(value);
        }
      }
      if (mounted) {
        setState(() {
          _moduleDropdownItems = fetchedModules;
          if (!_moduleDropdownItems.contains(selectedModule)) {
            selectedModule = 'All Modules';
          }
        });
      }
    } catch (e) {
      debugPrint("Could not load modules for dropdown: $e");
    }
  }

  /// Cosmetic-only color coding derived from the action text
  ({Color bg, Color fg}) _colorsForAction(String action) {
    final a = action.toLowerCase();
    if (a.contains('delet') || a.contains('deactivat')) {
      return (bg: Colors.red.shade50, fg: Colors.red.shade700);
    }
    if (a.contains('upload') || a.contains('creat') || a.contains('activat')) {
      return (bg: Colors.green.shade50, fg: Colors.green.shade700);
    }
    if (a.contains('updat') || a.contains('edit')) {
      return (bg: Colors.blue.shade50, fg: Colors.blue.shade700);
    }
    if (a.contains('login') || a.contains('logout')) {
      return (bg: Colors.grey.shade100, fg: Colors.grey.shade700);
    }
    return (bg: Colors.blue.shade50, fg: Colors.blue.shade700);
  }

  static const List<Color> _avatarColorCycle = [
    Color(0xFF163E75),
    Color(0xFF14B8A6),
    Color(0xFFA78BFA),
    Color(0xFFFB923C),
    Color(0xFF4ADE80),
  ];

  String _initialsFor(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  Future<void> _fetchActivities({int? page}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final targetPage = page ?? _currentPage;
      
      final raw = await _apiService.fetchActivityLogsRaw(
        page: targetPage,
        search: _searchCtrl.text.trim(),
        user: selectedUser == 'All Users' ? '' : selectedUser,
        action: selectedAction == 'All Actions' ? '' : selectedAction,
        module: selectedModule == 'All Modules' ? '' : selectedModule,
        startDate: selectedDateRange?.start,
        // Include the full end day (23:59:59) so the day the user picked
        // as "end" is not excluded from the results.
        endDate: selectedDateRange == null
            ? null
            : DateTime(
                selectedDateRange!.end.year,
                selectedDateRange!.end.month,
                selectedDateRange!.end.day,
                23, 59, 59,
              ),
      );
      
      // Handle cases where the backend sends a direct array (without the 'results' key)
      List<dynamic> results = [];
      if (raw.containsKey('results') && raw['results'] is List) {
        results = raw['results'] as List<dynamic>;
      } else if (raw.containsKey('data') && raw['data'] is List) {
        results = raw['data'] as List<dynamic>;
      }

      final items = results.asMap().entries.map((entry) {
        final i = entry.key;
        final json = entry.value as Map<String, dynamic>;
        
        // Handle nested user_details or direct user name
        String userName = 'Unknown user';
        if (json['user_details'] is Map && json['user_details']['full_name'] != null) {
          userName = json['user_details']['full_name'].toString();
        } else if (json['user'] != null) {
          userName = json['user'].toString();
        }

        final action = (json['action'] ?? '').toString();
        final colors = _colorsForAction(action);
        
        return ActivityModel(
          id: (json['id'] ?? '').toString(),
          time: (json['created_at'] ?? '').toString(),
          userName: userName,
          userInitials: _initialsFor(userName),
          userAvatarColor: _avatarColorCycle[i % _avatarColorCycle.length],
          action: action,
          actionColor: colors.fg,
          actionBgColor: colors.bg,
          module: (json['module'] ?? 'General').toString(),
          details: (json['details'] ?? '').toString(),
          ipAddress: (json['ip_address'] ?? '—').toString(),
        );
      }).toList();

      // DYNAMIC STATS CALCULATION
      int tempDocs = 0;
      int tempUsers = 0;
      int tempSystem = 0;
      
      for (var item in items) {
        if (item.module.toLowerCase().contains('document')) {
          tempDocs++;
        } else if (item.module.toLowerCase().contains('user') || item.module.toLowerCase().contains('auth')) {
          tempUsers++;
        } else {
          tempSystem++;
        }
      }

      setState(() {
        activitiesList = items;
        _currentPage = targetPage;
        
        // If count is directly available
        if (raw.containsKey('count') && raw['count'] is int) {
           _totalCount = raw['count'] as int;
        } else {
           _totalCount = results.length;
        }

        _hasNext = raw['next'] != null;
        _hasPrevious = raw['previous'] != null;
        
        _docsCount = tempDocs;
        _usersCount = tempUsers;
        _systemCount = tempSystem;
        
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = friendlyApiError(e); // API error capture
        _loading = false;
      });
    }
  }

  void _goToNextPage() {
    if (_hasNext) _fetchActivities(page: _currentPage + 1);
  }

  void _goToPreviousPage() {
    if (_hasPrevious && _currentPage > 1) {
      _fetchActivities(page: _currentPage - 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgLight,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AdminSidebar(activeItem: "Activity Log"),
          Expanded(
            child: Column(
              children: [
                const AdminTopHeader(
                  title: "Activity Log",
                  subtitle: "Track all system activities and user actions.",
                ),
                Expanded(
                  // LayoutBuilder decides between the side-by-side desktop
                  // layout and a stacked mobile/narrow layout. Forcing the
                  // table (flex 3) and the stats panel (flex 1) into one
                  // Row at any width is what squeezed the table's inner
                  // Rows below their minimum content width and produced
                  // the small overflow markers in the screenshot.
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isNarrow = constraints.maxWidth < 980;

                      // Builds the row list. `bounded=true` (desktop) means
                      // this sits inside an Expanded with a real height from
                      // the Scaffold, so a normal scrolling ListView is
                      // correct. `bounded=false` (narrow/stacked layout)
                      // means the whole page scrolls instead (see below),
                      // so the list must size itself to its content —
                      // shrinkWrap + NeverScrollableScrollPhysics does that.
                      // This replaces the old fixed-height SizedBoxes
                      // (480 / 560), which is what actually broke: the
                      // moment the filters row above grew taller (wrapping
                      // onto multiple lines), those guessed numbers no
                      // longer left enough room and the Column overflowed.
                      Widget buildRows({required bool bounded}) {
                        if (_loading) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        if (_error != null) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24.0),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                                  const SizedBox(height: 16),
                                  Text(
                                    "Backend Integration Error:\n$_error",
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(color: Colors.red, fontSize: 14),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }
                        if (activitiesList.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.history, size: 48, color: Colors.grey.shade300),
                                const SizedBox(height: 16),
                                const Text("No activities found.", style: TextStyle(color: Colors.grey, fontSize: 16)),
                              ],
                            ),
                          );
                        }
                        return ListView.separated(
                          shrinkWrap: !bounded,
                          physics: bounded ? null : const NeverScrollableScrollPhysics(),
                          itemCount: activitiesList.length,
                          separatorBuilder: (context, index) => const Divider(height: 1),
                          itemBuilder: (context, index) => _buildTableRow(activitiesList[index]),
                        );
                      }

                      // Wraps header+rows so the table can scroll
                      // horizontally once it's narrower than its natural
                      // minimum (720px), instead of squashing every
                      // column's text down to the point of overflow. Width
                      // is taken from a LayoutBuilder measured right here
                      // (the table's *actual* available width) rather than
                      // guessed from the outer screen width.
                      Widget buildTableBody({required bool bounded}) {
                        return LayoutBuilder(
                          builder: (context, inner) {
                            final w = inner.maxWidth < 720 ? 720.0 : inner.maxWidth;
                            final core = SizedBox(
                              width: w,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _buildTableHeader(),
                                  const Divider(height: 1),
                                  bounded ? Expanded(child: buildRows(bounded: true)) : buildRows(bounded: false),
                                ],
                              ),
                            );
                            return SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: core,
                            );
                          },
                        );
                      }

                      final table = Container(
                        margin: EdgeInsets.only(left: 32, bottom: 32, right: isNarrow ? 32 : 16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: borderLight),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildToolbar(),
                            const Divider(height: 1),
                            _buildFiltersRow(),
                            const Divider(height: 1),
                            isNarrow
                                ? buildTableBody(bounded: false)
                                : Expanded(child: buildTableBody(bounded: true)),
                            const Divider(height: 1),
                            _buildPaginationFooter(),
                          ],
                        ),
                      );

                      final rightPanel = _buildRightPanel();

                      if (isNarrow) {
                        // Stack vertically and let the whole page scroll.
                        // Neither the table nor the stats panel is forced
                        // into a fixed height anymore, so there's nothing
                        // left to overflow regardless of how tall the
                        // filters row or the row list end up being.
                        return SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              table,
                              rightPanel,
                            ],
                          ),
                        );
                      }

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 3, child: table),
                          Expanded(flex: 1, child: rightPanel),
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
              decoration: InputDecoration(
                hintText: "Search activities by user, action, or document...",
                hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: borderLight)),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
              onSubmitted: (_) => _fetchActivities(page: 1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFiltersRow() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      // LayoutBuilder + Wrap instead of a plain Row: a Row of 4 Expanded
      // filters has nowhere to shrink to once the window gets narrow,
      // which is exactly what produced the 1.5px overflow in the
      // screenshot. Wrap lets filters fall onto a second line instead of
      // overflowing, and on wide screens it still lays out as one row.
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 700;
          final itemWidth = isNarrow
              ? constraints.maxWidth
              : (constraints.maxWidth - 16 * 3) / 4;

          return Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              SizedBox(width: itemWidth, child: _buildSmallDropdown("User", selectedUser, _userDropdownItems)),
              SizedBox(width: itemWidth, child: _buildSmallDropdown("Action", selectedAction, _actionDropdownItems)),
              SizedBox(width: itemWidth, child: _buildSmallDropdown("Module", selectedModule, _moduleDropdownItems)),
              SizedBox(width: itemWidth, child: _buildDateRangePicker()),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDateRangePicker() {
    final label = selectedDateRange == null
        ? "All Time"
        : "${_formatDate(selectedDateRange!.start)} – ${_formatDate(selectedDateRange!.end)}";

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Date Range", style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: _pickDateRange,
          child: Container(
            height: 36, padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(border: Border.all(color: borderLight), borderRadius: BorderRadius.circular(6), color: Colors.grey.shade50),
            child: Row(
              children: [
                const Icon(Icons.calendar_today_outlined, size: 14, color: Colors.black54),
                const SizedBox(width: 8),
                Expanded(child: Text(label, style: const TextStyle(fontSize: 12, color: Colors.black87, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis)),
                if (selectedDateRange != null)
                  GestureDetector(
                    onTap: () {
                      setState(() => selectedDateRange = null);
                      _fetchActivities(page: 1);
                    },
                    child: const Icon(Icons.close, size: 14, color: Colors.black45),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime d) => "${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}";

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: now,
      initialDateRange: selectedDateRange,
      helpText: "Select date range",
    );
    if (picked != null) {
      setState(() => selectedDateRange = picked);
      _fetchActivities(page: 1);
    }
  }

  Widget _buildSmallDropdown(String label, String value, List<String> items) {
    if (!items.contains(value)) {
      value = items.first; 
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Container(
          height: 36, padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(border: Border.all(color: borderLight), borderRadius: BorderRadius.circular(6)),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              icon: const Icon(Icons.keyboard_arrow_down, color: Colors.grey, size: 16),
              items: items.map<DropdownMenuItem<String>>((String item) {
                return DropdownMenuItem<String>(
                  value: item, 
                  child: Text(item, style: const TextStyle(fontSize: 12, color: Colors.black87, fontWeight: FontWeight.w500))
                );
              }).toList(),
              onChanged: (v) { 
                if (v != null) {
                  setState(() { 
                    if(label == "User") selectedUser = v;
                    if(label == "Action") selectedAction = v;
                    if(label == "Module") selectedModule = v;
                    _fetchActivities(page: 1); 
                  }); 
                } 
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      color: Colors.grey.shade50,
      child: Row(
        children: [
          Expanded(flex: 2, child: Text("Time", style: _headerStyle())),
          Expanded(flex: 2, child: Text("User", style: _headerStyle())),
          Expanded(flex: 2, child: Text("Action", style: _headerStyle())),
          Expanded(flex: 2, child: Text("Module", style: _headerStyle())),
          Expanded(flex: 3, child: Text("Details", style: _headerStyle())),
          Expanded(flex: 2, child: Text("IP Address", style: _headerStyle())),
          const SizedBox(width: 24),
        ],
      ),
    );
  }

  TextStyle _headerStyle() => const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87);

  Future<void> _copyToClipboard(String value, {required String label}) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copied to clipboard.')),
    );
  }

  void _showActivityDetails(ActivityModel activity) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Activity Details'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _detailRow('What Action', activity.action),
              _detailRow('On Which', '${activity.module} — ${activity.details}'),
              _detailRow('On Which Account', activity.userName),
              _detailRow('Time', activity.time),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          SelectableText(
            value.isEmpty ? '—' : value,
            style: const TextStyle(fontSize: 13, color: Colors.black87),
          ),
        ],
      ),
    );
  }

  Widget _buildTableRow(ActivityModel activity) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      color: Colors.white,
      child: Row(
        children: [
          Expanded(flex: 2, child: Text(activity.time, style: const TextStyle(fontSize: 12, color: Colors.black87), overflow: TextOverflow.ellipsis)),
          Expanded(
            flex: 2,
            child: Row(
              children: [
                CircleAvatar(radius: 12, backgroundColor: activity.userAvatarColor, child: Text(activity.userInitials, style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold))),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    activity.userName,
                    style: const TextStyle(fontSize: 12, color: Colors.black87),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Tooltip(
                message: "Show everyone who did this",
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    setState(() {
                      selectedAction = activity.action;
                      if (!_actionDropdownItems.contains(selectedAction)) {
                        _actionDropdownItems = [..._actionDropdownItems, selectedAction];
                      }
                    });
                    _fetchActivities(page: 1);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: activity.actionBgColor, borderRadius: BorderRadius.circular(12)),
                    child: Text(
                      activity.action,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: activity.actionColor, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(flex: 2, child: Text(activity.module, style: const TextStyle(fontSize: 12, color: Colors.black87), overflow: TextOverflow.ellipsis)),
          Expanded(
            flex: 3,
            child: Row(
              children: [
                if (activity.module.toLowerCase().contains('document')) const Icon(Icons.description_outlined, size: 14, color: Colors.grey),
                if (activity.module.toLowerCase().contains('document')) const SizedBox(width: 6),
                Expanded(child: Text(activity.details, style: const TextStyle(fontSize: 12, color: Colors.black87), overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
          Expanded(flex: 2, child: Text(activity.ipAddress, style: const TextStyle(fontSize: 12, color: Colors.black87), overflow: TextOverflow.ellipsis)),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 18, color: Colors.grey),
            padding: EdgeInsets.zero,
            onSelected: (value) {
              if (value == 'view_details') {
                _showActivityDetails(activity);
              } else if (value == 'copy_ip') {
                _copyToClipboard(activity.ipAddress, label: 'IP address');
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'view_details', child: Text('View Full Details')),
              PopupMenuItem(value: 'copy_ip', child: Text('Copy IP Address')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPaginationFooter() {
    if (_totalCount == 0 && _error == null) return const SizedBox.shrink();

    int itemsPerPage = 10; 
    int totalPages = (_totalCount / itemsPerPage).ceil();
    if (totalPages == 0) totalPages = 1;

    int startIndex = ((_currentPage - 1) * itemsPerPage) + 1;
    int endIndex = startIndex + activitiesList.length - 1;

    final summaryText = Text(
      "Showing $startIndex–$endIndex of $_totalCount activities",
      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
      overflow: TextOverflow.ellipsis,
    );

    // A page-number list generated in a loop has unbounded width — with
    // enough pages (or a narrow window) it has nowhere to go and
    // overflows, same as the fixed-width toolbar controls did on the
    // Users screen. Scrolling horizontally keeps it safe at any size.
    final pageControls = SizedBox(
      height: 32,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            GestureDetector(
              onTap: _hasPrevious ? _goToPreviousPage : null,
              child: _buildPageBox(Icons.chevron_left, isIcon: true, disabled: !_hasPrevious)
            ),
            for (int i = 1; i <= totalPages; i++)
              GestureDetector(
                onTap: () => _currentPage != i ? _fetchActivities(page: i) : null,
                child: _buildPageBox(i.toString(), isActive: _currentPage == i)
              ),
            GestureDetector(
              onTap: _hasNext ? _goToNextPage : null,
              child: _buildPageBox(Icons.chevron_right, isIcon: true, disabled: !_hasNext)
            ),
          ],
        ),
      ),
    );

    final perPageBox = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(border: Border.all(color: borderLight), borderRadius: BorderRadius.circular(6)),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [Text("10 per page", style: TextStyle(fontSize: 12)), SizedBox(width: 8), Icon(Icons.keyboard_arrow_down, size: 16)],
      ),
    );

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 640;

          if (isNarrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                summaryText,
                const SizedBox(height: 12),
                pageControls,
                const SizedBox(height: 12),
                Align(alignment: Alignment.centerRight, child: perPageBox),
              ],
            );
          }

          return Row(
            children: [
              Flexible(child: summaryText),
              const SizedBox(width: 12),
              Flexible(child: pageControls),
              const SizedBox(width: 12),
              perPageBox,
            ],
          );
        },
      ),
    );
  }

  Widget _buildPageBox(dynamic content, {bool isActive = false, bool isIcon = false, bool disabled = false}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      width: 28, height: 28,
      decoration: BoxDecoration(
        color: isActive ? primaryBlue : (disabled ? Colors.grey.shade100 : Colors.white), 
        border: Border.all(color: isActive ? primaryBlue : borderLight), 
        borderRadius: BorderRadius.circular(4)
      ),
      alignment: Alignment.center,
      child: isIcon 
          ? Icon(content as IconData, size: 16, color: disabled ? Colors.grey.shade400 : Colors.black87) 
          : Text(content as String, style: TextStyle(color: isActive ? Colors.white : Colors.black87, fontSize: 12)),
    );
  }

  Widget _buildRightPanel() {
    return Container(
      margin: const EdgeInsets.only(right: 32, bottom: 32),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: borderLight), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))]),
      // SingleChildScrollView is the fix for the "BOTTOM OVERFLOWED BY 229
      // PIXELS" error in the screenshot: that Column of stat cards has a
      // fixed intrinsic height, and when the browser window gets short
      // there simply isn't enough vertical room for it inside the
      // Container. Scrolling — rather than clipping/overflowing — lets
      // the panel adapt to any window size.
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Activity Overview", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 24),
            _buildStatCard("$_totalCount", "Total Activities", Icons.description_outlined, Colors.blue),
            const SizedBox(height: 16),
            _buildStatCard("$_docsCount", "Document Activities (Page)", Icons.insert_drive_file_outlined, Colors.green),
            const SizedBox(height: 16),
            _buildStatCard("$_usersCount", "User Activities (Page)", Icons.people_outline, Colors.orange),
            const SizedBox(height: 16),
            _buildStatCard("$_systemCount", "System Activities (Page)", Icons.security_outlined, Colors.purple),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String count, String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(border: Border.all(color: borderLight), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(count, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87)),
                Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          )
        ],
      ),
    );
  }
}