from rest_framework import permissions


class IsDepartmentHeadOrReadOnly(permissions.BasePermission):
    def has_permission(self, request, view):
        if not request.user or not request.user.is_authenticated:
            return False

        if request.method in permissions.SAFE_METHODS:
            return True
            
        # Write permissions: HEAD, ADMIN, ya un Workers ko jinko access assign hui hai
        return (request.user.role in ('DEPARTMENT_HEAD', 'ADMIN')) or getattr(request.user, 'can_manage_docs', False)

class IsAdminOnly(permissions.BasePermission):
    """Strictly the ADMIN role -- unlike IsDepartmentHead/IsAdminUser (in
    views.py), a DEPARTMENT_HEAD does NOT pass this check.

    Used for actions that are exclusively an Admin's job: creating new
    user accounts, creating new departments, managing notification
    templates, and setting a user's per-user chat message limit.
    """
    def has_permission(self, request, view):
        return bool(
            request.user and
            request.user.is_authenticated and
            request.user.role == 'ADMIN'
        )
    """For endpoints available to Heads -- ADMIN included, since Admin sits
    above Department Head in the role hierarchy and can do everything a
    Head can, plus more (enforced per-view where relevant).

    NOTE: not currently imported/used anywhere in views.py -- views.py
    defines its own local IsAdminUser class instead for the same purpose.
    Left in place rather than deleted since it may be used elsewhere in
    the project outside this review's file set; if nothing else in the
    codebase imports it, it's safe to remove.
    """
    def has_permission(self, request, view):
        return bool(
            request.user and 
            request.user.is_authenticated and 
            request.user.role in ('DEPARTMENT_HEAD', 'ADMIN')
        )