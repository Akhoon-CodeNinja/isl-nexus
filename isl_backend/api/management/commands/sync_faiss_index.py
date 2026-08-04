"""
Management command: sync_faiss_index

Existing (pehle se database mein maujood) active + AI-chatbot-enabled
documents ko sharded FAISS index (`faiss_index/dept_<id>/` +
`faiss_index/common/`, see services.py) mein backfill/rebuild karne ke
liye. Har document `Document.include_in_chatbot=True` hona chahiye taake
ye is command se pick ho -- documents jo sirf read/download ke liye hain
(include_in_chatbot=False, jo NAYA DEFAULT hai) is index mein kabhi nahi
jaate, chahe wo active kyun na hon.

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
    help = ("Backfill/rebuild: existing active + include_in_chatbot=True documents ko "
            "sharded FAISS index mein sync karta hai.")

    def handle(self, *args, **kwargs):
        active_docs = Document.objects.filter(
            is_active=True,
            include_in_chatbot=True,
        )
        count = active_docs.count()

        if count == 0:
            self.stdout.write(self.style.WARNING(
                "Koi active + 'include_in_chatbot=True' document nahi mila. Kuch bhi "
                "sync nahi hoga. (Yaad rahe: include_in_chatbot ka default False hai -- "
                "Department Head ya Admin ko har relevant document par ye flag on karna "
                "hoga pehle.)"
            ))
            return

        self.stdout.write(
            f"{count} active + chatbot-enabled document(s) mile. Sharded index rebuild "
            f"ho raha hai (department-wise + common shard)..."
        )

        try:
            sync_vector_store()
        except Exception as e:
            self.stdout.write(self.style.ERROR(f"Sync fail ho gaya: {e}"))
            return

        self.stdout.write(self.style.SUCCESS(
            f"Successfully synced! {count} document(s) ab AI ke sharded FAISS index mein maujood hain."
        ))
