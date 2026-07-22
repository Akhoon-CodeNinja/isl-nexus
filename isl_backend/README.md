# ISL Enterprise & AI Assistant Platform — Backend

Django 5.x + DRF + SimpleJWT + PostgreSQL backend for the ISL industrial
mobile app and admin web portal.

## Step 1 — Project initialization (commands used to scaffold this repo)

```bash
# 1. Create & activate a virtual environment
python3 -m venv venv
source venv/bin/activate          # Windows: venv\Scripts\activate

# 2. Install dependencies
pip install -r requirements.txt

# 3. (Reference) How this project was originally created:
django-admin startproject isl_backend
cd isl_backend
python manage.py startapp api
```

## Configure environment

```bash
cp .env.example .env
# then edit .env with real DB credentials / secret key
```

Create the PostgreSQL database referenced in `.env`:

```bash
createdb isl_backend
# or, from psql:
# CREATE DATABASE isl_backend OWNER isl_admin;
```

## Migrate & run

```bash
python manage.py makemigrations
python manage.py migrate
python manage.py createsuperuser   # prompts for employee_id / email / password
python manage.py runserver
```

Django Admin: `http://127.0.0.1:8000/admin/`
JWT login endpoint: `POST http://127.0.0.1:8000/api/v1/auth/login/` with
`{"employee_id": "...", "password": "..."}`

## What's implemented in this step

- `isl_backend/settings.py` — PostgreSQL, DRF, SimpleJWT, CORS,
  custom `AUTH_USER_MODEL`, env-driven config via `python-decouple`.
- `api/models.py` — all 10 ERD entities as UUID-keyed Django models
  (`Department`, `User`, `Tag`, `Document`, `DocumentTag`, `Alert`,
  `UserAlertRead`, `ChatSession`, `ChatMessage`, `AuditLog`), with
  indexes matching the query patterns the app will need.
- `api/admin.py` — every model registered in Django Admin with
  sensible `list_display` / `list_filter` / `search_fields` for
  development use.
- `isl_backend/urls.py` — SimpleJWT token endpoints wired in
  (`/api/v1/auth/login/`, `/refresh/`, `/logout/`).

**Not yet implemented (next steps):** serializers, ViewSets/routers in
`api/urls.py`, permission classes for role-based access (Department
Head vs Worker), and the RAG chat integration itself.

## Notes on model design decisions

- **UUID primary keys** on every table (`UUIDModel` abstract base),
  instead of Django's default auto-increment `id`, per the ERD.
- **`User.USERNAME_FIELD = "employee_id"`** — workers log in with
  their employee ID, not a username or email, though email is still
  captured and unique for notifications/password resets.
- **`Document.tags`** is a `ManyToManyField` with an explicit
  `through="DocumentTag"` model, matching the ERD's `documents_tags`
  junction table (composite `document_id, tag_id`) rather than letting
  Django auto-generate an implicit join table.
- **`UserAlertRead`** enforces `unique_together = ("alert", "user")`
  so a read receipt can only exist once per user/alert pair, exactly
  as drawn in the ERD's `(alret_id, user_id)` composite PK.
- **`on_delete` choices** are deliberate: `Document.uploaded_by` and
  `Alert.created_by` use `SET_NULL` (don't lose the document/alert if
  the uploader's account is later deactivated/deleted), while
  `DocumentTag` and `UserAlertRead` junctions use `CASCADE` (a link
  row is meaningless without both sides).
