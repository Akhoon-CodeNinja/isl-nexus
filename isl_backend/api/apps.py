from django.apps import AppConfig

class IslAppConfig(AppConfig):
    default_auto_field = 'django.db.models.BigAutoField'
    # Must match the actual Python package this file lives in. Every
    # migration in this project (e.g. `to='api.department'`) and every
    # other module's relative imports (`from .models import ...`)
    # confirm the real app name is 'api', not 'isl_app' — that mismatch
    # would stop Django from starting at all.
    name = 'api'

    def ready(self):
        import api.signals  # noqa: F401 — registers the post_save signal below