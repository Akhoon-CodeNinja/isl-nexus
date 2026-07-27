from rest_framework import permissions


class IsDepartmentHeadOrReadOnly(permissions.BasePermission):
    def has_permission(self, request, view):
        if not request.user or not request.user.is_authenticated:
            return False

        if request.method in permissions.SAFE_METHODS:
            return True
            
        # Write permissions: HEAD ko ya un Workers ko jinko access assign hui hai
        return (request.user.role == 'DEPARTMENT_HEAD') or getattr(request.user, 'can_manage_docs', False)

class IsDepartmentHead(permissions.BasePermission):
    """Strictly for endpoints only available to Heads."""
    def has_permission(self, request, view):
        return bool(
            request.user and 
            request.user.is_authenticated and 
            request.user.role == 'DEPARTMENT_HEAD'
        )