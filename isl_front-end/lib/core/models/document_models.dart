class DocumentItem {
  DocumentItem({
    required this.id,
    required this.title,
    required this.documentNumber,
    required this.type,
    required this.department,
    required this.version,
    required this.updatedAt,
    required this.uploadedByName,
    required this.uploadedByInitials,
    this.uploadedById = '',
    required this.isActive,
    required this.status,
    required this.url,
    this.isSelected = false,
  });

  final String id;
  final String title;
  final String documentNumber;
  final String type;
  final String department;
  final String version;
  final String updatedAt;
  final String uploadedByName;
  final String uploadedByInitials;
  final String uploadedById; // needed client-side to show/hide the toggle
  final bool isActive;
  final String status;
  final String url;
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
    // Real data lives under these nested objects — see DocumentSerializer:
    // `department` / `uploaded_by` are write_only, so the response only
    // ever contains `department_details` / `uploaded_by_details`.
    final deptDetails = json['department_details'];
    final uploaderDetails = json['uploaded_by_details'];

    final departmentName = (deptDetails is Map ? deptDetails['name'] : null)
            as String? ??
        (json['department'] is String ? json['department'] as String : null) ??
        '';

    final uploaderName =
        (uploaderDetails is Map ? uploaderDetails['full_name'] : null)
                as String? ??
            (json['uploaded_by_name'] as String?) ??
            '';

    // Yeh wali line update karni hai
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
      version: (json['version'] ?? 'v1').toString(),
      updatedAt: (json['updated_at'] ?? json['updatedAt'] ?? '').toString(),
      uploadedByName: uploaderName,
      uploadedByInitials: (json['uploaded_by_initials'] ?? '').toString(),
      uploadedById: uploaderId,
      isActive: active,
      status: active ? 'active' : 'inactive',
      url: (json['file_url'] ?? json['url'] ?? '').toString(),
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