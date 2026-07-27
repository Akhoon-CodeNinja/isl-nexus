import 'package:flutter/foundation.dart';
import 'package:isl_app/core/models/auth_models.dart';
import 'package:isl_app/core/models/document_models.dart';
import 'package:isl_app/core/services/api_service.dart';

class AppState extends ChangeNotifier {
  AppState({ApiService? apiService}) : _apiService = apiService ?? ApiService();

  final ApiService _apiService;

  AuthSession? _session;
  UserProfile? _profile;
  bool _loading = false;
  String? _error;
  List<DocumentItem> _documents = [];
  List<AlertItem> _alerts = [];
  List<QuickHelpItem> _quickHelp = [];
  bool _restoreAttempted = false;

  AuthSession? get session => _session;
  UserProfile? get profile => _profile;
  // Logged-in user's own department id — used to restrict the Head's
  // "Pending Approval" tab to their own department only.
  String? get departmentId => _profile?.departmentId ?? _session?.departmentId;
  bool get loading => _loading;
  String? get error => _error;
  List<DocumentItem> get documents => _documents;
  List<AlertItem> get alerts => _alerts;
  List<QuickHelpItem> get quickHelp => _quickHelp;

  /// Rebuilds `_session` from the persisted login token if it's currently
  /// null — e.g. right after a Flutter Web page refresh, or whenever a
  /// widget (like AdminTopHeader) is built fresh and finds no in-memory
  /// session yet. Safe to call from many widgets: after the first attempt
  /// (successful or not) it's a no-op, so it never spams SharedPreferences
  /// reads or fights with an active sign-in.
  Future<void> restoreSessionIfNeeded() async {
    if (_session != null || _restoreAttempted) return;
    _restoreAttempted = true;
    try {
      final restored = await _apiService.restoreSession();
      if (restored != null) {
        _session = restored;
        notifyListeners();
      }
    } catch (_) {
      // Best-effort — leave session null if restore fails for any reason.
    }
  }

  Future<void> signIn({
    required String identifier,
    required String password,
  }) async {
    _setLoading(true);
    try {
      final session = await _apiService.login(
        identifier: identifier,
        password: password,
      );
      await _apiService.saveSession(session);
      _session = session;
      debugPrint(
        'LOGIN SET SESSION — fullName: "${session.fullName}", '
        'role: "${session.role}", department: "${session.department}"',
      ); // TEMPORARY — remove once the header bug is confirmed fixed
      _profile = await _apiService.getProfile();
      _error = null;
    } catch (e) {
      _error = e.toString();
      _session = null;
      _profile = null;
      await _apiService.clearSession();
    } finally {
      _setLoading(false);
    }
  }

  Future<void> loadProfile() async {
    _setLoading(true);
    try {
      _profile = await _apiService.getProfile();
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _setLoading(false);
    }
  }

  Future<void> loadDocuments({
    String? search,
    String? status,
    String? dept,
    String? fileType,
  }) async {
    _setLoading(true);
    try {
      _documents = await _apiService.fetchDocuments(
        search: search,
        status: status,
        dept: dept,
        fileType: fileType,
      );
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _setLoading(false);
    }
  }

  Future<void> loadAlerts() async {
    _setLoading(true);
    try {
      _alerts = await _apiService.fetchAlerts();
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _setLoading(false);
    }
  }

  Future<void> loadQuickHelp() async {
    try {
      _quickHelp = await _apiService.fetchQuickHelp();
      _error = null;
    } catch (e) {
      _error = e.toString();
    }
    notifyListeners();
  }

  Future<void> toggleDocumentStatus(String id, bool active) async {
    try {
      final updated = await _apiService.toggleDocumentStatus(id, active);
      _documents = _documents
          .map(
            (d) => d.id == id
                ? DocumentItem(
                    id: d.id,
                    title: d.title,
                    documentNumber: d.documentNumber,
                    type: d.type,
                    department: d.department,
                    version: d.version,
                    updatedAt: updated.updatedAt,
                    uploadedByName: d.uploadedByName,
                    uploadedByInitials: d.uploadedByInitials,
                    isActive: updated.isActive,
                    status: updated.status,
                    url: d.url,
                    approvalStatus: updated.approvalStatus,
                    isSelected: d.isSelected,
                  )
                : d,
          )
          .toList();
      _error = null;
    } catch (e) {
      _error = e.toString();
    }
    notifyListeners();
  }

  Future<void> approveDocument(String id) async {
    try {
      final updated = await _apiService.approveDocument(id);
      _documents = _documents
          .map(
            (d) => d.id == id
                ? DocumentItem(
                    id: d.id,
                    title: d.title,
                    documentNumber: d.documentNumber,
                    type: d.type,
                    department: d.department,
                    version: d.version,
                    updatedAt: updated.updatedAt,
                    uploadedByName: d.uploadedByName,
                    uploadedByInitials: d.uploadedByInitials,
                    isActive: updated.isActive,
                    status: updated.status,
                    url: d.url,
                    approvalStatus: updated.approvalStatus,
                    isSelected: d.isSelected,
                  )
                : d,
          )
          .toList();
      _error = null;
    } catch (e) {
      _error = e.toString();
    }
    notifyListeners();
  }

  // --- NAYA FUNCTION: Reject Document Handle Karega ---
  Future<void> rejectDocument(String id) async {
    try {
      final updated = await _apiService.rejectDocument(id);
      _documents = _documents
          .map(
            (d) => d.id == id
                ? DocumentItem(
                    id: d.id,
                    title: d.title,
                    documentNumber: d.documentNumber,
                    type: d.type,
                    department: d.department,
                    version: d.version,
                    updatedAt: updated.updatedAt,
                    uploadedByName: d.uploadedByName,
                    uploadedByInitials: d.uploadedByInitials,
                    isActive: updated.isActive,
                    status: updated.status,
                    url: d.url,
                    approvalStatus: updated.approvalStatus,
                    isSelected: d.isSelected,
                  )
                : d,
          )
          .toList();
      _error = null;
    } catch (e) {
      _error = e.toString();
    }
    notifyListeners();
  }

  Future<bool> deleteDocument(String id) async {
    try {
      await _apiService.deleteDocument(id);
      _documents.removeWhere((d) => d.id == id);
      _error = null;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<void> markAlertsRead() async {
    try {
      await _apiService.markAlertsRead();
      _alerts = _alerts
          .map(
            (a) => AlertItem(
              id: a.id,
              title: a.title,
              body: a.body,
              time: a.time,
              category: a.category,
              isUnread: false,
            ),
          )
          .toList();
      _error = null;
    } catch (e) {
      _error = e.toString();
    }
    notifyListeners();
  }

  Future<void> logout() async {
    await _apiService.clearSession();
    _session = null;
    _profile = null;
    _documents = [];
    _alerts = [];
    _quickHelp = [];
    _restoreAttempted = false;
    notifyListeners();
  }

  void _setLoading(bool loading) {
    _loading = loading;
    notifyListeners();
  }
}