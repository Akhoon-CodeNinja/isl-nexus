class AuthSession {
  const AuthSession({
    required this.token,
    required this.refreshToken,
    required this.role,
    required this.userId,
    required this.email,
    required this.fullName,
    required this.department,
    this.departmentId,
    required this.shift,
    required this.canManageDocs, // Naya field
  });

  final String token;
  final String refreshToken; 
  final String role;
  final String userId;
  final String email;
  final String fullName;
  final String department;
  final String? departmentId;
  final String shift;
  final bool canManageDocs; // Naya field

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    final userObj = json['user'] is Map ? json['user'] : null;
    final role = (json['role'] ?? json['user_role'] ?? userObj?['role'] ?? 'Worker').toString();

    // Backend (CustomTokenObtainPairSerializer) sends the id in two
    // places: top-level `department_id`, and nested under
    // `user.department_details.id`. Nested one is checked first since
    // it's the more structured/reliable source.
    final nestedDeptDetails = userObj?['department_details'];
    final departmentIdValue = (nestedDeptDetails is Map
            ? nestedDeptDetails['id']
            : null) ??
        json['department_id'];
    
    return AuthSession(
      token: (json['access'] ?? json['token'] ?? json['jwt'] ?? '').toString(),
      refreshToken: (json['refresh'] ?? '').toString(),
      role: role,
      userId: (userObj?['id'] ?? json['user_id'] ?? json['id'] ?? '').toString(),
      email: (userObj?['email'] ?? json['email'] ?? '').toString(),
      fullName: (userObj?['full_name'] ?? json['full_name'] ?? json['name'] ?? '').toString(),
      department: (userObj?['department_name'] ?? json['department_name'] ?? json['department'] ?? '').toString(),
      departmentId: departmentIdValue?.toString(),
      shift: (userObj?['shift_timing'] ?? json['shift'] ?? '').toString(),
      canManageDocs: userObj?['can_manage_docs'] ?? json['can_manage_docs'] ?? false, // Parsing
    );
  }
}

class UserProfile {
  const UserProfile({
    required this.id,
    required this.employeeId,
    required this.fullName,
    required this.email,
    required this.role,
    required this.department,
    this.departmentId,
    required this.shift,
    required this.phone,
    required this.canManageDocs, // Naya field
  });

  final String id;
  final String employeeId;
  final String fullName;
  final String email;
  final String role;
  final String department;
  final String? departmentId;
  final String shift;
  final String? phone;
  final bool canManageDocs; // Naya field

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final deptDetails = json['department_details'];
    final departmentName = deptDetails is Map
        ? (deptDetails['name'] ?? '').toString()
        : (json['department'] ?? '').toString();
    final departmentIdValue = deptDetails is Map ? deptDetails['id'] : null;

    return UserProfile(
      id: (json['id'] ?? '').toString(),
      employeeId: (json['employee_id'] ?? json['user_id'] ?? '').toString(),
      fullName: (json['full_name'] ?? json['name'] ?? json['username'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      role: (json['role'] ?? json['user_role'] ?? 'Worker').toString(),
      department: departmentName,
      departmentId: departmentIdValue?.toString(),
      shift: (json['shift'] ?? json['shift_timing'] ?? '').toString(),
      phone: json['phone']?.toString(),
      canManageDocs: json['can_manage_docs'] ?? false, // Parsing
    );
  }
}