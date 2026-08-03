import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:isl_app/core/models/auth_models.dart';
import 'package:isl_app/core/models/document_models.dart';

class ApiService {
  ApiService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  static bool needsFreshChatSession = true;

  static const String baseUrl = kIsWeb ? 'http://127.0.0.1:8000' : 'http://10.0.2.2:8000';
  
  static const String authLogin = '/api/auth/login/';
  static const String authRefresh = '/api/auth/refresh/'; 
  static const String authMicrosoft = '/api/auth/microsoft/';
  static const String me = '/api/auth/me/';
  
  static const String documents = '/api/documents/';
  static const String departments = '/api/departments/';
  static const String users = '/api/users/';
  static const String chatAsk = '/api/chat/ask/';
  static const String chatHistory = '/api/chat/history/';
  static const String chatNewSession = '/api/chat/session/new/';
  static const String chatSessions = '/api/chat/sessions/';
  static const String leaveApply = '/api/leave/apply/';
  static const String alerts = '/api/alerts/';
  static const String quickHelp = '/api/help/';
  static const String auditLogs = '/api/audit-logs/'; 
  static const String settings = '/api/settings/';
  static const String syncStatus = '/api/system/sync-status/';
  
  // NAYA: Notification Templates Endpoint
  static const String notificationTemplates = '/api/notification-templates/';

  String? _memoryToken;

  Future<String?> _readToken() async {
    if (_memoryToken != null && _memoryToken!.isNotEmpty) return _memoryToken;
    final prefs = await SharedPreferences.getInstance();
    _memoryToken = prefs.getString('access_token');
    return _memoryToken;
  }

  Future<Map<String, String>> _headers({bool auth = true}) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (auth) {
      final token = await _readToken();
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    }
    return headers;
  }

  Future<void> saveSession(AuthSession session) async {
    _memoryToken = session.token;
    needsFreshChatSession = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('access_token', session.token);
    await prefs.setString('refresh_token', session.refreshToken);
    await prefs.setString('role', session.role);
    await prefs.setString('user_id', session.userId);
    await prefs.setString('email', session.email);
    await prefs.setString('name', session.fullName);
    await prefs.setString('department', session.department);
    await prefs.setString('shift', session.shift);
    await prefs.setBool('can_manage_docs', session.canManageDocs);
  }

  Future<void> clearSession() async {
    _memoryToken = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await _storage.deleteAll();
  }

  Future<AuthSession?> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');
    final refreshToken = prefs.getString('refresh_token') ?? '';
    if (token == null || token.isEmpty) return null;
    
    _memoryToken = token;
    return AuthSession(
      token: token,
      refreshToken: refreshToken,
      role: prefs.getString('role') ?? '',
      userId: prefs.getString('user_id') ?? '',
      email: prefs.getString('email') ?? '',
      fullName: prefs.getString('name') ?? '',
      department: prefs.getString('department') ?? '',
      shift: prefs.getString('shift') ?? '',
      canManageDocs: prefs.getBool('can_manage_docs') ?? false,
    );
  }

  // --- AUTHENTICATION & PROFILE ---
  Future<AuthSession> login({required String identifier, required String password}) async {
    final response = await _post(
      authLogin,
      body: {'employee_id': identifier, 'password': password},
      auth: false,
    );
    final data = response['data'] as Map<String, dynamic>? ?? {};
    return AuthSession.fromJson(data);
  }

  Future<Map<String, dynamic>> loginWithMicrosoftToken(String token) async {
    final response = await _post(
      authMicrosoft,
      body: {'access_token': token},
      auth: false,
    );
    return response['data'] as Map<String, dynamic>? ?? {};
  }

  Future<UserProfile> getProfile() async {
    final response = await _get(me);
    final data = response['data'] as Map<String, dynamic>? ?? {};
    return UserProfile.fromJson(data);
  }

  Future<UserProfile> updateProfile({required String fullName, required String email}) async {
    final response = await _patch(me, body: {'full_name': fullName, 'email': email});
    final data = response['data'] as Map<String, dynamic>? ?? {};
    return UserProfile.fromJson(data);
  }

  // --- NOTIFICATION TEMPLATES (ADMIN) ---
  Future<List<Map<String, dynamic>>> fetchNotificationTemplates({String? status}) async {
    final query = <String, String>{};
    if (status != null && status != 'All Status') query['status'] = status;
    final response = await _get(notificationTemplates, query: query);
    return _asList(response['data']);
  }

  Future<Map<String, dynamic>> createNotificationTemplate({
    required String title, required String bodyText, required String type,
  }) async {
    final response = await _post(notificationTemplates, body: {'title': title, 'body': bodyText, 'type': type});
    return response['data'] as Map<String, dynamic>? ?? {};
  }

  Future<Map<String, dynamic>> updateNotificationTemplate(String id, {
    required String title, required String bodyText, required String type,
  }) async {
    final response = await _patch('$notificationTemplates$id/', body: {'title': title, 'body': bodyText, 'type': type});
    return response['data'] as Map<String, dynamic>? ?? {};
  }

  Future<void> deleteNotificationTemplate(String id) async {
    await _delete('$notificationTemplates$id/');
  }

  Future<void> setNotificationTemplateStatus(String id, String status) async {
    await _patch('$notificationTemplates$id/set_status/', body: {'status': status});
  }

  // --- USERS MANAGEMENT (ADMIN) ---
  Future<List<Map<String, dynamic>>> fetchUsersRaw({
    String? search, String? department, String? role, String? status,
  }) async {
    final query = <String, String>{};
    if (search != null && search.isNotEmpty) query['search'] = search;
    if (department != null && department.isNotEmpty && department.toLowerCase() != 'all departments') query['department'] = department;
    if (role != null && role.isNotEmpty && role.toLowerCase() != 'all roles') query['role'] = role;
    if (status != null && status.isNotEmpty && status.toLowerCase() != 'all status') query['status'] = status;
    final response = await _get(users, query: query);
    return _asList(response['data']);
  }

  Future<void> addUser({
    required String employeeId, required String name, required String email, 
    required String password, required String role, required String department,
  }) async {
    await _post(users, body: {
      'employee_id': employeeId, 'full_name': name, 'email': email,
      'password': password, 'role': role, 'department': department,
    });
  }

  Future<void> updateUser(String userId, {required String name, required String email, required String department}) async {
    await _patch('$users$userId/', body: {'full_name': name, 'email': email, 'department': department});
  }

  Future<void> toggleUserStatus(String userId, bool active) async {
    await _patch('$users$userId/status/', body: {'is_active': active});
  }

  Future<void> changeUserRole(String userId, String newRole) async {
    await _patch('$users$userId/change_role/', body: {'role': newRole});
  }

  Future<void> toggleUploadAccess(String userId, bool canManage) async {
    await _patch('$users$userId/toggle_upload_access/', body: {'can_manage_docs': canManage});
  }

  Future<void> setChatLimit(String userId, int? limit) async {
    await _patch('$users$userId/set_chat_limit/', body: {'chat_daily_limit_override': limit});
  }

  Future<void> deleteUser(String userId) async {
    await _delete('$users$userId/');
  }

  // --- DEPARTMENTS MANAGEMENT ---
  Future<List<Map<String, dynamic>>> fetchDepartments() async {
    return fetchDepartmentsRaw();
  }

  Future<List<Map<String, dynamic>>> fetchDepartmentsRaw() async {
    final response = await _get(departments, auth: true); 
    return _asList(response['data']);
  }

  Future<void> createDepartment({required String name, required String code, required String description}) async {
    await _post(departments, body: {'name': name, 'code': code, 'description': description});
  }

  // --- DOCUMENTS MANAGEMENT ---
  Future<List<DocumentItem>> fetchDocuments({String? search, String? status, String? dept, String? fileType}) async {
    final query = <String, String>{};
    if (search != null && search.isNotEmpty) query['search'] = search;
    if (status != null && status.toLowerCase() != 'all status' && status.toLowerCase() != 'all') query['status'] = status;
    if (dept != null && dept.toLowerCase() != 'all departments' && dept.toLowerCase() != 'all') query['department'] = dept;
    if (fileType != null && fileType.toLowerCase() != 'all file types' && fileType.toLowerCase() != 'all') query['file_type'] = fileType;
    
    final response = await _get(documents, query: query);
    final responseData = response['data'];
    List<dynamic> items = [];
    if (responseData is List) items = responseData;
    else if (responseData is Map && responseData.containsKey('results')) items = responseData['results'] as List<dynamic>;

    return items.map((e) => DocumentItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<DocumentItem> createDocument(Map<String, dynamic> payload) async {
    final response = await _post(documents, body: payload);
    final data = response['data'] as Map<String, dynamic>? ?? {};
    return DocumentItem.fromJson(data);
  }

  Future<DocumentItem> updateDocument(String id, Map<String, dynamic> payload) async {
    final response = await _patch('$documents$id/', body: payload);
    final data = response['data'] as Map<String, dynamic>? ?? {};
    return DocumentItem.fromJson(data);
  }

  Future<void> deleteDocument(String id) async {
    await _delete('$documents$id/');
  }

  Future<DocumentItem> toggleDocumentStatus(String id, bool active) async {
    final response = await _patch('$documents$id/status/', body: {'is_active': active});
    final data = response['data'] as Map<String, dynamic>? ?? {};
    return DocumentItem.fromJson(data);
  }

  Future<DocumentItem> approveDocument(String id) async {
    final response = await _post('$documents$id/approve/', body: {});
    final data = response['data'] as Map<String, dynamic>? ?? {};
    return DocumentItem.fromJson(data);
  }

  Future<DocumentItem> rejectDocument(String id, {String? reason}) async {
    final response = await _post(
      '$documents$id/reject/',
      body: {if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim()},
    );
    final data = response['data'] as Map<String, dynamic>? ?? {};
    return DocumentItem.fromJson(data);
  }

  // --- CHAT & HELP ---
  Future<Map<String, dynamic>> askChatWithReferences(String message) async {
    final response = await _post(chatAsk, body: {'message': message});
    final data = response['data'] as Map<String, dynamic>? ?? {};

    final rawRefs = (data['references'] as List<dynamic>? ?? []);
    final token = await _readToken();
    final references = rawRefs.map((r) {
      final ref = Map<String, dynamic>.from(r as Map);
      final docId = ref['doc_id'];
      if (docId != null && token != null && token.isNotEmpty) {
        ref['url'] = '$baseUrl$documents$docId/view/?token=$token';
      }
      return ref;
    }).toList();

    return {
      'answer': (data['answer'] ?? data['response'] ?? 'No answer found.').toString(),
      'references': references,
      'required_docs': data['required_docs'] ?? [],
      'intent': data['intent']?.toString(),
      'remaining_messages_today': data['remaining_messages_today'],
    };
  }

  Future<String> askChat(String message) async {
    final response = await _post(chatAsk, body: {'message': message});
    final data = response['data'] as Map<String, dynamic>? ?? {};
    return (data['answer'] ?? data['response'] ?? '').toString();
  }

  Future<Map<String, dynamic>> fetchChatHistory({int? limit, String? sessionId}) async {
    final response = await _get(chatHistory, query: {if (limit != null) 'limit': limit.toString(), 'session_id': ?sessionId});
    final data = response['data'] as Map<String, dynamic>? ?? {};
    final rawMessages = data['messages'] as List<dynamic>? ?? [];
    return {
      'session_id': data['session_id'],
      'daily_limit': data['daily_limit'],
      'remaining_messages_today': data['remaining_messages_today'],
      'messages': rawMessages.map((m) => Map<String, dynamic>.from(m as Map)).toList(),
    };
  }

  Future<Map<String, dynamic>> startNewChatSession() async {
    final response = await _post(chatNewSession, body: {});
    return response['data'] as Map<String, dynamic>? ?? {};
  }

  Future<List<Map<String, dynamic>>> fetchChatSessions() async {
    final response = await _get(chatSessions);
    final data = response['data'] as Map<String, dynamic>? ?? {};
    final raw = data['sessions'] as List<dynamic>? ?? [];
    return raw.map((s) => Map<String, dynamic>.from(s as Map)).toList();
  }

  Future<void> deleteChatSession(String sessionId) async {
    await _delete('$chatSessions$sessionId/');
  }

  Future<void> deleteAllChatSessions() async {
    await _delete(chatSessions); 
  }

  Future<void> sendFeedback(String messageId, bool helpful) async {
    await _post('/api/chat/feedback/', body: {'message_id': messageId, 'helpful': helpful});
  }

  // --- LEAVES & ALERTS ---
  Future<Map<String, dynamic>> submitLeaveApplication({required String leaveType, String reason = ''}) async {
    final response = await _post(leaveApply, body: {'leave_type': leaveType, 'reason': reason});
    return response['data'] as Map<String, dynamic>? ?? {};
  }

  Future<List<AlertItem>> fetchAlerts() async {
    final response = await _get(alerts);
    final items = response['data'] as List<dynamic>? ?? [];
    return items.map((e) => AlertItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> markAlertsRead() async {
    await _patch(alerts, body: {'mark_all_read': true});
  }

  Future<void> sendNotification({required String title, required String description, required String type, String? targetDepartmentId}) async {
    final payload = <String, dynamic>{'title': title, 'description': description, 'type': type};
    if (targetDepartmentId != null && targetDepartmentId.isNotEmpty) {
      payload['target_department'] = targetDepartmentId;
    }
    await _post(alerts, body: payload);
  }

  Future<List<QuickHelpItem>> fetchQuickHelp() async {
    final response = await _get(quickHelp);
    final items = response['data'] as List<dynamic>? ?? [];
    return items.map((e) => QuickHelpItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  // --- SYSTEM SETTINGS & AUDIT LOGS ---
  Future<Map<String, dynamic>> fetchSettings() async {
    final response = await _get(settings);
    return response['data'] as Map<String, dynamic>? ?? {};
  }

  Future<Map<String, dynamic>> updateSettings(Map<String, dynamic> payload) async {
    final response = await _patch(settings, body: payload);
    return response['data'] as Map<String, dynamic>? ?? {};
  }

  Future<Map<String, dynamic>> fetchActivityLogsRaw({
    int page = 1, String search = '', String user = 'All Users', 
    String action = 'All Actions', String module = 'All Modules', 
    DateTime? startDate, DateTime? endDate,
  }) async {
    final query = <String, String>{'page': page.toString()};
    if (search.isNotEmpty) query['search'] = search;
    if (user != 'All Users') query['user'] = user;
    if (action != 'All Actions') query['action'] = action;
    if (module != 'All Modules') query['module'] = module;
    if (startDate != null) query['start_date'] = startDate.toIso8601String();
    if (endDate != null) query['end_date'] = endDate.toIso8601String();

    final response = await _get(auditLogs, query: query);
    return response['data'] as Map<String, dynamic>;
  }
  
  Future<List<dynamic>> fetchAuditLogStats() async {
    final response = await _get('${auditLogs}stats/');
    final data = response['data'];
    if (data is List) return data;
    else if (data is Map && data.containsKey('results')) return data['results'] as List<dynamic>;
    return [];
  }
  
  Future<Map<String, dynamic>> fetchSyncStatus() async {
    final response = await _get(syncStatus);
    return response['data'] as Map<String, dynamic>? ?? {};
  }

  Future<List<dynamic>> fetchDistinctActivityValues({required String field}) async {
    final response = await _get('${auditLogs}distinct/', query: {'field': field});
    final data = response['data'];
    if (data is Map && data['values'] is List) return data['values'] as List<dynamic>;
    return [];
  }

  List<Map<String, dynamic>> _asList(dynamic data) {
    if (data is List) return List<Map<String, dynamic>>.from(data);
    if (data is Map && data['results'] is List) return List<Map<String, dynamic>>.from(data['results'] as List);
    return [];
  }

  // --- INTERNAL REQUEST HELPERS ---
  Future<Map<String, dynamic>> _get(String path, {Map<String, String>? query, bool auth = true}) async {
    return _request('GET', path, query: query, auth: auth);
  }

  Future<Map<String, dynamic>> _post(String path, {required Map<String, dynamic> body, bool auth = true}) async {
    return _request('POST', path, body: body, auth: auth);
  }

  Future<Map<String, dynamic>> _patch(String path, {Map<String, dynamic>? body, bool auth = true}) async {
    return _request('PATCH', path, body: body, auth: auth);
  }

  Future<Map<String, dynamic>> _delete(String path, {bool auth = true}) async {
    return _request('DELETE', path, auth: auth);
  }

  Future<Map<String, dynamic>> _request(String method, String path, {Map<String, dynamic>? body, Map<String, String>? query, bool auth = true, bool isRetry = false}) async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
    final headers = await _headers(auth: auth);
    http.Response response;
    try {
      if (method == 'GET') {
        response = await _client.get(uri, headers: headers).timeout(const Duration(seconds: 15));
      } else if (method == 'POST') {
        response = await _client.post(uri, headers: headers, body: jsonEncode(body ?? {})).timeout(const Duration(seconds: 15));
      } else if (method == 'PATCH') {
        response = await _client.patch(uri, headers: headers, body: jsonEncode(body ?? {})).timeout(const Duration(seconds: 15));
      } else {
        response = await _client.delete(uri, headers: headers).timeout(const Duration(seconds: 15));
      }
    } on SocketException catch (_) {
      throw Exception('Network unavailable. Please check your connection.');
    } on HttpException catch (_) {
      throw Exception('Server communication failed.');
    } on FormatException catch (_) {
      throw Exception('Unexpected response format.');
    } catch (_) {
      throw Exception('Request failed. Please try again.');
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final bodyText = response.body.isEmpty ? '{}' : response.body;
      final decoded = jsonDecode(bodyText);
      if (decoded is Map<String, dynamic>) return {'data': decoded};
      if (decoded is List) return {'data': decoded};
      return {'data': decoded};
    }

    if (response.statusCode == 401) {
      if (!isRetry && auth) {
        final refreshed = await _attemptTokenRefresh();
        if (refreshed) return _request(method, path, body: body, query: query, auth: auth, isRetry: true);
      }
      await clearSession();
      throw Exception('Session expired. Please sign in again.');
    }

    throw Exception(_extractErrorMessage(response));
  }

  Future<bool> _attemptTokenRefresh() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final refreshToken = prefs.getString('refresh_token');
      if (refreshToken == null || refreshToken.isEmpty) return false;

      final uri = Uri.parse('$baseUrl$authRefresh');
      final response = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode({'refresh': refreshToken}),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final newAccess = data['access'] ?? data['token'];
        if (newAccess != null) {
          _memoryToken = newAccess;
          await prefs.setString('access_token', newAccess);
          return true;
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  String _extractErrorMessage(http.Response response) {
    try {
      final bodyText = response.body.isEmpty ? '{}' : response.body;
      final decoded = jsonDecode(bodyText);
      if (decoded is Map) {
        if (decoded['message'] != null) return decoded['message'].toString();
        if (decoded['detail'] != null) return decoded['detail'].toString();
        final firstKey = decoded.keys.isNotEmpty ? decoded.keys.first : null;
        if (firstKey != null && decoded[firstKey] is List && (decoded[firstKey] as List).isNotEmpty) {
          return '$firstKey: ${(decoded[firstKey] as List).first}';
        }
      }
    } catch (_) {}
    return 'Request failed (${response.statusCode}).';
  }
}

String friendlyApiError(Object error) {
  return error.toString().replaceFirst('Exception: ', '');
}