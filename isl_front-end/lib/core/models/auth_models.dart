class AuthSession {
  const AuthSession({
    required this.token,
    required this.refreshToken,
    required this.role,
    required this.userId,
    required this.email,
    required this.fullName,
    required this.department,
    required this.shift,
  });

  final String token;
  final String refreshToken; 
  final String role;
  final String userId;
  final String email;
  final String fullName;
  final String department;
  final String shift;

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    // Backend nested 'user' object bhejta hai, pehle usay pakrein
    final userObj = json['user'] is Map ? json['user'] : null;
    
    // Role aur baqi cheezein root ya nested dono jagah se check karein
    final role = (json['role'] ?? json['user_role'] ?? userObj?['role'] ?? 'Worker').toString();
    
    return AuthSession(
      token: (json['access'] ?? json['token'] ?? json['jwt'] ?? '').toString(),
      refreshToken: (json['refresh'] ?? '').toString(),
      role: role,
      // ASAL FIX: userObj?['id'] ko priority deni hai
      userId: (userObj?['id'] ?? json['user_id'] ?? json['id'] ?? '').toString(),
      email: (userObj?['email'] ?? json['email'] ?? '').toString(),
      fullName: (userObj?['full_name'] ?? json['full_name'] ?? json['name'] ?? '').toString(),
      department: (userObj?['department_name'] ?? json['department_name'] ?? json['department'] ?? '').toString(),
      shift: (userObj?['shift_timing'] ?? json['shift'] ?? '').toString(),
    );
  }
}

// UserProfile class waisi hi rahegi jaisi aapke paas already updated hai
class UserProfile {
  const UserProfile({
    required this.id,
    required this.employeeId,
    required this.fullName,
    required this.email,
    required this.role,
    required this.department,
    required this.shift,
    required this.phone,
  });

  final String id;
  final String employeeId;
  final String fullName;
  final String email;
  final String role;
  final String department;
  final String shift;
  final String? phone;

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final deptDetails = json['department_details'];
    final departmentName = deptDetails is Map
        ? (deptDetails['name'] ?? '').toString()
        : (json['department'] ?? '').toString();

    return UserProfile(
      id: (json['id'] ?? '').toString(),
      employeeId: (json['employee_id'] ?? json['user_id'] ?? '').toString(),
      fullName: (json['full_name'] ?? json['name'] ?? json['username'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      role: (json['role'] ?? json['user_role'] ?? 'Worker').toString(),
      department: departmentName,
      shift: (json['shift'] ?? json['shift_timing'] ?? '').toString(),
      phone: json['phone']?.toString(),
    );
  }
}