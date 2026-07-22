from django.conf import settings
from django.conf.urls.static import static
from django.contrib import admin
from django.urls import include, path

urlpatterns = [
    path("admin/", admin.site.urls),
    # All real API traffic goes through here — CustomTokenObtainPairView,
    # DocumentViewSet, SystemSettingsView, etc. all live in api/urls.py.
    # (Removed the old /api/v1/ block that pointed at the stock
    # TokenObtainPairView — it returned tokens without role/department
    # and nothing in the app actually calls it; keeping both was
    # confusing and risked someone accidentally wiring the frontend to
    # the wrong one.)
    path("api/", include("api.urls")),
]

if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)