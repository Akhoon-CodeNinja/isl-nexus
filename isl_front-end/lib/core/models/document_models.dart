class DocumentItem {
  DocumentItem({
    required this.id,
    required this.title,
    required this.documentNumber,
    required this.type,
    required this.department,
    this.departmentIds = const [],
    required this.version,
    required this.updatedAt,
    required this.uploadedByName,
    required this.uploadedByInitials,
    this.uploadedById = '',
    required this.isActive,
    required this.status,
    required this.url,
    required this.approvalStatus, // Naya field
    this.isSelected = false,
  });

  final String id;
  final String title;
  final String documentNumber;
  final String type;
  final String department;
  final List<String> departmentIds;
  final String version;
  final String updatedAt;
  final String uploadedByName;
  final String uploadedByInitials;
  final String uploadedById; 
  final bool isActive;
  final String status;
  final String url;
  final String approvalStatus; // Naya field
  bool isSelected;

  static bool _parseBool(dynamic v) {
    if (v is bool) return v;
    if (v is String) {
      final s = v.toLowerCase();
      return s == 'true' || s == 'active' || s == '1';
    }
    return false;
  }

  factory DocumentItem.fromJson(Map<String, dynamic> json) {
    // Backend sends 'departments_details' (plural — a document can belong
    // to more than one department), NOT a singular 'department_details'.
    // We join all linked department names so nothing gets silently dropped.
    final deptList = json['departments_details'];
    final uploaderDetails = json['uploaded_by_details'];

    final departmentName = (deptList is List && deptList.isNotEmpty)
        ? deptList
            .map((d) => (d is Map ? d['name'] : null)?.toString() ?? '')
            .where((n) => n.isNotEmpty)
            .join(', ')
        : '';

    final departmentIdList = (deptList is List)
        ? deptList
            .map((d) => (d is Map ? d['id'] : null)?.toString() ?? '')
            .where((idStr) => idStr.isNotEmpty)
            .toList()
        : <String>[];

    final uploaderName =
        (uploaderDetails is Map ? uploaderDetails['full_name'] : null)
                as String? ??
            (json['uploaded_by_name'] as String?) ??
            '';

    final uploaderId =
        (uploaderDetails is Map ? uploaderDetails['id'] : null)?.toString() ??
        (json['uploaded_by']?.toString()) ??
        '';

    final active = _parseBool(json['is_active']);

    return DocumentItem(
      id: (json['id'] ?? json['document_id'] ?? '').toString(),
      title: (json['title'] ?? json['name'] ?? '').toString(),
      documentNumber: (json['document_number'] ?? json['doc_number'] ?? '')
          .toString(),
      type: (json['file_type'] ?? json['type'] ?? 'PDF').toString(),
      department: departmentName,
      departmentIds: departmentIdList,
      version: (json['version'] ?? 'v1').toString(),
      updatedAt: (json['updated_at'] ?? json['updatedAt'] ?? '').toString(),
      uploadedByName: uploaderName,
      uploadedByInitials: (json['uploaded_by_initials'] ?? '').toString(),
      uploadedById: uploaderId,
      isActive: active,
      status: active ? 'active' : 'inactive',
      url: (json['file_url'] ?? json['url'] ?? '').toString(),
      approvalStatus: (json['approval_status'] ?? 'PENDING').toString(), // Parsing
      isSelected: false,
    );
  }
}

class AlertItem {
  const AlertItem({
    required this.id,
    required this.title,
    required this.body,
    required this.time,
    required this.category,
    required this.isUnread,
  });

  final String id;
  final String title;
  final String body;
  final String time;
  final String category;
  final bool isUnread;

  factory AlertItem.fromJson(Map<String, dynamic> json) {
    return AlertItem(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      body: (json['message'] ?? json['body'] ?? '').toString(),
      time: (json['created_at'] ?? json['time'] ?? '').toString(),
      category: (json['category'] ?? 'General').toString(),
      isUnread: json['is_unread'] ?? json['unread'] ?? true,
    );
  }
}

class QuickHelpItem {
  const QuickHelpItem({
    required this.id,
    required this.title,
    required this.description,
  });

  final String id;
  final String title;
  final String description;

  factory QuickHelpItem.fromJson(Map<String, dynamic> json) {
    return QuickHelpItem(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
    );
  }
}