import 'package:flutter/foundation.dart';
import 'package:isl_app/core/models/auth_models.dart';
import 'package:isl_app/core/models/document_models.dart';
import 'package:isl_app/core/services/api_service.dart';

/// App-wide state container (Provider/ChangeNotifier).
///
/// Holds the current auth session/profile, the loaded documents/alerts/quick
/// help lists, and simple `_loading`/`_error` flags used by screens to show
/// spinners and error banners. Every method here follows the same pattern:
/// set `_loading = true`, call `_apiService`, update state, and on failure
/// set `_error` to a user-safe message via `friendlyApiError()` (never the
/// raw exception) — then `notifyListeners()` so widgets rebuild.
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
  /// widget (like DepartmentHeadTopHeader) is built fresh and finds no in-memory
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

  /// Logs the user in with employee ID + password, persists the session
  /// (via ApiService.saveSession), and loads their profile. On any failure
  /// the partial session/profile is cleared so the app doesn't end up in a
  /// half-authenticated state.
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
      _error = friendlyApiError(e);
      _session = null;
      _profile = null;
      await _apiService.clearSession();
    } finally {
      _setLoading(false);
    }
  }

  /// Refreshes the current user's profile from the server.
  Future<void> loadProfile() async {
    _setLoading(true);
    try {
      _profile = await _apiService.getProfile();
      _error = null;
    } catch (e) {
      _error = friendlyApiError(e);
    } finally {
      _setLoading(false);
    }
  }

  /// Fetches documents matching the given filters and replaces `_documents`
  /// with the result. Pass `null` for any filter to leave it unrestricted.
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
      _error = friendlyApiError(e);
    } finally {
      _setLoading(false);
    }
  }

  /// Fetches this user's alerts/notifications.
  Future<void> loadAlerts() async {
    _setLoading(true);
    try {
      _alerts = await _apiService.fetchAlerts();
      _error = null;
    } catch (e) {
      _error = friendlyApiError(e);
    } finally {
      _setLoading(false);
    }
  }

  /// Fetches the "Quick Help" reference items shown to users.
  Future<void> loadQuickHelp() async {
    try {
      _quickHelp = await _apiService.fetchQuickHelp();
      _error = null;
    } catch (e) {
      _error = friendlyApiError(e);
    }
    notifyListeners();
  }

  /// Activates/deactivates a document (visibility toggle, not approval) and
  /// patches the local `_documents` list in place with the server's response
  /// so the UI updates without a full reload.
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
                    departmentIds: d.departmentIds,
                    version: d.version,
                    updatedAt: updated.updatedAt,
                    uploadedByName: d.uploadedByName,
                    uploadedByInitials: d.uploadedByInitials,
                    uploadedById: d.uploadedById,
                    isActive: updated.isActive,
                    status: updated.status,
                    url: d.url,
                    approvalStatus: updated.approvalStatus,
                    includeInChatbot: d.includeInChatbot,
                    isSelected: d.isSelected,
                  )
                : d,
          )
          .toList();
      _error = null;
    } catch (e) {
      _error = friendlyApiError(e);
    }
    notifyListeners();
  }

  /// Toggles whether a document is included in the AI chatbot's knowledge
  /// base and patches the local `_documents` list in place with the
  /// server's response (same pattern as [toggleDocumentStatus]).
  Future<void> toggleChatbotInclusion(String id, bool include) async {
    try {
      final updated = await _apiService.toggleChatbotInclusion(id, include);
      _documents = _documents
          .map(
            (d) => d.id == id
                ? DocumentItem(
                    id: d.id,
                    title: d.title,
                    documentNumber: d.documentNumber,
                    type: d.type,
                    department: d.department,
                    departmentIds: d.departmentIds,
                    version: d.version,
                    updatedAt: updated.updatedAt,
                    uploadedByName: d.uploadedByName,
                    uploadedByInitials: d.uploadedByInitials,
                    uploadedById: d.uploadedById,
                    isActive: d.isActive,
                    status: d.status,
                    url: d.url,
                    approvalStatus: d.approvalStatus,
                    includeInChatbot: updated.includeInChatbot,
                    isSelected: d.isSelected,
                  )
                : d,
          )
          .toList();
      _error = null;
    } catch (e) {
      _error = friendlyApiError(e);
    }
    notifyListeners();
  }

  /// Approves a pending document and updates it in the local list in place.
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
      _error = friendlyApiError(e);
    }
    notifyListeners();
  }

  /// Rejects a pending document, optionally with a `reason` (stored in the
  /// backend's AuditLog/Alert). Updates the document in the local list; the
  /// document itself is filtered out of "All Documents" / "Pending" views
  /// once its status becomes REJECTED (see the Documents screens).
  Future<void> rejectDocument(String id, {String? reason}) async {
    try {
      final updated = await _apiService.rejectDocument(id, reason: reason);
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
      _error = friendlyApiError(e);
    }
    notifyListeners();
  }

  /// Permanently deletes a document. Returns `true` on success so callers
  /// can show a confirmation, or `false` (with `error` set) on failure.
  Future<bool> deleteDocument(String id) async {
    try {
      await _apiService.deleteDocument(id);
      _documents.removeWhere((d) => d.id == id);
      _error = null;
      notifyListeners();
      return true;
    } catch (e) {
      _error = friendlyApiError(e);
      notifyListeners();
      return false;
    }
  }

  /// Marks all of the current user's alerts as read, both on the server and
  /// in the local `_alerts` list.
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
      _error = friendlyApiError(e);
    }
    notifyListeners();
  }

  /// Clears the persisted session and resets all in-memory state, returning
  /// the app to a logged-out state.
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