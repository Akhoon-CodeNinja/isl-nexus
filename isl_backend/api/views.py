from rest_framework import viewsets, permissions, generics
from rest_framework.views import APIView
from rest_framework.parsers import MultiPartParser, FormParser
from rest_framework_simplejwt.views import TokenObtainPairView
from rest_framework_simplejwt.authentication import JWTAuthentication
from rest_framework_simplejwt.tokens import RefreshToken
from rest_framework.exceptions import AuthenticationFailed, PermissionDenied, ValidationError
from django.contrib.auth import get_user_model
from django.db.models import Q, Exists, OuterRef, Count
from django.http import FileResponse, Http404
from django.utils import timezone
from datetime import timedelta
import os
import requests
import mimetypes
from rest_framework.response import Response
from rest_framework import status as http_status
from rest_framework.decorators import action

from .models import Department, Document, Tag, Alert, ChatSession, ChatMessage, UserAlertRead, AuditLog, SystemSettings
from .serializers import (
    CustomTokenObtainPairSerializer, DepartmentSerializer, DocumentSerializer, 
    TagSerializer, AlertSerializer, ChatSessionSerializer, ChatMessageSerializer,
    UserListSerializer, MeSerializer, AuditLogSerializer, SystemSettingsSerializer,
    LeaveApplicationSerializer
)
from .permissions import IsDepartmentHeadOrReadOnly
from .services import ISLChatBotService

chatbot_service = ISLChatBotService()


def sync_vector_store():
    docs = Document.objects.filter(
        is_active=True,
    )
    file_paths = [d.file_url.path for d in docs if d.file_url]

    try:
        chatbot_service.rebuild_index_from_paths(file_paths)
    except Exception as e:
        print(f"[sync_vector_store] Warning: FAISS index rebuild failed: {e}")

def get_daily_limit(user):
    return 100 if user.role == 'DEPARTMENT_HEAD' else 30

def get_remaining_messages_today(user) -> int:
    today = timezone.localdate()
    sent_today = ChatMessage.objects.filter(
        session__user=user, sender=ChatMessage.Sender.USER, created_at__date=today
    ).count()
    return max(0, get_daily_limit(user) - sent_today)

class SystemSyncStatusView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        filepath = "faiss_index/sync_timestamp.txt"
        if os.path.exists(filepath):
            with open(filepath, "r") as f:
                last_sync = f.read().strip()
            return Response({"status": "Synced", "last_sync": last_sync})
        return Response({"status": "Pending", "last_sync": None})


class ChatAskView(APIView):
    permission_classes = [permissions.IsAuthenticated] 
    SESSION_HISTORY_WINDOW = 50

    def _get_or_create_session(self, user):
        session = ChatSession.objects.filter(user=user).order_by('-started_at').first()
        if session is None:
            session = ChatSession.objects.create(user=user)
        return session

    def post(self, request):
        user = request.user
        query = request.data.get('query') or request.data.get('message', '')
        query = query.strip() if query else ''

        if not query:
            return Response({"answer": "Sawal khali hai, baraye meharbani sawal likhein.", "references": []})

        session = self._get_or_create_session(user)

        today = timezone.localdate()
        messages_sent_today = ChatMessage.objects.filter(
            session__user=user, sender=ChatMessage.Sender.USER, created_at__date=today,
        ).count()

        user_daily_limit = get_daily_limit(user)

        if messages_sent_today >= user_daily_limit:
            return Response({
                "answer": f"Aaj ke liye aapki message limit ({user_daily_limit} messages) mukammal ho chuki hai. Baraye meharbani kal dobara koshish karein.",
                "intent": "LIMIT_REACHED",
                "references": [],
                "remaining_messages_today": 0,
            })

        ChatMessage.objects.create(session=session, sender=ChatMessage.Sender.USER, message_text=query)

        try:
            result = chatbot_service.process_query(query)
            reply = result["answer"]
            intent = result["intent"]

            ChatMessage.objects.create(session=session, sender=ChatMessage.Sender.AI, message_text=reply)
            remaining = max(0, user_daily_limit - (messages_sent_today + 1))

            return Response({
                "answer": reply, "intent": intent, "references": [],
                "success": True, "remaining_messages_today": remaining,
            })
        except Exception as e:
            error_reply = f"System mein koi masla aaya hai: {str(e)}"
            ChatMessage.objects.create(session=session, sender=ChatMessage.Sender.AI, message_text=error_reply)
            return Response({"answer": error_reply, "references": []}, status=500)

class ChatNewSessionView(APIView):
    permission_classes = [permissions.IsAuthenticated]
    def post(self, request):
        session = ChatSession.objects.create(user=request.user)
        return Response({
            "session_id": str(session.id), "daily_limit": get_daily_limit(request.user),
            "remaining_messages_today": get_remaining_messages_today(request.user),
        }, status=http_status.HTTP_201_CREATED)

class ChatSessionListView(APIView):
    permission_classes = [permissions.IsAuthenticated]
    def get(self, request):
        sessions = ChatSession.objects.filter(user=request.user).order_by('-started_at')
        data = []
        for s in sessions:
            first_msg = s.messages.order_by('created_at').first()
            last_msg = s.messages.order_by('-created_at').first()
            if first_msg is None: continue
            data.append({
                "session_id": str(s.id), "preview": first_msg.message_text[:80],
                "started_at": s.started_at.isoformat(),
                "last_message_at": (last_msg.created_at if last_msg else s.started_at).isoformat(),
                "message_count": s.messages.count(),
            })
        return Response({"sessions": data})

class ChatHistoryView(APIView):
    permission_classes = [permissions.IsAuthenticated]
    def get(self, request):
        user = request.user
        session_id = request.query_params.get('session_id')
        if session_id:
            session = ChatSession.objects.filter(user=user, id=session_id).first()
        else:
            session = ChatSession.objects.filter(user=user).order_by('-started_at').first()
        if session is None:
            return Response({
                "messages": [], "session_id": None, "daily_limit": get_daily_limit(user),
                "remaining_messages_today": get_remaining_messages_today(user),
            })
        try:
            limit = int(request.query_params.get('limit', ChatAskView.SESSION_HISTORY_WINDOW))
        except (TypeError, ValueError):
            limit = ChatAskView.SESSION_HISTORY_WINDOW
        limit = max(1, min(limit, 1000))
        messages = list(session.messages.order_by('-created_at')[:limit])
        messages.reverse()
        return Response({
            "session_id": str(session.id), "daily_limit": get_daily_limit(user),
            "remaining_messages_today": get_remaining_messages_today(user),
            "messages": [
                {"id": str(m.id), "sender": m.sender, "text": m.message_text, "created_at": m.created_at.isoformat()}
                for m in messages
            ],
        })

class LeaveApplicationView(APIView):
    permission_classes = [permissions.IsAuthenticated]
    LEAVE_TYPE_LABELS = dict(LeaveApplicationSerializer.LEAVE_TYPE_CHOICES)

    def post(self, request):
        user = request.user
        serializer = LeaveApplicationSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        leave_type = serializer.validated_data['leave_type']
        reason = serializer.validated_data.get('reason', '').strip()
        leave_type_label = self.LEAVE_TYPE_LABELS.get(leave_type, leave_type)

        if not reason:
            reason = f"{user.full_name} {leave_type_label.lower()} ke liye darkhwast kar rahe/rahi hain. Baraye meharbani manzoori dein."

        application_text = (
            f"Application Text:\n\nRespected Sir/Madam,\n\n"
            f"Mera naam {user.full_name} hai (Employee ID: {user.employee_id}). "
            f"Main {leave_type_label} ke liye darkhwast kar raha/rahi hoon.\n\n"
            f"Wajah: {reason}\n\nBaraye meharbani meri darkhwast manzoor karein.\n\n"
            f"Shukriya,\n{user.full_name}"
        )

        alert = Alert.objects.create(
            title=f"Leave Application - {user.full_name} ({leave_type_label})",
            description=application_text, type=Alert.AlertType.LEAVE_REQUEST,
            target_department=user.department, created_by=user,
        )

        AuditLog.objects.create(
            user=user, action="Submitted Leave Application", entity_type="Alert",
            entity_id=alert.id, ip_address=get_client_ip(request),
        )

        return Response({
            "success": True, "alert_id": str(alert.id), "application_text": application_text,
        }, status=http_status.HTTP_201_CREATED)

User = get_user_model()
def get_client_ip(request):
    x_forwarded_for = request.META.get('HTTP_X_FORWARDED_FOR')
    if x_forwarded_for: return x_forwarded_for.split(',')[0]
    return request.META.get('REMOTE_ADDR')

def _bump_version(current: str) -> str:
    try:
        major, _, minor = current.partition('.')
        minor_num = int(minor) if minor.isdigit() else 0
        return f"{major}.{minor_num + 1}"
    except Exception: return f"{current}.1"

class CustomTokenObtainPairView(TokenObtainPairView):
    serializer_class = CustomTokenObtainPairSerializer

class MeView(generics.RetrieveUpdateAPIView):
    serializer_class = MeSerializer
    permission_classes = [permissions.IsAuthenticated]
    def get_object(self): return self.request.user

class MicrosoftLoginView(APIView):
    permission_classes = [permissions.AllowAny]
    GRAPH_ME_URL = "https://graph.microsoft.com/v1.0/me"
    GRAPH_TIMEOUT_SECONDS = 10

    def post(self, request):
        ms_access_token = request.data.get('access_token')
        if not ms_access_token:
            return Response({"detail": "Microsoft Access Token is required."}, status=http_status.HTTP_400_BAD_REQUEST)

        try:
            graph_res = requests.get(self.GRAPH_ME_URL, headers={"Authorization": f"Bearer {ms_access_token}"}, timeout=self.GRAPH_TIMEOUT_SECONDS)
        except requests.exceptions.RequestException:
            return Response({"detail": "Could not reach Microsoft's login service. Please try again."}, status=http_status.HTTP_503_SERVICE_UNAVAILABLE)

        if graph_res.status_code != 200:
            return Response({"detail": "Invalid or expired Microsoft token."}, status=http_status.HTTP_401_UNAUTHORIZED)

        ms_data = graph_res.json()
        email = ms_data.get('userPrincipalName') or ms_data.get('mail')
        full_name = ms_data.get('displayName', 'ISL Employee')

        if not email:
            return Response({"detail": "Could not retrieve email from Microsoft account."}, status=http_status.HTTP_400_BAD_REQUEST)

        user = User.objects.filter(email__iexact=email).first()
        created = False
        if not user:
            employee_id = email.split('@')[0].upper()
            user = User.objects.create_user(employee_id=employee_id, email=email, full_name=full_name, password=User.objects.make_random_password(), role='WORKER')
            created = True

        refresh = RefreshToken.for_user(user)
        AuditLog.objects.create(
            user=user, action="Created Account via Microsoft SSO" if created else "Signed in via Microsoft SSO",
            entity_type="User", entity_id=user.id, ip_address=get_client_ip(request),
        )

        department_details = None
        department_name = None
        department_id = None
        if user.department:
            department_id = str(user.department.id)
            department_name = user.department.name
            department_details = {'id': department_id, 'name': department_name}

        return Response({
            'access': str(refresh.access_token), 'refresh': str(refresh), 'role': user.role,
            'full_name': user.full_name, 'department_id': department_id, 'department_name': department_name,
            'shift': user.shift_timing or '', 'user': {
                'id': str(user.id), 'full_name': user.full_name, 'role': user.role,
                'department_details': department_details, 'shift_timing': user.shift_timing or '',
            },
        })

class IsAdminUser(permissions.BasePermission):
    def has_permission(self, request, view):
        user = request.user
        return bool(user and user.is_authenticated and (user.is_superuser or getattr(user, 'role', None) == 'DEPARTMENT_HEAD'))

class DepartmentViewSet(viewsets.ReadOnlyModelViewSet):
    queryset = Department.objects.all()
    serializer_class = DepartmentSerializer
    permission_classes = [permissions.IsAuthenticated]

class UserViewSet(viewsets.ModelViewSet):
    serializer_class = UserListSerializer
    permission_classes = [IsAdminUser]

    def get_queryset(self):
        qs = User.objects.select_related('department').all().order_by('full_name')
        params = self.request.query_params
        search = params.get('search')
        if search: qs = qs.filter(Q(full_name__icontains=search) | Q(email__icontains=search) | Q(employee_id__icontains=search))
        department = params.get('department')
        if department: qs = qs.filter(department__name__iexact=department)
        role = params.get('role')
        if role: qs = qs.filter(role__iexact=role)
        status_param = params.get('status')
        if status_param:
            if status_param.lower() == 'active': qs = qs.filter(is_active=True)
            elif status_param.lower() == 'inactive': qs = qs.filter(is_active=False)
        return qs
        
    def create(self, request, *args, **kwargs):
        data = request.data
        full_name = data.get('full_name')
        email = data.get('email')
        role = data.get('role', 'WORKER')
        department_name = data.get('department')
        if not full_name or not email: return Response({"detail": "Full Name and Email are required."}, status=http_status.HTTP_400_BAD_REQUEST)
        department = None
        if department_name:
            department = Department.objects.filter(name__iexact=department_name).first()
            if not department: return Response({"detail": f"Department '{department_name}' not found."}, status=http_status.HTTP_400_BAD_REQUEST)

        employee_id = data.get('employee_id', email.split('@')[0].upper())
        password = data.get('password', 'Isl@12345')
        shift_timing = data.get('shift_timing', '')

        try:
            user = User.objects.create_user(employee_id=employee_id, email=email, password=password, full_name=full_name, role=role, department=department, shift_timing=shift_timing)
            AuditLog.objects.create(user=request.user, action="Created New User", entity_type="User", entity_id=user.id, ip_address=get_client_ip(request))
            serializer = self.get_serializer(user)
            return Response(serializer.data, status=http_status.HTTP_201_CREATED)
        except Exception as e: return Response({"detail": str(e)}, status=http_status.HTTP_400_BAD_REQUEST)

    def update(self, request, *args, **kwargs):
        instance = self.get_object()
        data = request.data
        full_name = data.get('full_name', instance.full_name)
        email = data.get('email', instance.email)
        department_name = data.get('department')
        shift_timing = data.get('shift_timing', instance.shift_timing)
        try:
            instance.full_name = full_name
            instance.email = email
            instance.shift_timing = shift_timing
            if department_name:
                dept = Department.objects.filter(name__iexact=department_name).first()
                if not dept: return Response({"detail": f"Department '{department_name}' not found."}, status=http_status.HTTP_400_BAD_REQUEST)
                instance.department = dept
            instance.save()
            AuditLog.objects.create(user=request.user, action=f"Updated User Details ({instance.full_name})", entity_type="User", entity_id=instance.id, ip_address=get_client_ip(request))
            serializer = self.get_serializer(instance)
            return Response(serializer.data)
        except Exception as e:
            if 'unique constraint' in str(e).lower() or 'duplicate key' in str(e).lower(): return Response({"detail": "This email is already in use by another user."}, status=http_status.HTTP_400_BAD_REQUEST)
            return Response({"detail": str(e)}, status=http_status.HTTP_400_BAD_REQUEST)

    @action(detail=True, methods=['patch'], permission_classes=[IsAdminUser])
    def status(self, request, pk=None):
        user_obj = self.get_object()
        if user_obj == request.user and not request.data.get('is_active', True): return Response({"detail": "You cannot deactivate your own account."}, status=http_status.HTTP_400_BAD_REQUEST)
        is_active = request.data.get('is_active')
        if is_active is None: return Response({"detail": "'is_active' is required."}, status=http_status.HTTP_400_BAD_REQUEST)
        user_obj.is_active = bool(is_active)
        user_obj.save(update_fields=['is_active'])
        AuditLog.objects.create(user=request.user, action="Activated User" if user_obj.is_active else "Deactivated User", entity_type="User", entity_id=user_obj.id, ip_address=get_client_ip(request))
        serializer = self.get_serializer(user_obj)
        return Response(serializer.data)
    
    @action(detail=True, methods=['patch'], permission_classes=[IsAdminUser])
    def change_role(self, request, pk=None):
        user_obj = self.get_object()
        new_role = request.data.get('role')
        if not new_role or new_role not in ['WORKER', 'DEPARTMENT_HEAD']: return Response({"detail": "Valid 'role' (WORKER or DEPARTMENT_HEAD) is required."}, status=http_status.HTTP_400_BAD_REQUEST)
        if user_obj == request.user: return Response({"detail": "You cannot change your own role."}, status=http_status.HTTP_400_BAD_REQUEST)
        old_role = user_obj.role
        user_obj.role = new_role
        user_obj.save(update_fields=['role'])
        AuditLog.objects.create(user=request.user, action=f"Changed user role from {old_role} to {new_role}", entity_type="User", entity_id=user_obj.id, ip_address=get_client_ip(request))
        serializer = self.get_serializer(user_obj)
        return Response(serializer.data)

    @action(detail=True, methods=['patch'], permission_classes=[IsAdminUser])
    def toggle_upload_access(self, request, pk=None):
        user_obj = self.get_object()
        if user_obj.role == 'DEPARTMENT_HEAD': return Response({"detail": "Department Heads inherently have full access."}, status=http_status.HTTP_400_BAD_REQUEST)
        can_manage = request.data.get('can_manage_docs')
        if can_manage is None: return Response({"detail": "'can_manage_docs' is required."}, status=http_status.HTTP_400_BAD_REQUEST)
        user_obj.can_manage_docs = bool(can_manage)
        user_obj.save(update_fields=['can_manage_docs'])
        AuditLog.objects.create(user=request.user, action=f"{'Granted' if user_obj.can_manage_docs else 'Revoked'} document upload access for {user_obj.full_name}", entity_type="User", entity_id=user_obj.id, ip_address=get_client_ip(request))
        serializer = self.get_serializer(user_obj)
        return Response(serializer.data)

class DocumentViewSet(viewsets.ModelViewSet):
    serializer_class = DocumentSerializer
    permission_classes = [IsDepartmentHeadOrReadOnly]

    def get_queryset(self):
        user = self.request.user
        if not user or not user.is_authenticated: return Document.objects.none()
        if user.role == 'DEPARTMENT_HEAD': return Document.objects.all()
        elif user.role == 'WORKER': return Document.objects.filter(departments__in=[user.department], is_active=True).distinct()
        return Document.objects.none()

    def perform_create(self, serializer):
        dept_ids_raw = self.request.data.get('departments', '')
        dept_ids = [d.strip() for d in dept_ids_raw.split(',') if d.strip()]

        if not dept_ids: raise ValidationError({"departments": "Select at least one department."})
        departments = Department.objects.filter(id__in=dept_ids)
        if departments.count() != len(set(dept_ids)): raise ValidationError({"departments": "One or more selected departments were not found."})

        # NAYA CHANGE: Role-based status & approval assignment
        user = self.request.user
        if user.role == 'DEPARTMENT_HEAD' or user.is_superuser:
            doc = serializer.save(uploaded_by=user, approval_status=Document.ApprovalStatus.APPROVED, is_active=True)
        else:
            doc = serializer.save(uploaded_by=user, approval_status=Document.ApprovalStatus.PENDING, is_active=False)

        doc.departments.set(departments)

        AuditLog.objects.create(
            user=self.request.user,
            action="Uploaded Document",
            entity_type="Document",
            entity_id=doc.id,
            ip_address=get_client_ip(self.request)
        )
        sync_vector_store()

    def perform_destroy(self, instance):
        AuditLog.objects.create(user=self.request.user, action="Deleted Document", entity_type="Document", entity_id=instance.id, ip_address=get_client_ip(self.request))
        instance.delete()
        sync_vector_store()

    @action(detail=True, methods=['patch'], permission_classes=[permissions.IsAuthenticated])
    def status(self, request, pk=None):
        document = self.get_object()
        user = request.user
        if not (user.is_superuser or document.uploaded_by_id == user.id): raise PermissionDenied("Only the user who uploaded this document can change its status.")
        is_active = request.data.get('is_active')
        if is_active is None: return Response({"detail": "'is_active' is required."}, status=http_status.HTTP_400_BAD_REQUEST)
        document.is_active = bool(is_active)
        document.save(update_fields=['is_active', 'updated_at'])
        AuditLog.objects.create(user=user, action="Activated Document" if document.is_active else "Deactivated Document", entity_type="Document", entity_id=document.id, ip_address=get_client_ip(request))
        sync_vector_store()
        serializer = self.get_serializer(document)
        return Response(serializer.data)

    @action(detail=True, methods=['post'], permission_classes=[permissions.IsAuthenticated], parser_classes=[MultiPartParser, FormParser])
    def replace(self, request, pk=None):
        document = self.get_object()
        user = request.user
        if not (user.is_superuser or document.uploaded_by_id == user.id): raise PermissionDenied("Only the user who uploaded this document can replace its file.")
        new_file = request.FILES.get('file')
        if not new_file: return Response({"detail": "No file provided under the 'file' field."}, status=http_status.HTTP_400_BAD_REQUEST)
        document.file_url = new_file
        if SystemSettings.load().enable_document_versioning: document.version = _bump_version(document.version)
        document.approval_status = Document.ApprovalStatus.PENDING
        document.save()
        AuditLog.objects.create(user=user, action="Replaced Document File", entity_type="Document", entity_id=document.id, ip_address=get_client_ip(request))
        sync_vector_store()
        serializer = self.get_serializer(document)
        return Response(serializer.data)

    @action(detail=True, methods=['post'], permission_classes=[IsAdminUser])
    def approve(self, request, pk=None):
        document = self.get_object()
        if document.approval_status == Document.ApprovalStatus.APPROVED: return Response({"detail": "This document is already approved."}, status=http_status.HTTP_400_BAD_REQUEST)
        document.approval_status = Document.ApprovalStatus.APPROVED
        document.is_active = True
        document.save(update_fields=['approval_status', 'is_active', 'updated_at'])
        department = document.departments.first()
        alert_msg = f"A new document '{document.title}' has been approved and is now available in the knowledge base."
        Alert.objects.create(title="New Document Approved", description=alert_msg, type=Alert.AlertType.GENERAL, target_department=department, created_by=request.user)
        sync_vector_store()
        AuditLog.objects.create(user=request.user, action="Approved Document", entity_type="Document", entity_id=document.id, ip_address=get_client_ip(request))
        serializer = self.get_serializer(document)
        return Response(serializer.data)

    # NAYA ACTION: Reject Document Workflow
    @action(detail=True, methods=['post'], permission_classes=[IsAdminUser])
    def reject(self, request, pk=None):
        document = self.get_object()
        if document.approval_status != Document.ApprovalStatus.PENDING:
            return Response({"detail": "Only pending documents can be rejected."}, status=http_status.HTTP_400_BAD_REQUEST)
            
        document.approval_status = Document.ApprovalStatus.REJECTED
        document.is_active = False
        document.save(update_fields=['approval_status', 'is_active', 'updated_at'])
        
        sync_vector_store()
        
        AuditLog.objects.create(
            user=request.user, action="Rejected Document", entity_type="Document",
            entity_id=document.id, ip_address=get_client_ip(request)
        )
        serializer = self.get_serializer(document)
        return Response(serializer.data)

    def _authenticate_url_token(self, request):
        if request.user and request.user.is_authenticated: return request.user
        token = request.GET.get('token')
        if not token: raise AuthenticationFailed("Authentication token is missing in URL.")
        try:
            jwt_auth = JWTAuthentication()
            validated_token = jwt_auth.get_validated_token(token)
            user = jwt_auth.get_user(validated_token)
            request.user = user 
            return user
        except Exception: raise AuthenticationFailed("Invalid or expired token.")

    @action(detail=True, methods=['get'], permission_classes=[permissions.AllowAny])
    def view(self, request, pk=None):
        user = self._authenticate_url_token(request)
        if not SystemSettings.load().enable_file_preview: raise PermissionDenied("Inline document preview is currently disabled by the administrator.")
        document = self.get_object()
        if document.file_url:
            file_handle = document.file_url.open('rb')
            response = FileResponse(file_handle, as_attachment=False)
            content_type, _ = mimetypes.guess_type(document.file_url.name)
            if content_type: response['Content-Type'] = content_type
            filename = document.file_url.name.split('/')[-1]
            response['Content-Disposition'] = f'inline; filename="{filename}"'
            return response
        raise Http404("File not found")

    @action(detail=True, methods=['get'], permission_classes=[permissions.AllowAny])
    def download(self, request, pk=None):
        user = self._authenticate_url_token(request)
        if user.role == 'WORKER' and not SystemSettings.load().allow_worker_downloads: raise PermissionDenied("Access Denied: Workers are not allowed to download documents.")
        document = self.get_object()
        if document.file_url:
            file_handle = document.file_url.open('rb')
            response = FileResponse(file_handle, as_attachment=True)
            filename = document.file_url.name.split('/')[-1]
            response['Content-Disposition'] = f'attachment; filename="{filename}"'
            AuditLog.objects.create(user=user, action="Downloaded Document", entity_type="Document", entity_id=document.id, ip_address=get_client_ip(request))
            return response
        raise Http404("File not found")

class TagViewSet(viewsets.ModelViewSet):
    serializer_class = TagSerializer
    permission_classes = [IsDepartmentHeadOrReadOnly]
    def get_queryset(self):
        department_id = self.request.query_params.get('department')
        if department_id: return Tag.objects.filter(department_id=department_id).order_by('name')
        return Tag.objects.filter(department=self.request.user.department).order_by('name')
    def perform_create(self, serializer):
        department = serializer.validated_data.get('department') or self.request.user.department
        serializer.save(department=department)

class AlertViewSet(viewsets.ModelViewSet):
    serializer_class = AlertSerializer
    permission_classes = [IsDepartmentHeadOrReadOnly]
    def get_queryset(self):
        user = self.request.user
        read_receipt = UserAlertRead.objects.filter(alert=OuterRef('pk'), user=user)
        return Alert.objects.filter(Q(target_department=user.department) | Q(target_department__isnull=True)).annotate(is_read_annotated=Exists(read_receipt))
    DUPLICATE_WINDOW_SECONDS = 30
    def perform_create(self, serializer):
        data = serializer.validated_data
        cutoff = timezone.now() - timedelta(seconds=self.DUPLICATE_WINDOW_SECONDS)
        is_duplicate = Alert.objects.filter(created_by=self.request.user, title=data.get('title'), description=data.get('description'), target_department=data.get('target_department'), created_at__gte=cutoff).exists()
        if is_duplicate: raise ValidationError("An identical alert was just created. Please wait a moment before submitting the same alert again.")
        serializer.save(created_by=self.request.user)
    @action(detail=True, methods=['post'], permission_classes=[permissions.IsAuthenticated])
    def mark_read(self, request, pk=None):
        alert = self.get_object()
        receipt, created = UserAlertRead.objects.get_or_create(alert=alert, user=request.user)
        if created: return Response({"status": "Success", "message": "Alert marked as read."})
        return Response({"status": "Ignored", "message": "Alert was already marked as read."})

class ChatSessionDetailView(APIView):
    permission_classes = [permissions.IsAuthenticated]
    def delete(self, request, session_id):
        try:
            session = ChatSession.objects.get(id=session_id, user=request.user)
            session.delete()
            return Response(status=http_status.HTTP_204_NO_CONTENT)
        except ChatSession.DoesNotExist: return Response({"error": "Chat not found"}, status=http_status.HTTP_404_NOT_FOUND)

class ChatMessageViewSet(viewsets.ModelViewSet):
    serializer_class = ChatMessageSerializer
    permission_classes = [permissions.IsAuthenticated]
    def get_queryset(self): return ChatMessage.objects.filter(session__user=self.request.user)

class AuditLogViewSet(viewsets.ReadOnlyModelViewSet):
    serializer_class = AuditLogSerializer
    permission_classes = [IsAdminUser] 
    def get_queryset(self):
        qs = AuditLog.objects.select_related('user').all().order_by('-created_at')
        params = self.request.query_params
        search = params.get('search')
        if search: qs = qs.filter(Q(user__full_name__icontains=search) | Q(action__icontains=search) | Q(entity_type__icontains=search))
        user_name = params.get('user')
        if user_name and user_name != 'All Users': qs = qs.filter(user__full_name__iexact=user_name)
        action = params.get('action')
        if action and action != 'All Actions': qs = qs.filter(action__icontains=action)
        module = params.get('module')
        if module and module != 'All Modules': qs = qs.filter(entity_type__icontains=module)
        start_date = params.get('start_date')
        if start_date: qs = qs.filter(created_at__gte=start_date)
        end_date = params.get('end_date')
        if end_date: qs = qs.filter(created_at__lte=end_date)
        return qs
    @action(detail=False, methods=['get'], permission_classes=[IsAdminUser])
    def stats(self, request):
        stats = AuditLog.objects.values('entity_type').annotate(count=Count('id'))
        return Response(stats)

class SystemSettingsView(generics.RetrieveUpdateAPIView):
    serializer_class = SystemSettingsSerializer
    permission_classes = [IsDepartmentHeadOrReadOnly]
    def get_object(self): return SystemSettings.load()
    def perform_update(self, serializer):
        serializer.save(updated_by=self.request.user)
        AuditLog.objects.create(user=self.request.user, action="Updated System Settings", entity_type="SystemSettings", entity_id=None, ip_address=get_client_ip(self.request))