# ISL Backend — Data Architecture

Ye document batata hai ke backend mein **data kis tareeqe se store aur structure** hota hai — teen alag data stores use ho rahe hain, har ek apne specific purpose ke liye.

```
┌─────────────────────────────────────────────────────────────────┐
│                        ISL Django Backend                        │
├───────────────────┬───────────────────────┬─────────────────────┤
│   1. PostgreSQL    │   2. FAISS Index      │   3. Media Storage  │
│   (relational DB)  │   (vector store)      │   (file system)     │
│                     │                        │                     │
│  Users, Documents  │  Document text chunks  │  Actual uploaded    │
│  metadata, Alerts, │  → embeddings, for     │  files: PDF/DOCX/   │
│  Chat history, etc │  the RAG chatbot       │  XLSX               │
└───────────────────┴───────────────────────┴─────────────────────┘
```

---

## 1. Relational data — PostgreSQL (via Django ORM)

**Engine:** `django.db.backends.postgresql` (`isl_backend/settings.py`).
**Where defined:** `api/models.py`.

### Design conventions used throughout

| Convention | Why |
|---|---|
| **UUID primary keys** on every table (`UUIDModel` abstract base) | Avoids exposing sequential/guessable integer IDs over the API; plays well with future offline/distributed sync. |
| **`db_index=True`** on every FK and frequently-filtered column (`is_active`, `created_at`, `approval_status`, ...) | Keeps dashboard/list/chat queries fast as tables grow. |
| **Explicit `related_name`** on every FK/M2M | Reverse relations read naturally: `department.documents`, `user.uploaded_documents`. |
| **Through-models for M2M with extra data** (`DocumentTag`, `UserAlertRead`) | Matches the ERD's junction tables and lets extra columns (`read_at`) live on the relationship itself. |
| **`TextChoices` enums** (`Role`, `ApprovalStatus`, `FileType`, `AlertType`, ...) | Restricts values at the DB + serializer layer instead of relying on free-text strings. |

### Tables / models (14 total)

| Model | DB table | Purpose |
|---|---|---|
| `Department` | `departments` | Org units (IT, HR, Safety, ...). |
| `User` (custom, `AUTH_USER_MODEL`) | `users` | RBAC: `ADMIN` / `DEPARTMENT_HEAD` / `WORKER`. Auth key is `employee_id`, not username. |
| `Tag` | `tags` | Per-department document categories. |
| `Document` | `documents` | Uploaded policy/reference files. **`departments` is ManyToMany** (one doc can belong to several departments). |
| `DocumentTag` | `documents_tags` | Explicit Document↔Tag junction (composite unique key). |
| `Alert` | `alerts` | Notifications/announcements/leave requests. |
| `UserAlertRead` | `users_alert_reads` | Read-receipt junction (unique per user+alert). |
| `NotificationTemplate` | `notification_templates` | Reusable Admin-authored alert drafts (NEW→ACTIVE→INACTIVE lifecycle). |
| `ChatSession` | `chat_sessions` | One row per user chat session. |
| `ChatMessage` | `chat_messages` | Individual user/AI turns, optionally citing a `Document`. |
| `AuditLog` | `audit_logs` | Who did what, when, from which IP — for every mutating admin action. |
| `SystemSettings` | `system_settings` | **Singleton** (`pk` is forced to `1` in `save()`) — one row holds all platform-wide toggles. |

### Key relationships

```
Department 1───* User            (a user belongs to at most one department)
Department *───* Document        (multi-department documents, via M2M)
Department 1───* Tag             (tags are scoped per department)
Document   *───* Tag             (via DocumentTag)
User       1───* Document        (uploaded_by)
User       1───* ChatSession 1───* ChatMessage
Alert      *───* User            (read receipts, via UserAlertRead)
Department 1───* Alert           (target_department; NULL = broadcast to all)
```

### Access control lives in the data, not just in code

`Document.departments` (M2M) and `Alert.target_department` (nullable FK) are how row-level, department-scoped visibility is enforced — `views.py` querysets and `services.py` retrieval filtering both key off these fields directly (see §2 below for how this extends into the vector store).

---

## 2. Vector store — FAISS (for the RAG chatbot)

**Where:** `faiss_index/` directory at the project root (`index.faiss` + `index.pkl`, persisted to disk).
**Built/queried by:** `api/services.py` (`ISLChatBotService`), file-parsing helpers in `api/rag_utils.py`.

This is **not** a database table — it's a similarity-search index, separate from PostgreSQL, that only exists to power the AI assistant's document search.

### How data gets into it

Two paths now exist — a **targeted (incremental)** path used for every normal action, and a **full rebuild** path used only for bulk backfill.

**Targeted path (`views.py::sync_single_document()` → `services.py::ISLChatBotService.index_document()` / `.remove_document()`)** — used on every upload, activate/deactivate, approve/reject, replace, and delete:

- A **hash table** (`ISLChatBotService._doc_chunk_ids`, a plain Python `dict[doc_id -> [chunk_id, ...]]`) is kept in memory and persisted to `faiss_index/chunk_registry.json`. This is what makes "touch only the one document that changed" possible — FAISS itself has no concept of "which chunks belong to which uploaded document"; that mapping only exists in this registry.
- **Deactivating / deleting a document:** look up its chunk ids in the registry (`O(1)` dict lookup) → call LangChain's `FAISS.delete(ids=...)` → those vectors are removed from the FAISS index (`index.remove_ids`) and their entries removed from the docstore. Every other document's chunks are untouched.
- **Activating / uploading / replacing a document:** parse just that one file (`rag_utils.py::_load_pages`), chunk it, embed it, call `FAISS.add_documents(...)`, record the ids it returns into the registry. `index_document()` always removes any old chunks for that `doc_id` first, so `replace` (swapping in a new file) correctly drops the old version's chunks rather than leaving them alongside the new ones.
- Verified against the actual LangChain FAISS API: `add_documents()` returns the new chunk ids, `.delete(ids=...)` genuinely removes just those vectors (backed by `IndexFlatL2.remove_ids`), and a reload via `FAISS.load_local()` reflects the change correctly.

**Full-rebuild path (`views.py::sync_vector_store()` → `services.py::rebuild_index_from_paths()`)** — no longer called by per-document actions; kept for:
- The `sync_faiss_index` management command (one-off backfill of documents that predate this indexing logic).
- A manual full-resync if the registry and the index ever drift out of sync.

Both paths tag every chunk's metadata with `doc_id`, `doc_title`, and `department_ids` — this is what makes department-scoped retrieval possible (see below).

### How it's queried

`ISLChatBotService._handle_company_query()`:
1. Runs `max_marginal_relevance_search` (MMR) — fetches 40 diverse candidate chunks, narrows to the 20 most relevant/diverse.
2. Filters those candidates down to only the chunks whose `department_ids` metadata the *querying user* is actually allowed to see (`_doc_chunk_allowed`) — an Admin sees everything; a Worker/Head sees their own department's documents plus any document with no department restriction (company-wide).
3. Takes the top 5 post-filter chunks as context and sends them to the Groq-hosted LLM (`ChatGroq`) via a LangChain prompt chain to generate the final answer.

This two-stage filter (vector similarity, *then* department access) is what stops an IT-only document from leaking into a Warehouse worker's chat answer.

---

## 3. File storage — uploaded documents

**Where:** `media/documents/<year>/<month>/<filename>` on the local filesystem (`MEDIA_ROOT` in `settings.py`).
**Tracked by:** `Document.file_url` (a Django `FileField`, storing the relative path — the actual bytes live on disk, not in PostgreSQL).

This is the source-of-truth file; the FAISS index (§2) only ever stores *extracted text + embeddings* derived from it, never the file itself.

---

## Summary — "kaunsa data structure kahan hai"

| Data | Structure | Store |
|---|---|---|
| Users, roles, departments, alerts, chat message log, audit trail | Relational rows/tables (UUID PKs, FKs, M2M through-tables) | PostgreSQL |
| Document *text*, chunked + embedded for semantic search | Vector index (FAISS: dense float vectors + a metadata sidecar) | `faiss_index/index.faiss` + `index.pkl` on disk |
| doc_id → chunk_ids mapping (what makes targeted add/remove possible) | Hash table (`dict`), persisted as JSON | `faiss_index/chunk_registry.json` on disk, mirrored in RAM |
| The actual uploaded PDF/DOCX/XLSX bytes | Flat files | `media/documents/...` on disk |
| Session/auth state | Stateless JWT (access + refresh tokens, SimpleJWT) | Not stored server-side (blacklist table only, for revoked refresh tokens) |
