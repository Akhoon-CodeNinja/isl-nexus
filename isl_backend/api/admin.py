from django.contrib import admin
from django.contrib.auth.admin import UserAdmin as DjangoUserAdmin

from .models import (
    Alert,
    AuditLog,
    ChatMessage,
    ChatSession,
    Department,
    Document,
    DocumentTag,
    Tag,
    User,
    UserAlertRead,
)


@admin.register(Department)
class DepartmentAdmin(admin.ModelAdmin):
    list_display = ("name", "code", "created_at")
    search_fields = ("name", "code")
    ordering = ("name",)


@admin.register(User)
class UserAdmin(DjangoUserAdmin):
    """Custom admin for the ISL User model.

    We don't inherit the default `fieldsets`/`add_fieldsets` from
    `DjangoUserAdmin` as-is because the field set differs (no
    username/first_name/last_name, custom `employee_id` login field),
    so both are redefined explicitly below.
    """

    model = User
    list_display = (
        "employee_id", "full_name", "email", "role",
        "department", "is_active", "is_staff", "last_login",
    )
    list_filter = ("role", "department", "is_active", "is_staff")
    search_fields = ("employee_id", "full_name", "email")
    ordering = ("full_name",)

    fieldsets = (
        (None, {"fields": ("employee_id", "password")}),
        ("Personal info", {"fields": ("full_name", "email", "department", "shift_timing")}),
        ("Role & permissions", {
            "fields": (
                "role", "is_active", "is_staff", "is_superuser",
                "groups", "user_permissions",
            ),
        }),
        ("Important dates", {"fields": ("last_login", "date_joined")}),
    )
    add_fieldsets = (
        (None, {
            "classes": ("wide",),
            "fields": (
                "employee_id", "email", "full_name", "role",
                "department", "password1", "password2",
            ),
        }),
    )


class DocumentTagInline(admin.TabularInline):
    model = DocumentTag
    extra = 1


@admin.register(Document)
class DocumentAdmin(admin.ModelAdmin):
    list_display = (
        "title", "doc_number", "department_list", "file_type", "version",
        "approval_status", "is_active", "uploaded_by", "created_at",
    )
    list_filter = ("departments", "file_type", "approval_status", "is_active")
    search_fields = ("title", "doc_number")
    autocomplete_fields = ("departments", "uploaded_by")
    readonly_fields = ("created_at", "updated_at")
    inlines = [DocumentTagInline]
    date_hierarchy = "created_at"

    @admin.display(description="Departments")
    def department_list(self, obj):
        # M2M fields can't be plugged into list_display directly (that's
        # exactly the E108 error) — Admin needs a single displayable
        # value, so this joins every linked department's name into one
        # string for the column.
        return ", ".join(d.name for d in obj.departments.all())


@admin.register(Tag)
class TagAdmin(admin.ModelAdmin):
    list_display = ("name", "department")
    list_filter = ("department",)
    search_fields = ("name",)
    autocomplete_fields = ("department",)


@admin.register(Alert)
class AlertAdmin(admin.ModelAdmin):
    list_display = ("title", "type", "target_department", "created_by", "created_at")
    list_filter = ("type", "target_department")
    search_fields = ("title", "description")
    autocomplete_fields = ("target_department", "created_by")
    date_hierarchy = "created_at"


@admin.register(UserAlertRead)
class UserAlertReadAdmin(admin.ModelAdmin):
    list_display = ("alert", "user", "read_at")
    list_filter = ("read_at",)
    autocomplete_fields = ("alert", "user")


@admin.register(ChatSession)
class ChatSessionAdmin(admin.ModelAdmin):
    list_display = ("id", "user", "started_at")
    list_filter = ("started_at",)
    search_fields = ("id", "user__employee_id", "user__full_name")
    autocomplete_fields = ("user",)
    date_hierarchy = "started_at"


@admin.register(ChatMessage)
class ChatMessageAdmin(admin.ModelAdmin):
    list_display = ("session", "sender", "short_text", "cited_document", "is_helpful", "created_at")
    list_filter = ("sender", "is_helpful")
    search_fields = ("message_text",)
    autocomplete_fields = ("session", "cited_document")
    date_hierarchy = "created_at"

    @admin.display(description="Message")
    def short_text(self, obj):
        return (obj.message_text[:60] + "…") if len(obj.message_text) > 60 else obj.message_text


@admin.register(AuditLog)
class AuditLogAdmin(admin.ModelAdmin):
    list_display = ("action", "entity_type", "entity_id", "user", "ip_address", "created_at")
    list_filter = ("entity_type", "action")
    search_fields = ("action", "entity_type", "ip_address")
    autocomplete_fields = ("user",)
    date_hierarchy = "created_at"
    readonly_fields = [f.name for f in AuditLog._meta.fields]

    def has_add_permission(self, request):
        # Audit logs are written by the system only, never manually.
        return False

    def has_change_permission(self, request, obj=None):
        return False