from rest_framework import permissions

class IsDepartmentHeadOrReadOnly(permissions.BasePermission):
    """
    WORKER can only read (GET, HEAD, OPTIONS).
    DEPARTMENT_HEAD can read and write (POST, PUT, PATCH, DELETE)[cite: 1].
    """
    def has_permission(self, request, view):
        if not request.user or not request.user.is_authenticated:
            return False

        if request.method in permissions.SAFE_METHODS:
            return True
            
        # Write permissions are only allowed to DEPARTMENT_HEAD
        return request.user.role == 'DEPARTMENT_HEAD' # References Role.DEPARTMENT_HEAD[cite: 1]

class IsDepartmentHead(permissions.BasePermission):
    """Strictly for endpoints only available to Heads."""
    def has_permission(self, request, view):
        return bool(
            request.user and 
            request.user.is_authenticated and 
            request.user.role == 'DEPARTMENT_HEAD'
        )