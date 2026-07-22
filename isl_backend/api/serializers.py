from rest_framework_simplejwt.serializers import TokenObtainPairSerializer
from rest_framework import serializers
from django.contrib.auth import get_user_model
# UPDATE: Added AuditLog to imports
from .models import Department, Tag, Document, Alert, ChatSession, ChatMessage, AuditLog, SystemSettings

User = get_user_model()

class CustomTokenObtainPairSerializer(TokenObtainPairSerializer):
    """Custom JWT login to return user role, name, and department."""
    
    @classmethod
    def get_token(cls, user):
        token = super().get_token(user)
        token['role'] = user.role
        return token

    def validate(self, attrs):
        data = super().validate(attrs)
        data['role'] = self.user.role
        data['full_name'] = self.user.full_name 
        data['shift'] = self.user.shift_timing or ''
        
        department_details = None
        if self.user.department: 
            data['department_id'] = str(self.user.department.id)
            data['department_name'] = self.user.department.name
            department_details = {
                'id': str(self.user.department.id),
                'name': self.user.department.name,
            }
        else:
            data['department_id'] = None
            data['department_name'] = None

        # NOTE: the top-level fields above (role, full_name, department_id,
        # department_name) are kept as-is — AuthSession.fromJson() on the
        # Flutter side (used by AppState / admin sidebar / admin header)
        # reads exactly those. Some other frontend code (e.g.
        # worker_header.dart) expects a nested `user.department_details`
        # shape instead, so both are sent rather than picking one and
        # breaking the other.
        data['user'] = {
            'id': str(self.user.id),
            'full_name': self.user.full_name,
            'role': self.user.role,
            'department_details': department_details,
            'shift_timing': self.user.shift_timing or '',
        }

        return data

# --- Standard Model Serializers ---

class DepartmentSerializer(serializers.ModelSerializer):
    users_count = serializers.SerializerMethodField()
    documents_count = serializers.SerializerMethodField()
    description = serializers.SerializerMethodField()
    is_active = serializers.SerializerMethodField()

    class Meta:
        model = Department
        fields = [
            'id', 'name', 'code', 'created_at',
            'description', 'is_active', 'users_count', 'documents_count',
        ]

    def get_users_count(self, obj):
        return User.objects.filter(department=obj).count()

    def get_documents_count(self, obj):
        return Document.objects.filter(departments=obj).count()

    def get_description(self, obj):
        return getattr(obj, 'description', '') or ''

    def get_is_active(self, obj):
        return getattr(obj, 'is_active', True)


class UserMinimalSerializer(serializers.ModelSerializer):
    """Read-only serializer for nested user data."""
    class Meta:
        model = User
        fields = ['id', 'employee_id', 'full_name', 'role'] 


class UserListSerializer(serializers.ModelSerializer):
    department_details = DepartmentSerializer(source='department', read_only=True)

    class Meta:
        model = User
        fields = [
            'id', 'employee_id', 'full_name', 'email', 'role',
            'department_details', 'is_active', 'last_login', 'date_joined',
            'shift_timing',
        ]

class MeSerializer(serializers.ModelSerializer):
    """Used for GET/PATCH /api/auth/me/ — a user editing their own profile.

    Deliberately much stricter than UserListSerializer: only full_name
    and email are writable. role, employee_id, department, is_active,
    and shift_timing are admin-assigned and must stay read-only here,
    or any authenticated worker could PATCH their own role to
    DEPARTMENT_HEAD.
    """
    department_details = DepartmentSerializer(source='department', read_only=True)

    class Meta:
        model = User
        fields = [
            'id', 'employee_id', 'full_name', 'email', 'role',
            'department_details', 'is_active', 'last_login', 'date_joined',
            'shift_timing',
        ]
        read_only_fields = [
            'id', 'employee_id', 'role', 'department_details',
            'is_active', 'last_login', 'date_joined', 'shift_timing',
        ]

class TagSerializer(serializers.ModelSerializer):
    class Meta:
        model = Tag
        fields = ['id', 'name', 'department']

class DocumentSerializer(serializers.ModelSerializer):
    uploaded_by_details = UserMinimalSerializer(source='uploaded_by', read_only=True)
    # Multi-department documents: a document can now belong to more than
    # one department. This is read-only here on purpose — writing it is
    # handled manually in DocumentViewSet.perform_create, because the
    # Flutter multipart upload sends department IDs as a single
    # comma-separated field (`departments=id1,id2`) rather than the
    # repeated-key form DRF's ManyRelatedField expects from HTML/multipart
    # input.
    departments_details = DepartmentSerializer(source='departments', many=True, read_only=True)
    tags_details = TagSerializer(source='tags', many=True, read_only=True)

    class Meta:
        model = Document
        fields = [
            'id', 'title', 'doc_number', 'file_url', 'file_type', 'version', 
            'approval_status', 'is_active', 'created_at', 'updated_at',
            'uploaded_by', 'uploaded_by_details', 
            'departments_details',
            'tags', 'tags_details'
        ]
        extra_kwargs = {
            'uploaded_by': {'write_only': True, 'required': False},
        }

class AlertSerializer(serializers.ModelSerializer):
    created_by_details = UserMinimalSerializer(source='created_by', read_only=True)
    target_department_details = DepartmentSerializer(source='target_department', read_only=True)
    is_read = serializers.SerializerMethodField()

    class Meta:
        model = Alert
        fields = [
            'id', 'title', 'description', 'type', 
            'target_department', 'target_department_details', 
            'created_by', 'created_by_details', 'created_at', 'is_read'
        ]
        extra_kwargs = {
            'created_by': {'write_only': True, 'required': False}
        }

    def get_is_read(self, obj):
        # AlertViewSet.get_queryset annotates this as an Exists() subquery
        # so listing alerts stays a single query instead of N+1. Fall back
        # to a direct lookup for any other path that instantiates this
        # serializer without that annotation (e.g. a bare .get() call).
        if hasattr(obj, 'is_read_annotated'):
            return bool(obj.is_read_annotated)
        request = self.context.get('request')
        if not request or not request.user.is_authenticated:
            return False
        return obj.read_receipts.filter(user=request.user).exists()

class ChatSessionSerializer(serializers.ModelSerializer):
    class Meta:
        model = ChatSession
        fields = ['id', 'user', 'started_at']
        extra_kwargs = {'user': {'read_only': True}}

class ChatMessageSerializer(serializers.ModelSerializer):
    class Meta:
        model = ChatMessage
        fields = [
            'id', 'session', 'sender', 'message_text', 
            'cited_document', 'is_helpful', 'created_at'
        ]

# ---------------------------------------------------------
# NAYA SERIALIZER: AUDIT LOG KE LIYE
# ---------------------------------------------------------
class AuditLogSerializer(serializers.ModelSerializer):
    user_details = UserMinimalSerializer(source='user', read_only=True)
    module = serializers.CharField(source='entity_type', read_only=True)
    details = serializers.SerializerMethodField()

    class Meta:
        model = AuditLog
        fields = [
            'id', 'action', 'module', 'details', 'ip_address', 
            'created_at', 'user', 'user_details'
        ]

    def get_details(self, obj):
        """Resolves entity_id into the actual name of whatever was acted
        on, rather than a bare (truncated) UUID that means nothing to an
        admin reading the log. Falls back to the ID if the target has
        since been deleted, so the row is still informative.
        """
        if not obj.entity_id:
            return "System action"

        if obj.entity_type == "User":
            target = User.objects.filter(id=obj.entity_id).first()
            if target:
                return target.full_name
        elif obj.entity_type == "Document":
            target = Document.objects.filter(id=obj.entity_id).first()
            if target:
                return target.title
        elif obj.entity_type == "SystemSettings":
            return "System Settings"

        # Target no longer exists (deleted since), or an entity_type we
        # don't have a name lookup for yet — fall back to a truncated ID
        # rather than crashing or showing nothing.
        return f"{obj.entity_type} (deleted) — {str(obj.entity_id)[:8]}..."


# ---------------------------------------------------------
# System Settings — real, enforced config (see SystemSettings model
# for exactly where each field is read on the backend).
# ---------------------------------------------------------
class SystemSettingsSerializer(serializers.ModelSerializer):
    updated_by_details = UserMinimalSerializer(source='updated_by', read_only=True)

    class Meta:
        model = SystemSettings
        fields = [
            'allow_worker_downloads',
            'enable_file_preview',
            'show_inactive_by_default',
            'enable_document_versioning',
            'default_page_size',
            'updated_by_details',
            'updated_at',
        ]
        read_only_fields = ['updated_by_details', 'updated_at']

    def validate_default_page_size(self, value):
        if not (5 <= value <= 100):
            raise serializers.ValidationError("Must be between 5 and 100.")
        return value