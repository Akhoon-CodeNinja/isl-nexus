from django.urls import path, include
from rest_framework.routers import DefaultRouter
from rest_framework_simplejwt.views import TokenRefreshView
from .views import (
    CustomTokenObtainPairView, MeView, DepartmentViewSet, DocumentViewSet, 
    TagViewSet, AlertViewSet, ChatSessionViewSet, ChatMessageViewSet,
    UserViewSet, AuditLogViewSet, SystemSettingsView, MicrosoftLoginView
)

from .views import ChatAskView



router = DefaultRouter()
# Fixes Python 3.14 / DRF duplicate converter registration issue:
router.include_format_suffixes = False

router.register(r'departments', DepartmentViewSet, basename='department')
router.register(r'documents', DocumentViewSet, basename='document')
router.register(r'tags', TagViewSet, basename='tag')
router.register(r'alerts', AlertViewSet, basename='alert')
router.register(r'chat-sessions', ChatSessionViewSet, basename='chatsession')
router.register(r'chat-messages', ChatMessageViewSet, basename='chatmessage')
router.register(r'users', UserViewSet, basename='user')
router.register(r'audit-logs', AuditLogViewSet, basename='auditlog')

urlpatterns = [
    path('auth/login/', CustomTokenObtainPairView.as_view(), name='token_obtain_pair'),
    path('auth/refresh/', TokenRefreshView.as_view(), name='token_refresh'),
    path('auth/me/', MeView.as_view(), name='me'),
    path('auth/microsoft/', MicrosoftLoginView.as_view(), name='microsoft_login'),
    path('settings/', SystemSettingsView.as_view(), name='system-settings'),
    path('', include(router.urls)),
    path('chat/ask/', ChatAskView.as_view(), name='chat_ask'),
]