from django.db.models.signals import post_save
from django.dispatch import receiver
from .models import Document
# process_and_add_document import removed -- no longer called from here,
# see explanation below.

@receiver(post_save, sender=Document)
def update_faiss_index_on_upload(sender, instance, created, **kwargs):
    # DISABLED (security fix): this used to call process_and_add_document()
    # here, but post_save fires DURING serializer.save() in
    # DocumentViewSet.perform_create() -- BEFORE the very next line,
    # doc.departments.set(departments), actually runs (Django M2M .set()
    # is always a separate step after save()). For Head/Admin uploads
    # (auto-approved+active immediately), that meant this signal indexed
    # the document with department_ids=[] every time -- which
    # _doc_chunk_allowed() in services.py treats as "no restriction",
    # making the document retrievable by chat users in ANY department
    # regardless of which department(s) it was actually assigned to.
    #
    # This is also redundant: perform_create() already calls
    # sync_vector_store() itself, AFTER doc.departments.set() has run, which
    # does a full, correctly-ordered FAISS rebuild with accurate
    # department_ids for every active document (see views.py). That is now
    # the ONLY indexing path -- intentionally a no-op here so a stray
    # pre-M2M index can never be written again.
    passq