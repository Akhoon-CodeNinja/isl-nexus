"""
Management command: sync_faiss_index

Existing (pehle se database mein maujood) active documents ko FAISS index
mein sync karne ke liye. Ye zaroori hai un documents ke liye jo naye
sync_vector_store() fix se pehle upload huay thay, kyunke wo fix sirf
future ke upload/status-toggle/replace/delete actions par chalta hai.

Usage:
    python manage.py sync_faiss_index

Is file ko apne app ke andar `management/commands/sync_faiss_index.py`
path par rakhein (jaisa ingest_docs.py already hai).
"""

from django.core.management.base import BaseCommand

# NOTE: apna actual app ka naam yahan use karein (jahan Document model aur
# views.sync_vector_store() maujood hain) -- neeche 'api' placeholder hai.
from api.models import Document
from api.views import sync_vector_store


class Command(BaseCommand):
    help = "Backfill: existing active PDF documents ko FAISS index mein sync karta hai."

    def handle(self, *args, **kwargs):
        active_docs = Document.objects.filter(
            is_active=True,
            file_type=Document.FileType.PDF,
        )
        count = active_docs.count()

        if count == 0:
            self.stdout.write(self.style.WARNING(
                "Koi active PDF document nahi mila. Kuch bhi sync nahi hoga."
            ))
            return

        self.stdout.write(f"{count} active PDF document(s) mile. Index rebuild ho raha hai...")

        try:
            sync_vector_store()
        except Exception as e:
            self.stdout.write(self.style.ERROR(f"Sync fail ho gaya: {e}"))
            return

        self.stdout.write(self.style.SUCCESS(
            f"Successfully synced! {count} document(s) ab AI ke FAISS index mein maujood hain."
        ))
