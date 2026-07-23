import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fl_chart/fl_chart.dart'; 

// API Service lazmi import karein
import 'package:isl_app/core/services/api_service.dart';

import 'package:isl_app/views/admin/admin_documents_screen.dart';
import 'package:isl_app/views/admin/admin_departments_screen.dart';
import 'package:isl_app/views/admin/admin_activity_log_screen.dart';
import 'package:isl_app/views/admin/admin_users_screen.dart';

import 'package:isl_app/widgets/admin/admin_sidebar.dart';
import 'package:isl_app/widgets/admin/admin_top_header.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final Color primaryBlue = const Color(0xFF163E75);
  final Color bgLight = const Color(0xFFF8FAFC);
  final Color borderLight = Colors.grey.shade200;

  final ApiService _apiService = ApiService();

  String _fullName = "Loading...";
  
  // Bar Chart Data
  List<Map<String, dynamic>> _chartData = [];
  bool _loadingChart = true;

  // Real Data Variables for Dashboard Cards
  int _totalDocs = 0, _activeDocs = 0, _inactiveDocs = 0, _pdfDocs = 0;
  int _totalDepts = 0, _activeDepts = 0, _inactiveDepts = 0;
  int _totalUsers = 0, _activeUsers = 0, _inactiveUsers = 0, _deptHeadUsers = 0, _workerUsers = 0;
  int _totalActivities = 0, _docActivities = 0, _userActivities = 0, _systemActivities = 0;
  bool _isLoadingStats = true;

  // Chart bars ke liye colors
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
    _loadUserData();
    _fetchDashboardData(); 
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('name');

    if (mounted) {
      setState(() {
        _fullName = (name != null && name.isNotEmpty) ? name : "Admin";
      });
    }
  }

  // Parallel API requests run karne ke liye naya function
  Future<void> _fetchDashboardData() async {
    setState(() {
      _loadingChart = true;
      _isLoadingStats = true;
    });

    // Dono functions ek sath parallel chalenge taake fast load ho
    await Future.wait([
      _fetchChartData(),
      _fetchAllDashboardStats(),
    ]);

    if (mounted) {
      setState(() {
        _loadingChart = false;
        _isLoadingStats = false;
      });
    }
  }

  // API se Real Stats (Cards ke liye)
  Future<void> _fetchAllDashboardStats() async {
    try {
      // 1. Documents Stats Fetching
      final docs = await _apiService.fetchDocuments();
      int tDocs = docs.length;
      int aDocs = docs.where((d) => d.isActive).length;
      int pdf = docs.where((d) => d.type.toUpperCase().contains('PDF')).length;

      // 2. Departments Stats Fetching
      final depts = await _apiService.fetchDepartmentsRaw();
      int tDepts = depts.length;
      int aDepts = depts.where((d) {
        final active = d['is_active'];
        return active is bool ? active : true;
      }).length;

      // 3. Users Stats Fetching
      final users = await _apiService.fetchUsersRaw();
      int tUsers = users.length;
      int aUsers = users.where((u) {
        final active = u['is_active'];
        return active is bool ? active : true;
      }).length;
      int dHeads = users.where((u) => (u['role'] ?? '').toString() == 'DEPARTMENT_HEAD').length;

      // 4. Activity Logs Stats Fetching
      final activityRaw = await _apiService.fetchActivityLogsRaw(page: 1);
      int tActivities = 0;
      List<dynamic> actResults = [];
      
      // Kyunke activityRaw hamesha Map hota hai, hum direct keys check karenge
      if (activityRaw.containsKey('count')) {
        tActivities = int.tryParse(activityRaw['count'].toString()) ?? 0;
      }
      
      if (activityRaw.containsKey('results') && activityRaw['results'] is List) {
        actResults = activityRaw['results'] as List<dynamic>;
      } else if (activityRaw.containsKey('data') && activityRaw['data'] is List) {
        actResults = activityRaw['data'] as List<dynamic>;
      }

      // First Page Breakdown Extrapolation
      int tempDocs = 0, tempUsers = 0, tempSystem = 0;
      for (var item in actResults) {
        String mod = (item['entity_type'] ?? item['module'] ?? '').toString().toLowerCase();
        if (mod.contains('document')) tempDocs++;
        else if (mod.contains('user') || mod.contains('auth')) tempUsers++;
        else tempSystem++;
      }

      if (mounted) {
        setState(() {
          _totalDocs = tDocs;
          _activeDocs = aDocs;
          _inactiveDocs = tDocs - aDocs;
          _pdfDocs = pdf;

          _totalDepts = tDepts;
          _activeDepts = aDepts;
          _inactiveDepts = tDepts - aDepts;

          _totalUsers = tUsers;
          _activeUsers = aUsers;
          _inactiveUsers = tUsers - aUsers;
          _deptHeadUsers = dHeads;
          _workerUsers = tUsers - dHeads;

          _totalActivities = tActivities;
          _docActivities = tempDocs;
          _userActivities = tempUsers;
          _systemActivities = tempSystem;
        });
      }
    } catch (e) {
      debugPrint("Error fetching dashboard stats: $e");
    }
  }

  // Yahan API se real data fetch ho raha hai Bar chart ke liye
  Future<void> _fetchChartData() async {
    try {
      final rawData = await _apiService.fetchDepartmentsRaw();
      final List<Map<String, dynamic>> loadedData = [];
      
      for (int i = 0; i < rawData.length; i++) {
        final json = rawData[i];
        loadedData.add({
          'name': (json['name'] ?? 'Unnamed').toString(),
          'users': int.tryParse('${json['users_count'] ?? 0}') ?? 0,
          'color': _colorCycle[i % _colorCycle.length],
        });
      }
      
      if (mounted) {
        setState(() {
          _chartData = loadedData;
        });
      }
    } catch (e) {
      debugPrint("Error loading chart data: $e");
    }
  }

  void _navigateTo(Widget screen) {
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => screen,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
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
          const AdminSidebar(activeItem: "Dashboard"),
          Expanded(
            child: Column(
              children: [
                AdminTopHeader(
                  title: "Dashboard",
                  subtitle: "Welcome back, $_fullName! Here's what's happening at ISL.",
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(left: 32, bottom: 32, right: 32, top: 8),
                    child: Column(
                      children: [
                        // --- MAIN GRID (3 columns) ---
                        IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: Column(
                                  children: [
                                    _buildAnimatedCard(
                                      index: 0,
                                      child: _buildUploadsOverview(),
                                      onTap: () => _navigateTo(const AdminDocumentsScreen()),
                                    ),
                                    const SizedBox(height: 24),
                                    _buildAnimatedCard(
                                      index: 3,
                                      child: _buildActivityOverview(),
                                      onTap: () => _navigateTo(const AdminActivityLogScreen()),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 24),
                              Expanded(
                                child: Column(
                                  children: [
                                    _buildAnimatedCard(
                                      index: 1,
                                      child: _buildAIKnowledgeBase(),
                                      onTap: () => _navigateTo(const AdminDocumentsScreen()),
                                    ),
                                    const SizedBox(height: 24),
                                    _buildAnimatedCard(
                                      index: 4,
                                      child: _buildUserOverview(),
                                      onTap: () => _navigateTo(const AdminUsersScreen()),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 24),
                              Expanded(
                                child: _buildAnimatedCard(
                                  index: 2,
                                  child: _buildDepartmentOverview(),
                                  onTap: () => _navigateTo(const AdminDepartmentsScreen()),
                                ),
                              ),
                            ],
                          ),
                        ),
                        
                        const SizedBox(height: 24),
                        
                        // --- BOTTOM CHART SECTION (Full Width) ---
                        Row(
                          children: [
                            Expanded(
                              child: _buildAnimatedCard(
                                index: 5,
                                child: _buildEmployeesBarChart(),
                                onTap: () => _navigateTo(const AdminDepartmentsScreen()),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // =======================================================================
  // ANIMATION & CARD WRAPPER
  // =======================================================================
  Widget _buildAnimatedCard({required int index, required Widget child, required VoidCallback onTap}) {
    return TweenAnimationBuilder(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: 400 + (index * 150)),
      curve: Curves.easeOutCubic,
      builder: (context, double value, widget) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 30 * (1 - value)),
            child: widget,
          ),
        );
      },
      child: Material(
        color: Colors.transparent,
        child: _HoverScale(
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            hoverColor: Colors.blue.withOpacity(0.02),
            child: Container(
              padding: const EdgeInsets.all(20), 
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderLight),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4)),
                ],
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  // =======================================================================
  // EMPLOYEES BAR CHART (API BASED)
  // =======================================================================
  Widget _buildEmployeesBarChart() {
    double maxY = 10;
    if (_chartData.isNotEmpty) {
      final maxUsers = _chartData.map((d) => d['users'] as int).reduce((a, b) => a > b ? a : b);
      if (maxUsers > 0) maxY = maxUsers.toDouble() * 1.2;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          "Employees by Department",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: 240, 
          child: _loadingChart 
              ? const Center(child: CircularProgressIndicator()) 
              : _chartData.isEmpty
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
                                '${_chartData[group.x.toInt()]['name']}\n',
                                const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                children: <TextSpan>[
                                  TextSpan(
                                    text: '${rod.toY.toInt()} Employees',
                                    style: TextStyle(
                                      color: _chartData[group.x.toInt()]['color'],
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
                                if (index < 0 || index >= _chartData.length) return const SizedBox.shrink();
                                
                                final name = _chartData[index]['name'] as String;
                                final shortName = name.length > 10 ? '${name.substring(0, 8)}..' : name;
                                
                                return Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: Text(
                                    shortName,
                                    style: const TextStyle(fontSize: 11, color: Colors.black87),
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
                                if (value % 1 != 0) return const SizedBox.shrink();
                                return Text(
                                  value.toInt().toString(),
                                  style: const TextStyle(fontSize: 11, color: Colors.black54),
                                );
                              },
                            ),
                          ),
                          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        ),
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          horizontalInterval: maxY > 5 ? (maxY / 5).floorToDouble() : 1,
                          getDrawingHorizontalLine: (value) => FlLine(
                            color: borderLight,
                            strokeWidth: 1,
                            dashArray: [4, 4], 
                          ),
                        ),
                        borderData: FlBorderData(
                          show: true,
                          border: Border(
                            bottom: BorderSide(color: borderLight, width: 2), 
                            left: BorderSide(color: borderLight, width: 2),
                            top: BorderSide.none,
                            right: BorderSide.none,
                          ),
                        ),
                        barGroups: _chartData.asMap().entries.map((entry) {
                          final index = entry.key;
                          final data = entry.value;
                          return BarChartGroupData(
                            x: index,
                            barRods: [
                              BarChartRodData(
                                toY: (data['users'] as int).toDouble(),
                                color: data['color'] as Color,
                                width: 24, 
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
    );
  }

  // =======================================================================
  // CARD 1: UPLOADS OVERVIEW
  // =======================================================================
  Widget _buildUploadsOverview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min, 
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.insert_drive_file, color: Colors.blue, size: 20),
            ),
            const SizedBox(width: 12),
            const Text("Uploads Overview", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          ],
        ),
        const SizedBox(height: 16),
        _buildRowItem("Total Uploaded", _totalDocs.toString(), Colors.blue.shade700),
        const Divider(height: 16),
        _buildRowItem("Active Documents", _activeDocs.toString(), Colors.green.shade700),
        const Divider(height: 16),
        _buildRowItem("Inactive Documents", _inactiveDocs.toString(), Colors.orange.shade700),
        const Divider(height: 16),
        _buildRowItem("PDF Files", _pdfDocs.toString(), Colors.red.shade700),
        const SizedBox(height: 16),
        const Text("By File Type", style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        SizedBox(
          height: 120, 
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 35,
              sections: _totalDocs == 0
                  ? [
                      PieChartSectionData(
                        color: Colors.grey.shade200,
                        value: 100,
                        title: '',
                        radius: 30,
                      )
                    ]
                  : [
                      if (_pdfDocs > 0)
                        PieChartSectionData(
                          color: Colors.red.shade400,
                          value: _pdfDocs.toDouble(),
                          title: 'PDF',
                          radius: 30,
                          titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      if ((_totalDocs - _pdfDocs) > 0)
                        PieChartSectionData(
                          color: Colors.blue.shade400,
                          value: (_totalDocs - _pdfDocs).toDouble(),
                          title: 'Other',
                          radius: 30,
                          titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                    ],
            ),
          ),
        ),
      ],
    );
  }

  // =======================================================================
  // CARD 2: AI KNOWLEDGE BASE
  // =======================================================================
  Widget _buildAIKnowledgeBase() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(Icons.psychology_outlined, color: primaryBlue, size: 24),
            const SizedBox(width: 12),
            const Text("AI Knowledge Base", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          ],
        ),
        const SizedBox(height: 16),
        const Text("Sync Status", style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Row(
          children: [
            const _PulsingDot(color: Colors.green, size: 10),
            const SizedBox(width: 8),
            const Text("Synced", style: TextStyle(fontSize: 13, color: Colors.black87, fontWeight: FontWeight.w500)),
          ],
        ),
        const SizedBox(height: 16),
        _buildBoxStat(_totalDocs.toString(), "Total Documents", Icons.description_outlined, Colors.blue),
        const SizedBox(height: 12),
        _buildBoxStat(_activeDocs.toString(), "Active Documents", Icons.check_circle_outline, Colors.green),
        const SizedBox(height: 12),
        _buildBoxStat(_inactiveDocs.toString(), "Inactive Documents", Icons.pause_circle_outline, Colors.orange),
        const SizedBox(height: 16),
        const Text("Last Sync", style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        const Row(
          children: [
            Icon(Icons.access_time, size: 14, color: Colors.black54),
            SizedBox(width: 8),
            Text("Just now", style: TextStyle(fontSize: 12, color: Colors.black87)),
          ],
        ),
      ],
    );
  }

  // =======================================================================
  // CARD 3: DEPARTMENT OVERVIEW
  // =======================================================================
  Widget _buildDepartmentOverview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
              child: Icon(Icons.business, color: primaryBlue, size: 20),
            ),
            const SizedBox(width: 12),
            const Text("Department Overview", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          ],
        ),
        const SizedBox(height: 16),
        _buildRowItem("Total Departments", _totalDepts.toString(), Colors.blue.shade700),
        const Divider(height: 20),
        _buildRowItem("Active Departments", _activeDepts.toString(), Colors.green.shade700),
        const Divider(height: 20),
        _buildRowItem("Inactive Departments", _inactiveDepts.toString(), Colors.orange.shade700),
        const Divider(height: 20),
        _buildRowItem("Total Users", _totalUsers.toString(), Colors.indigo.shade700),
        const Divider(height: 20),
        _buildRowItem("Total Documents", _totalDocs.toString(), Colors.blue.shade700),
      ],
    );
  }

  // =======================================================================
  // CARD 4: ACTIVITY OVERVIEW
  // =======================================================================
  Widget _buildActivityOverview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text("Activity Overview", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 16),
        _buildBoxStat(_totalActivities.toString(), "Total Activities", Icons.description_outlined, Colors.blue),
        const SizedBox(height: 12),
        _buildBoxStat(_docActivities.toString(), "Document Activities (Page)", Icons.insert_drive_file_outlined, Colors.green),
        const SizedBox(height: 12),
        _buildBoxStat(_userActivities.toString(), "User Activities (Page)", Icons.people_outline, Colors.orange),
        const SizedBox(height: 12),
        _buildBoxStat(_systemActivities.toString(), "System Activities (Page)", Icons.security_outlined, Colors.purple), 
      ],
    );
  }

  // =======================================================================
  // CARD 5: USER OVERVIEW
  // =======================================================================
  Widget _buildUserOverview() {
    double dPct = _totalUsers == 0 ? 0 : (_deptHeadUsers / _totalUsers) * 100;
    double wPct = _totalUsers == 0 ? 0 : (_workerUsers / _totalUsers) * 100;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text("User Overview", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 16),
        _buildUserRowStat(_totalUsers.toString(), "Total Users", Icons.person, Colors.blue),
        const SizedBox(height: 12),
        _buildUserRowStat(_activeUsers.toString(), "Active Users", Icons.person, Colors.green),
        const SizedBox(height: 12),
        _buildUserRowStat(_inactiveUsers.toString(), "Inactive Users", Icons.person, Colors.grey),
        const SizedBox(height: 20),
        const Text("Role Distribution", style: TextStyle(fontSize: 13, color: Colors.black87, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        SizedBox(
          height: 120, 
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 35,
              sections: _totalUsers == 0
                  ? [
                      PieChartSectionData(
                        color: Colors.grey.shade200,
                        value: 100,
                        title: '',
                        radius: 30,
                      )
                    ]
                  : [
                      if (wPct > 0)
                        PieChartSectionData(
                          color: const Color(0xFF14B8A6), 
                          value: wPct,
                          title: '${wPct.toStringAsFixed(0)}%',
                          radius: 30,
                          titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      if (dPct > 0)
                        PieChartSectionData(
                          color: const Color(0xFF1E3A8A), 
                          value: dPct,
                          title: '${dPct.toStringAsFixed(0)}%',
                          radius: 30,
                          titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                    ],
            ),
            swapAnimationDuration: const Duration(milliseconds: 800),
            swapAnimationCurve: Curves.easeOutCubic,
          ),
        ),
        const SizedBox(height: 16),
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.circle, size: 10, color: Color(0xFF1E3A8A)),
            SizedBox(width: 6),
            Text("DEPARTMENT", style: TextStyle(fontSize: 10, color: Colors.grey)),
            SizedBox(width: 12),
            Icon(Icons.circle, size: 10, color: Color(0xFF14B8A6)),
            SizedBox(width: 6),
            Text("WORKER", style: TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        )
      ],
    );
  }

  // --- Helper Widgets ---

  Widget _buildRowItem(String label, String count, Color countColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
        _isLoadingStats 
            ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2))
            : _CountUpText(count, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: countColor)),
      ],
    );
  }

  Widget _buildBoxStat(String count, String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(border: Border.all(color: borderLight), borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle), 
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _isLoadingStats 
                    ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                    : _CountUpText(count, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
                const SizedBox(height: 2),
                Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey), overflow: TextOverflow.ellipsis, maxLines: 1),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildUserRowStat(String count, String label, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _isLoadingStats 
                ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                : _CountUpText(count, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87)),
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        )
      ],
    );
  }
}

// =============================================================================
// ANIMATED HELPER WIDGETS
// =============================================================================

class _HoverScale extends StatefulWidget {
  const _HoverScale({required this.child});
  final Widget child;

  @override
  State<_HoverScale> createState() => _HoverScaleState();
}

class _HoverScaleState extends State<_HoverScale> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedScale(
        scale: _hovering ? 1.015 : 1.0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

class _CountUpText extends StatelessWidget {
  const _CountUpText(
    this.value, {
    required this.style,
    this.duration = const Duration(milliseconds: 900),
  });

  final String value;
  final TextStyle style;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final match = RegExp(r'^(\d+)(.*)$').firstMatch(value.trim());
    if (match == null) {
      return Text(value, style: style);
    }

    final target = int.parse(match.group(1)!);
    final suffix = match.group(2) ?? '';

    return TweenAnimationBuilder<int>(
      tween: IntTween(begin: 0, end: target),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, animatedValue, _) {
        return Text('$animatedValue$suffix', style: style);
      },
    );
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot({required this.color, this.size = 10});
  final Color color;
  final double size;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value; 
        return Opacity(
          opacity: 0.55 + (0.45 * t),
          child: Transform.scale(
            scale: 0.85 + (0.15 * t),
            child: Icon(Icons.circle, size: widget.size, color: widget.color),
          ),
        );
      },
    );
  }
}