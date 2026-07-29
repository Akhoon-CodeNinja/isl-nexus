import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

class ApiException implements Exception {
  final String message;
  ApiException(this.message);

  @override
  String toString() => message;
}

class AuthService {
  // Pure App-Based connection ke liye Android Emulator IP
  static const String _baseUrl = kIsWeb
      ? 'http://localhost:8000/api'
      : 'http://10.0.2.2:8000/api';

  static const String _accessTokenKey = 'access_token';
  static const String _refreshTokenKey = 'refresh_token';
  static const String _userRoleKey = 'user_role';
  static const String _userDataKey = 'user_data';

  late final Dio _dio;

  AuthService() {
    _dio = Dio(
      BaseOptions(
        baseUrl: _baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        headers: {'Content-Type': 'application/json'},
      ),
    );

    // Interceptor: Har API request mein token attach karega
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final prefs = await SharedPreferences.getInstance();
          final token = prefs.getString(_accessTokenKey);
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          return handler.next(options);
        },
      ),
    );
  }

  

  String _extractError(DioException e) {
    final data = e.response?.data;
    if (data is Map) {
      if (data['message'] != null) return data['message'].toString();
      if (data['detail'] != null) return data['detail'].toString();
      final firstKey = data.keys.isNotEmpty ? data.keys.first : null;
      if (firstKey != null &&
          data[firstKey] is List &&
          (data[firstKey] as List).isNotEmpty) {
        return '$firstKey: ${(data[firstKey] as List).first}';
      }
    }
    return 'Server error. Please try again.';
  }

  // --- REGISTER (Sign Up) ---
  Future<String> register({
    required String employeeId,
    required String password,
    required String fullName,
    required String email,
    required int department,
  }) async {
    try {
      final response = await _dio.post(
        '/auth/register/',
        data: {
          'employee_id': employeeId,
          'password': password,
          'full_name': fullName,
          'email': email,
          'department': department,
        },
      );
      return response.data['message']?.toString() ?? 'OTP sent to your email.';
    } on DioException catch (e) {
      throw ApiException(_extractError(e));
    }
  }

  // --- VERIFY OTP ---
  Future<String> verifyOtp({
    required String employeeId,
    required String otp,
  }) async {
    try {
      final response = await _dio.post(
        '/auth/verify-otp/',
        data: {'employee_id': employeeId, 'otp': otp},
      );
      return response.data['message']?.toString() ?? 'Account verified.';
    } on DioException catch (e) {
      throw ApiException(_extractError(e));
    }
  }

  // --- RESEND OTP ---
  Future<String> resendOtp({required String employeeId}) async {
    try {
      final response = await _dio.post(
        '/auth/resend-otp/',
        data: {'employee_id': employeeId},
      );
      return response.data['message']?.toString() ?? 'New OTP sent.';
    } on DioException catch (e) {
      throw ApiException(_extractError(e));
    }
  }

  // --- LOGIN ---
  Future<Map<String, dynamic>> login({
    required String employeeId,
    required String password,
  }) async {
    try {
      final response = await _dio.post(
        '/auth/login/',
        data: {'employee_id': employeeId, 'password': password},
      );

      final data = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : <String, dynamic>{};

      await storeUserSession(data);
      return data;
    } on DioException catch (e) {
      throw ApiException(_extractError(e));
    }
  }

  // --- SESSION MANAGEMENT ---
  Future<void> storeUserSession(Map<String, dynamic> responseData) async {
    final prefs = await SharedPreferences.getInstance();

    final accessToken = responseData['access']?.toString();
    final refreshToken = responseData['refresh']?.toString();
    final userMap = responseData['user'];

    // Yahan hum role direct user object se nikal rahe hain
    final role = userMap != null ? userMap['role']?.toString() : null;

    if (accessToken != null && accessToken.isNotEmpty) {
      await prefs.setString(_accessTokenKey, accessToken);
    }
    if (refreshToken != null && refreshToken.isNotEmpty) {
      await prefs.setString(_refreshTokenKey, refreshToken);
    }
    if (role != null && role.isNotEmpty) {
      await prefs.setString(_userRoleKey, role);
    }

    final userData = userMap is Map
        ? Map<String, dynamic>.from(userMap)
        : responseData;
    await prefs.setString(_userDataKey, jsonEncode(userData));
  }

  Future<bool> isAuthenticated() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_accessTokenKey);
    return token != null && token.isNotEmpty;
  }

  Future<String?> getStoredUserRole() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_userRoleKey);
  }

  bool isAdminRole(String? role) {
    final normalized = role?.trim().toUpperCase();
    return normalized == 'ADMIN' || normalized == 'DEPARTMENT_HEAD';
  }

  bool isDepartmentHeadRole(String? role) {
    final normalized = role?.trim().toUpperCase();
    return normalized == 'DEPARTMENT_HEAD';
  }

  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear(); // Clears all auth keys properly
  }
}
