"""
Core domain models for the ISL Enterprise & AI Assistant Platform.

Design notes
------------
- Every model uses a UUID primary key (`id`) instead of the default
  auto-incrementing integer. This avoids exposing sequential/guessable
  IDs over the API and plays well with distributed/offline-first sync
  scenarios later.
- `db_index=True` is set on every foreign key and on fields that are
  frequently filtered/sorted on (e.g. `is_active`, `created_at`,
  `approval_status`) to keep the dashboard and chat queries fast as
  the tables grow.
- `related_name` is set explicitly everywhere so reverse relations
  read naturally from both sides (e.g. `department.documents`,
  `user.uploaded_documents`).
- Junction tables (`UserAlertRead`, `Document.tags` M2M) carry the
  `unique_together` / `through` constraints called out in the ERD.
"""

import uuid

from django.conf import settings
from django.contrib.auth.base_user import BaseUserManager
from django.contrib.auth.models import AbstractUser
from django.core.validators import MinLengthValidator
from django.db import models


class UUIDModel(models.Model):
    """Abstract base: UUID primary key for every table in the schema."""

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)

    class Meta:
        abstract = True


# ---------------------------------------------------------------------------
# Departments
# ---------------------------------------------------------------------------
class Department(UUIDModel):
    name = models.CharField(max_length=150)
    code = models.CharField(max_length=20, unique=True, db_index=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = "departments"
        ordering = ["name"]
        verbose_name = "Department"
        verbose_name_plural = "Departments"

    def __str__(self) -> str:
        return f"{self.name} ({self.code})"


# ---------------------------------------------------------------------------
# Custom User (RBAC)
# ---------------------------------------------------------------------------
class UserManager(BaseUserManager):
    """Custom manager keying auth on `employee_id` instead of `username`.

    Inherits from Django's `BaseUserManager` (not the plain `models.Manager`)
    because `createsuperuser`, `authenticate()`, and Django Admin login all
    rely on manager methods that only `BaseUserManager` provides —
    `get_by_natural_key()` and `normalize_email()` in particular.
    """

    use_in_migrations = True

    def _create_user(self, employee_id, email, password=None, **extra_fields):
        if not employee_id:
            raise ValueError("Employee ID is required.")
        if not email:
            raise ValueError("Email is required.")
        email = self.normalize_email(email)
        user = self.model(employee_id=employee_id, email=email, **extra_fields)
        user.set_password(password)
        user.save(using=self._db)
        return user

    def create_user(self, employee_id, email, password=None, **extra_fields):
        extra_fields.setdefault("is_staff", False)
        extra_fields.setdefault("is_superuser", False)
        return self._create_user(employee_id, email, password, **extra_fields)

    def create_superuser(self, employee_id, email, password=None, **extra_fields):
        extra_fields.setdefault("is_staff", True)
        extra_fields.setdefault("is_superuser", True)
        extra_fields.setdefault("role", User.Role.DEPARTMENT_HEAD)
        extra_fields.setdefault("is_active", True)

        if extra_fields.get("is_staff") is not True:
            raise ValueError("Superuser must have is_staff=True.")
        if extra_fields.get("is_superuser") is not True:
            raise ValueError("Superuser must have is_superuser=True.")

        return self._create_user(employee_id, email, password, **extra_fields)

    def get_by_natural_key(self, employee_id):
        return self.get(**{f"{self.model.USERNAME_FIELD}__iexact": employee_id})


class User(AbstractUser, UUIDModel):
    """Custom user model, authenticated by `employee_id` (not username/email).

    Inherits Django's built-in auth scaffolding (password hashing,
    permissions, groups, `is_staff`/`is_superuser` for Django Admin
    access) via `AbstractUser`, while replacing the identity fields
    to match the ISL ERD.
    """

    class Role(models.TextChoices):
        DEPARTMENT_HEAD = "DEPARTMENT_HEAD", "Department Head"
        WORKER = "WORKER", "Worker"

    # Drop the fields AbstractUser ships with that we don't use, and
    # neutralize `username` since `employee_id` is our USERNAME_FIELD.
    username = models.CharField(max_length=150, unique=False, blank=True, null=True)
    first_name = None
    last_name = None

    employee_id = models.CharField(
        max_length=30, unique=True, db_index=True,
        validators=[MinLengthValidator(2)],
        help_text="Unique company employee code, used to sign in.",
    )
    email = models.EmailField(unique=True, db_index=True)
    full_name = models.CharField(max_length=150)
    role = models.CharField(
        max_length=20, choices=Role.choices, default=Role.WORKER, db_index=True,
    )
    shift_timing = models.CharField(max_length=50, blank=True, null=True)
    department = models.ForeignKey(
        Department,
        on_delete=models.SET_NULL,
        null=True, blank=True,
        related_name="users",
        db_column="department_id",
    )
    is_active = models.BooleanField(default=True, db_index=True)
    last_login = models.DateTimeField(null=True, blank=True)

    objects = UserManager()

    USERNAME_FIELD = "employee_id"
    REQUIRED_FIELDS = ["email", "full_name"]

    class Meta:
        db_table = "users"
        ordering = ["full_name"]
        verbose_name = "User"
        verbose_name_plural = "Users"

    def __str__(self) -> str:
        return f"{self.full_name} ({self.employee_id})"

    @property
    def is_department_head(self) -> bool:
        return self.role == self.Role.DEPARTMENT_HEAD


# ---------------------------------------------------------------------------
# Tags & Documents (department-wise knowledge base)
# ---------------------------------------------------------------------------
class Tag(UUIDModel):
    name = models.CharField(max_length=80)
    department = models.ForeignKey(
        Department,
        on_delete=models.CASCADE,
        related_name="tags",
        db_column="department_id",
    )

    class Meta:
        db_table = "tags"
        ordering = ["name"]
        unique_together = ("name", "department")
        verbose_name = "Tag"
        verbose_name_plural = "Tags"

    def __str__(self) -> str:
        return f"{self.name} [{self.department.code}]"


class Document(UUIDModel):
    class FileType(models.TextChoices):
        PDF = "PDF", "PDF"
        DOCX = "DOCX", "DOCX"
        XLSX = "XLSX", "Excel"

    class ApprovalStatus(models.TextChoices):
        PENDING = "PENDING", "Pending"
        APPROVED = "APPROVED", "Approved"
        REJECTED = "REJECTED", "Rejected"

    title = models.CharField(max_length=255, db_index=True)
    doc_number = models.CharField(max_length=50, unique=True, db_index=True)
    file_url = models.FileField(upload_to="documents/%Y/%m/")
    file_type = models.CharField(max_length=10, choices=FileType.choices)
    version = models.CharField(max_length=20, default="1.0")

    # Multi-department documents: one document can now be linked to more
    # than one department at once. Any employee in ANY of the linked
    # departments can see it — see DocumentViewSet.get_queryset (WORKER
    # branch) in views.py for where that's enforced.
    departments = models.ManyToManyField(
        Department,
        related_name="documents",
        db_table="documents_departments",
    )
    uploaded_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        related_name="uploaded_documents",
        db_column="uploaded_by",
    )
    tags = models.ManyToManyField(
        Tag,
        through="DocumentTag",
        related_name="documents",
        blank=True,
    )

    approval_status = models.CharField(
        max_length=10,
        choices=ApprovalStatus.choices,
        default=ApprovalStatus.PENDING,
        db_index=True,
    )
    is_active = models.BooleanField(default=False, db_index=True)

    created_at = models.DateTimeField(auto_now_add=True, db_index=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "documents"
        ordering = ["-created_at"]
        verbose_name = "Document"
        verbose_name_plural = "Documents"
        indexes = [
            models.Index(fields=["approval_status", "is_active"]),
        ]

    def __str__(self) -> str:
        return f"{self.title} (v{self.version})"


class DocumentTag(UUIDModel):
    """Explicit through-table for Document <-> Tag (matches the ERD's
    `documents_tags` junction with a composite (document_id, tag_id) key)."""

    document = models.ForeignKey(
        Document, on_delete=models.CASCADE, db_column="document_id",
        related_name="document_tag_links",
    )
    tag = models.ForeignKey(
        Tag, on_delete=models.CASCADE, db_column="tag_id",
        related_name="tag_document_links",
    )

    class Meta:
        db_table = "documents_tags"
        unique_together = ("document", "tag")
        verbose_name = "Document Tag"
        verbose_name_plural = "Document Tags"

    def __str__(self) -> str:
        return f"{self.document.title} -> {self.tag.name}"


# ---------------------------------------------------------------------------
# Alerts system
# ---------------------------------------------------------------------------
class Alert(UUIDModel):
    class AlertType(models.TextChoices):
        EMERGENCY = "EMERGENCY", "Emergency"
        SAFETY = "SAFETY", "Safety"
        ANNOUNCEMENT = "ANNOUNCEMENT", "Announcement"
        MAINTENANCE = "MAINTENANCE", "Maintenance"

    title = models.CharField(max_length=255)
    description = models.TextField()
    type = models.CharField(max_length=20, choices=AlertType.choices, db_index=True)

    target_department = models.ForeignKey(
        Department,
        on_delete=models.CASCADE,
        null=True, blank=True,
        related_name="alerts",
        db_column="target_department_id",
        help_text="Null means the alert is broadcast to all departments.",
    )
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        related_name="created_alerts",
        db_column="created_by",
    )
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)

    # Junction handled via the through model below, mirroring the ERD.
    read_by = models.ManyToManyField(
        settings.AUTH_USER_MODEL,
        through="UserAlertRead",
        related_name="read_alerts",
        blank=True,
    )

    class Meta:
        db_table = "alerts"
        ordering = ["-created_at"]
        verbose_name = "Alert"
        verbose_name_plural = "Alerts"
        indexes = [
            models.Index(fields=["type", "target_department"]),
        ]

    def __str__(self) -> str:
        return f"[{self.type}] {self.title}"


class UserAlertRead(UUIDModel):
    """Junction model tracking which users have read which alerts.

    Matches the ERD's `users_alret_reads` table, with a composite
    uniqueness constraint on (alert, user) so an alert can only be
    marked read once per user.
    """

    alert = models.ForeignKey(
        Alert, on_delete=models.CASCADE, db_column="alert_id",
        related_name="read_receipts",
    )
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, db_column="user_id",
        related_name="alert_read_receipts",
    )
    read_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = "users_alert_reads"
        unique_together = ("alert", "user")
        verbose_name = "User Alert Read"
        verbose_name_plural = "User Alert Reads"

    def __str__(self) -> str:
        return f"{self.user.employee_id} read {self.alert_id}"


# ---------------------------------------------------------------------------
# AI Chat Assistant (RAG)
# ---------------------------------------------------------------------------
class ChatSession(UUIDModel):
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="chat_sessions",
        db_column="user_id",
    )
    started_at = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        db_table = "chat_sessions"
        ordering = ["-started_at"]
        verbose_name = "Chat Session"
        verbose_name_plural = "Chat Sessions"

    def __str__(self) -> str:
        return f"Session {self.id} - {self.user.employee_id}"


class ChatMessage(UUIDModel):
    class Sender(models.TextChoices):
        USER = "USER", "User"
        AI = "AI", "AI"

    session = models.ForeignKey(
        ChatSession,
        on_delete=models.CASCADE,
        related_name="messages",
        db_column="session_id",
    )
    sender = models.CharField(max_length=10, choices=Sender.choices, db_index=True)
    message_text = models.TextField()

    cited_document = models.ForeignKey(
        Document,
        on_delete=models.SET_NULL,
        null=True, blank=True,
        related_name="cited_in_messages",
        db_column="cited_document_id",
        help_text="Source document the AI cited (RAG grounding), if any.",
    )
    is_helpful = models.BooleanField(
        null=True, blank=True,
        help_text="Worker feedback on the AI response: True=helpful, "
                   "False=not helpful, Null=no feedback given.",
    )
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        db_table = "chat_messages"
        ordering = ["created_at"]
        verbose_name = "Chat Message"
        verbose_name_plural = "Chat Messages"
        indexes = [
            models.Index(fields=["session", "created_at"]),
        ]

    def __str__(self) -> str:
        preview = (self.message_text[:40] + "…") if len(self.message_text) > 40 else self.message_text
        return f"[{self.sender}] {preview}"


# ---------------------------------------------------------------------------
# Audit Logs
# ---------------------------------------------------------------------------
class AuditLog(UUIDModel):
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True, blank=True,
        related_name="audit_logs",
        db_column="user_id",
    )
    action = models.CharField(max_length=100, db_index=True)
    entity_type = models.CharField(max_length=100, db_index=True)
    entity_id = models.UUIDField(null=True, blank=True, db_index=True)
    ip_address = models.GenericIPAddressField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        db_table = "audit_logs"
        ordering = ["-created_at"]
        verbose_name = "Audit Log"
        verbose_name_plural = "Audit Logs"
        indexes = [
            models.Index(fields=["entity_type", "entity_id"]),
        ]

    def __str__(self) -> str:
        return f"{self.action} on {self.entity_type} by {self.user_id}"


# ---------------------------------------------------------------------------
# System Settings (singleton — always exactly one row)
# ---------------------------------------------------------------------------
class SystemSettings(models.Model):
    """Platform-wide configuration, editable from the admin Settings screen.

    Deliberately excludes purely cosmetic fields (company name, clock
    format, UI language) that don't drive any real backend behavior —
    every field on this model is read by at least one view or
    permission check elsewhere in this file/app. See DocumentViewSet
    in views.py for where each of these is actually enforced.
    """

    allow_worker_downloads = models.BooleanField(
        default=True,
        help_text="If off, the download action returns 403 for Workers "
                   "regardless of department.",
    )
    enable_file_preview = models.BooleanField(
        default=True,
        help_text="If off, the inline document preview action is disabled "
                   "for everyone, Department Heads included.",
    )
    show_inactive_by_default = models.BooleanField(
        default=False,
        help_text="Whether Department Heads see inactive documents by "
                   "default in list views. Always overridable per-request "
                   "with ?show_inactive=true|false. Never applies to "
                   "Workers, who never see inactive documents regardless.",
    )
    enable_document_versioning = models.BooleanField(
        default=True,
        help_text="If on, replacing a document's file via the 'replace' "
                   "action auto-increments its version number instead of "
                   "keeping the version string unchanged.",
    )
    default_page_size = models.PositiveSmallIntegerField(
        default=20,
        help_text="Default items-per-page for list endpoints when the "
                   "client doesn't pass ?page_size=.",
    )

    updated_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True, blank=True,
        related_name="+",
    )
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "system_settings"
        verbose_name = "System Settings"
        verbose_name_plural = "System Settings"

    def __str__(self) -> str:
        return "ISL System Settings"

    @classmethod
    def load(cls) -> "SystemSettings":
        """Always returns the single settings row, creating it with
        defaults on first access."""
        obj, _ = cls.objects.get_or_create(pk=1)
        return obj

    def save(self, *args, **kwargs):
        self.pk = 1  # enforce singleton — there is only ever one row
        super().save(*args, **kwargs)

    def delete(self, *args, **kwargs):
        pass  # the singleton row is never deletable via the ORM