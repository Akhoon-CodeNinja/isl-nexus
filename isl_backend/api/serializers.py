from rest_framework_simplejwt.serializers import TokenObtainPairSerializer
from rest_framework import serializers
from django.contrib.auth import get_user_model
from .models import Department, Tag, Document, Alert, ChatSession, ChatMessage, AuditLog, SystemSettings, NotificationTemplate

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

        data['user'] = {
            'id': str(self.user.id),
            'full_name': self.user.full_name,
            'role': self.user.role,
            'department_details': department_details,
            'shift_timing': self.user.shift_timing or '',
            'can_manage_docs': self.user.can_manage_docs,
        }

        return data

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
            'shift_timing', 'can_manage_docs', 'chat_daily_limit_override'
        ]

class MeSerializer(serializers.ModelSerializer):
    department_details = DepartmentSerializer(source='department', read_only=True)

    class Meta:
        model = User
        fields = [
            'id', 'employee_id', 'full_name', 'email', 'role',
            'department_details', 'is_active', 'last_login', 'date_joined',
            'shift_timing','can_manage_docs', 'chat_daily_limit_override'
        ]
        read_only_fields = [
            'id', 'employee_id', 'role', 'department_details',
            'is_active', 'last_login', 'date_joined', 'shift_timing',
            'chat_daily_limit_override',
        ]

class TagSerializer(serializers.ModelSerializer):
    class Meta:
        model = Tag
        fields = ['id', 'name', 'department']

class DocumentSerializer(serializers.ModelSerializer):
    uploaded_by_details = UserMinimalSerializer(source='uploaded_by', read_only=True)
    departments_details = DepartmentSerializer(source='departments', many=True, read_only=True)
    tags_details = TagSerializer(source='tags', many=True, read_only=True)

    class Meta:
        model = Document
        fields = [
            'id', 'title', 'doc_number', 'file_url', 'file_type', 'version', 
            'approval_status', 'is_active', 'include_in_chatbot', 'created_at', 'updated_at',
            'uploaded_by', 'uploaded_by_details', 
            'departments_details',
            'tags', 'tags_details'
        ]
        extra_kwargs = {
            'uploaded_by': {'write_only': True, 'required': False},
            'is_active': {'read_only': True}, # NAYA CHANGE: User upload time is_active set nahi kar sakta
            # Read-only here on purpose: this is exposed for display, but can
            # only be changed via the dedicated `chatbot_inclusion` action
            # below (Department Head / Admin only), not via a plain
            # create/update call -- see DocumentViewSet.chatbot_inclusion.
            'include_in_chatbot': {'read_only': True},
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
        if hasattr(obj, 'is_read_annotated'):
            return bool(obj.is_read_annotated)
        request = self.context.get('request')
        if not request or not request.user.is_authenticated:
            return False
        return obj.read_receipts.filter(user=request.user).exists()

class LeaveApplicationSerializer(serializers.Serializer):
    LEAVE_TYPE_CHOICES = (
        ("SICK", "Sick Leave"),
        ("CASUAL", "Casual Leave"),
        ("ANNUAL", "Annual Leave"),
    )
    leave_type = serializers.ChoiceField(choices=LEAVE_TYPE_CHOICES)
    reason = serializers.CharField(required=False, allow_blank=True, max_length=1000)

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

        return f"{obj.entity_type} (deleted) — {str(obj.entity_id)[:8]}..."

class NotificationTemplateSerializer(serializers.ModelSerializer):
    created_by_details = UserMinimalSerializer(source='created_by', read_only=True)

    class Meta:
        model = NotificationTemplate
        fields = [
            'id', 'title', 'body', 'type', 'status',
            'created_by_details', 'created_at', 'updated_at',
        ]
        extra_kwargs = {
            'status': {'read_only': True},  # only settable via set_status action, or NEW on create
        }

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