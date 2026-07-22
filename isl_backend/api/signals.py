from django.db.models.signals import post_save
from django.dispatch import receiver
from .models import Document
from .rag_utils import process_and_add_document

@receiver(post_save, sender=Document)
def update_faiss_index_on_upload(sender, instance, created, **kwargs):
    # Only index on the document's initial creation. Document.save() also
    # fires on every later edit (activate/deactivate, approve, rename,
    # replace metadata, etc.) — re-running process_and_add_document on
    # each of those would append the same file's chunks into FAISS again
    # every time, since add_documents() has no built-in dedup. Re-indexing
    # an actually-replaced file is handled separately wherever the
    # 'replace' document action lives, not here.
    if created and instance.file_url and instance.is_active:
        file_path = instance.file_url.path  # PDF/DOCX/XLSX ka physical path

        # Asynchronous task ya background mein RAG engine ko call karein
        process_and_add_document(
            doc_path=file_path, 
            doc_id=instance.id,
            doc_title=instance.file_url.name.split('/')[-1] # File ka naam reference ke liye
        )