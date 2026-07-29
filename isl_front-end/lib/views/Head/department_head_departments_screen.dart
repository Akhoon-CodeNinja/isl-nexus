import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart'; // Added import for charts
import 'package:isl_app/core/services/api_service.dart';
import 'package:isl_app/widgets/Head/department_head_sidebar.dart';
import 'package:isl_app/widgets/Head/department_head_top_header.dart';

// --- DATA MODEL ---
class DepartmentModel {
  final String id;
  final String name;
  final String description;
  final String code;
  final int usersCount;
  final int docsCount;
  final bool isActive;
  final IconData icon;
  final Color iconColor;

  DepartmentModel({
    required this.id,
    required this.name,
    required this.description,
    required this.code,
    required this.usersCount,
    required this.docsCount,
    required this.isActive,
    required this.icon,
    required this.iconColor,
  });
}

// --- MAIN SCREEN ---
class DepartmentHeadDepartmentsScreen extends StatefulWidget {
  const DepartmentHeadDepartmentsScreen({super.key});

  @override
  State<DepartmentHeadDepartmentsScreen> createState() => _DepartmentHeadDepartmentsScreenState();
}

class _DepartmentHeadDepartmentsScreenState extends State<DepartmentHeadDepartmentsScreen> {
  final Color sidebarColor = const Color(0xFF0F294D);
  final Color primaryBlue = const Color(0xFF163E75);
  final Color bgLight = const Color(0xFFF8FAFC);
  final Color borderLight = Colors.grey.shade200;

  final ApiService _apiService = ApiService();

  List<DepartmentModel> departmentsList = [];
  String selectedStatus = 'All Status';
  String selectedSort = 'Newest First';
  bool _loading = true;
  String? _error;
  final TextEditingController _searchCtrl = TextEditingController();

  static const List<IconData> _iconCycle = [
    Icons.factory,
    Icons.security,
    Icons.build,
    Icons.verified,
    Icons.people,
    Icons.domain,
    Icons.shopping_cart,
    Icons.science,
  ];
  static const List<Color> _colorCycle = [
    Color(0xFF2563EB),
    Color(0xFFD97706),
    Color(0xFF9333EA),
    Color(0xFF14B8A6),
    Color(0xFFF97316),
    Color(0xFF6B7280),
    Color(0xFFEF4444),
    Color(0xFF38BDF8),
  ];

  @override
  void initState() {
    super.initState();
    _fetchDepartments();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchDepartments() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await _apiService.fetchDepartmentsRaw();
      var items = raw.asMap().entries.map((entry) {
        final i = entry.key;
        final json = entry.value;
        return DepartmentModel(
          id: (json['id'] ?? '').toString(),
          name: (json['name'] ?? 'Unnamed department').toString(),
          description: (json['description'] ?? '').toString(),
          code: (json['code'] ?? '').toString(),
          usersCount: int.tryParse('${json['users_count'] ?? 0}') ?? 0,
          docsCount: int.tryParse('${json['documents_count'] ?? 0}') ?? 0,
          isActive: json['is_active'] is bool
              ? json['is_active'] as bool
              : true,
          icon: _iconCycle[i % _iconCycle.length],
          iconColor: _colorCycle[i % _colorCycle.length],
        );
      }).toList();

      final query = _searchCtrl.text.trim().toLowerCase();
      if (query.isNotEmpty) {
        items = items
            .where(
              (d) =>
                  d.name.toLowerCase().contains(query) ||
                  d.code.toLowerCase().contains(query),
            )
            .toList();
      }
      if (selectedStatus == 'Active') {
        items = items.where((d) => d.isActive).toList();
      } else if (selectedStatus == 'Inactive') {
        items = items.where((d) => !d.isActive).toList();
      }

      setState(() {
        departmentsList = items;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, color: Colors.red.shade400, size: 32),
          const SizedBox(height: 12),
          Text(
            _error ?? 'Something went wrong.',
            style: const TextStyle(color: Colors.black87),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _fetchDepartments,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgLight,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const DepartmentHeadSidebar(activeItem: "Departments"),
          Expanded(
            child: Column(
              children: [
                const DepartmentHeadTopHeader(
                  title: "Departments",
                  subtitle:
                      "Manage company departments and their document access.",
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
                            BoxShadow(
                              color: Colors.black.withOpacity(0.02),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildToolbar(),
                            const Divider(height: 1),
                            _buildFiltersRow(),
                            const Divider(height: 1),
                            _buildTableHeader(),
                            const Divider(height: 1),
                            Expanded(
                              child: _loading
                                  ? const Center(
                                      child: CircularProgressIndicator(),
                                    )
                                  : _error != null
                                  ? _buildErrorState()
                                  : departmentsList.isEmpty
                                  ? const Center(
                                      child: Text(
                                        'No departments found.',
                                        style: TextStyle(color: Colors.grey),
                                      ),
                                    )
                                  : ListView.separated(
                                      itemCount: departmentsList.length,
                                      separatorBuilder: (context, index) =>
                                          const Divider(height: 1),
                                      itemBuilder: (context, index) =>
                                          _buildTableRow(
                                            departmentsList[index],
                                          ),
                                    ),
                            ),
                            const Divider(height: 1),
                            _buildPaginationFooter(),
                          ],
                        ),
                      );

                      // Narrow window (e.g. sidebar + squeezed browser):
                      // stack the table and the stats panel full-width
                      // instead of squeezing them side-by-side, which is
                      // what caused the table columns to wrap letter-by-
                      // letter.
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
                          _buildRightPanel(),
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

  // ---------------------------------------------------------
  // TABLE & FILTERS
  // ---------------------------------------------------------
  Widget _buildToolbar() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: "Search departments by name or code...",
                hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: borderLight),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
              onSubmitted: (_) => _fetchDepartments(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFiltersRow() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          _buildSmallDropdown(
            "Status",
            selectedStatus,
            ["All Status", "Active", "Inactive"],
            onChanged: (v) {
              setState(() => selectedStatus = v);
              _fetchDepartments();
            },
          ),
          const SizedBox(width: 16),
          _buildSmallDropdown(
            "Sort By",
            selectedSort,
            ["Newest First", "Oldest First"],
            icon: Icons.sort,
            onChanged: (v) {
              setState(() {
                selectedSort = v;
                departmentsList = departmentsList.reversed.toList();
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSmallDropdown(
    String label,
    String value,
    List<String> items, {
    IconData? icon,
    required ValueChanged<String> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: Colors.grey,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          height: 36,
          width: 200,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border.all(color: borderLight),
            borderRadius: BorderRadius.circular(6),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              icon: const Icon(
                Icons.keyboard_arrow_down,
                color: Colors.grey,
                size: 16,
              ),
              items: items
                  .map(
                    (String item) => DropdownMenuItem(
                      value: item,
                      child: Row(
                        children: [
                          if (icon != null) ...[
                            Icon(icon, size: 14, color: Colors.black54),
                            const SizedBox(width: 6),
                          ],
                          Text(
                            item,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black87,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v != null) onChanged(v);
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
          Expanded(flex: 4, child: Text("Department", style: _headerStyle())),
          Expanded(flex: 2, child: Text("Code", style: _headerStyle())),
          Expanded(flex: 2, child: Text("Users", style: _headerStyle())),
          Expanded(flex: 2, child: Text("Documents", style: _headerStyle())),
          Expanded(flex: 2, child: Text("Status", style: _headerStyle())),
        ],
      ),
    );
  }

  TextStyle _headerStyle() => const TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.bold,
    color: Colors.black87,
  );

  Widget _buildTableRow(DepartmentModel dept) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      color: Colors.white,
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: dept.iconColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(dept.icon, color: dept.iconColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        dept.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        dept.description,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              dept.code,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Icon(
                  Icons.person_outline,
                  size: 16,
                  color: Colors.grey.shade600,
                ),
                const SizedBox(width: 6),
                Text(
                  dept.usersCount.toString(),
                  style: const TextStyle(fontSize: 13, color: Colors.black87),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Icon(
                  Icons.description_outlined,
                  size: 16,
                  color: Colors.grey.shade600,
                ),
                const SizedBox(width: 6),
                Text(
                  dept.docsCount.toString(),
                  style: const TextStyle(fontSize: 13, color: Colors.black87),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: dept.isActive ? Colors.green : Colors.grey,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  dept.isActive ? "Active" : "Inactive",
                  style: TextStyle(
                    fontSize: 12,
                    color: dept.isActive
                        ? Colors.green.shade700
                        : Colors.grey.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaginationFooter() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              "Showing 1–${departmentsList.length} of ${departmentsList.length} departments",
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
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
                  _buildPageBox(Icons.chevron_left, isIcon: true),
                  _buildPageBox("1", isActive: true),
                  _buildPageBox(Icons.chevron_right, isIcon: true),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              border: Border.all(color: borderLight),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("10 per page", style: TextStyle(fontSize: 12)),
                SizedBox(width: 8),
                Icon(Icons.keyboard_arrow_down, size: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPageBox(
    dynamic content, {
    bool isActive = false,
    bool isIcon = false,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: isActive ? primaryBlue : Colors.white,
        border: Border.all(color: isActive ? primaryBlue : borderLight),
        borderRadius: BorderRadius.circular(4),
      ),
      alignment: Alignment.center,
      child: isIcon
          ? Icon(content as IconData, size: 16, color: Colors.black87)
          : Text(
              content as String,
              style: TextStyle(
                color: isActive ? Colors.white : Colors.black87,
                fontSize: 12,
              ),
            ),
    );
  }

  // ---------------------------------------------------------
  // RIGHT HAND SIDE PANEL (RHS)
  // ---------------------------------------------------------
  Widget _buildRightPanel() {
    return Container(
      width: 300,
      margin: const EdgeInsets.only(right: 32, bottom: 32),
      child: SingleChildScrollView(
        child: Column(
          children: [
            // Section 1: Overview
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderLight),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.02),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.business, color: primaryBlue, size: 20),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "Department Overview",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  _buildOverviewRow(
                    "Total Departments",
                    departmentsList.length.toString(),
                    Colors.blue.shade700,
                  ),
                  const Divider(),
                  _buildOverviewRow(
                    "Active Departments",
                    departmentsList.where((d) => d.isActive).length.toString(),
                    Colors.green.shade700,
                  ),
                  const Divider(),
                  _buildOverviewRow(
                    "Inactive Departments",
                    departmentsList.where((d) => !d.isActive).length.toString(),
                    Colors.orange.shade700,
                  ),
                  const Divider(),
                  _buildOverviewRow(
                    "Total Users",
                    departmentsList
                        .fold<int>(0, (sum, d) => sum + d.usersCount)
                        .toString(),
                    Colors.indigo.shade700,
                  ),
                  const Divider(),
                  _buildOverviewRow(
                    "Total Documents",
                    departmentsList
                        .fold<int>(0, (sum, d) => sum + d.docsCount)
                        .toString(),
                    Colors.blue.shade700,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Section 2: Bar Chart (Employees by Department)
            _buildBarChartSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewRow(String label, String count, Color countColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            count,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: countColor,
            ),
          ),
        ],
      ),
    );
  }

  // Bar Chart Widget Method
  Widget _buildBarChartSection() {
    double maxY = 10; // Default max Y axis limit
    if (departmentsList.isNotEmpty) {
      final maxUsers = departmentsList
          .map((d) => d.usersCount)
          .reduce((a, b) => a > b ? a : b);
      if (maxUsers > 0) {
        maxY = maxUsers.toDouble() * 1.2; // Add 20% padding to top
      }
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderLight),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Employees by Department",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 32),
          SizedBox(
            height: 200,
            child: departmentsList.isEmpty
                ? const Center(
                    child: Text(
                      "No data available",
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  )
                : BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      maxY: maxY,
                      barTouchData: BarTouchData(
                        enabled: true,
                        touchTooltipData: BarTouchTooltipData(
                          getTooltipItem: (group, groupIndex, rod, rodIndex) {
                            return BarTooltipItem(
                              '${departmentsList[group.x.toInt()].name}\n',
                              const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                              children: <TextSpan>[
                                TextSpan(
                                  text: '${rod.toY.toInt()} Employees',
                                  style: TextStyle(
                                    color: departmentsList[group.x.toInt()]
                                        .iconColor,
                                    fontWeight: FontWeight.w500,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                      titlesData: FlTitlesData(
                        show: true,
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (double value, TitleMeta meta) {
                              final index = value.toInt();
                              if (index < 0 ||
                                  index >= departmentsList.length) {
                                return const SizedBox.shrink();
                              }
                              // Shortening name to prevent text overlap
                              final name = departmentsList[index].name;
                              final shortName = name.length > 8
                                  ? '${name.substring(0, 6)}..'
                                  : name;

                              return Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Text(
                                  shortName,
                                  style: const TextStyle(
                                    fontSize: 9,
                                    color: Colors.black87,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              );
                            },
                            reservedSize: 28,
                          ),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 30,
                            getTitlesWidget: (value, meta) {
                              // Only showing integer values for employees
                              if (value % 1 != 0) {
                                return const SizedBox.shrink();
                              }
                              return Text(
                                value.toInt().toString(),
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.black54,
                                ),
                              );
                            },
                          ),
                        ),
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                      ),
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: maxY > 5
                            ? (maxY / 5).floorToDouble()
                            : 1,
                        getDrawingHorizontalLine: (value) => FlLine(
                          color: borderLight,
                          strokeWidth: 1,
                          dashArray: [4, 4], // Dotted horizontal lines for grid
                        ),
                      ),
                      // FIX APPLIED: Boundaries have been enabled
                      borderData: FlBorderData(
                        show: true,
                        border: Border(
                          bottom: BorderSide(
                            color: borderLight,
                            width: 2,
                          ), // X-Axis Line
                          left: BorderSide(
                            color: borderLight,
                            width: 2,
                          ), // Y-Axis Line
                          top: BorderSide.none,
                          right: BorderSide.none,
                        ),
                      ),
                      barGroups: departmentsList.asMap().entries.map((entry) {
                        final index = entry.key;
                        final dept = entry.value;
                        return BarChartGroupData(
                          x: index,
                          barRods: [
                            BarChartRodData(
                              toY: dept.usersCount.toDouble(),
                              color: dept.iconColor,
                              width: 16,
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(4),
                                topRight: Radius.circular(4),
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}