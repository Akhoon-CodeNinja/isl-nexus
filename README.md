```markdown
# 🚀 ISL Nexus - Enterprise Knowledge Base & RAG Platform

An enterprise-grade document management and workflow automation system powered by an intelligent Retrieval-Augmented Generation (RAG) chatbot. Built with a scalable Django REST Framework backend and a cross-platform Flutter frontend.

---

## 📌 Overview

**ISL Nexus** is designed to streamline internal company documentation, security policies, and employee workflows. It features secure Role-Based Access Control (RBAC), real-time document search, vector-based semantic querying, and a token-authenticated client interface.

---

## ✨ Key Features

### 🤖 1. AI Knowledge Base & RAG Pipeline
* Context-aware chatbot for querying enterprise documents (e.g., Leave Policies, Safety Guidelines, SRS documents).
* Integrated vector search leveraging **FAISS** and **LangChain** for ultra-fast semantic retrieval.
* Automated document ingestion and index synchronization commands.

### 👥 2. Role-Based Access Control (RBAC)
* **Admin / Department Head Portal:** Comprehensive dashboards for managing users, monitoring activity logs, adjusting system settings, and reviewing multi-department document uploads.
* **Worker Portal:** Dedicated mobile/web-optimized views for workers to chat with the AI assistant, browse department documents, receive broadcast alerts, and manage profile states.

### 🔐 3. Robust Authentication & Security
* Secure JSON Web Token (JWT) authentication with automated background token interception and auto-refresh mechanisms.
* Memory-cached tokens (`_memoryToken`) and synchronized profile persistence to eliminate "Session Expired" interruptions.

### 📊 4. Analytics & Document Management
* Dynamic data visualization and real-time operational metrics.
* Full CRUD operations for documents with versioning, status toggling, and multi-department mapping.

---

## 🛠️ Tech Stack

* **Frontend:** Flutter, Dart, Dio (with Interceptors), Provider, Fl_Chart.
* **Backend:** Python, Django, Django REST Framework (DRF), SimpleJWT.
* **AI & Search:** LangChain, FAISS Vector Database, OpenAI / Groq API integrations.
* **Containerization:** Docker & Docker Compose *(Optional / Production Ready)*.

---

## 📂 Project Structure

```text
ISL_APP/
├── isl_backend/          # Django REST Framework Backend
│   ├── api/              # Core API endpoints, models, RAG utilities, migrations
│   ├── isl_backend/      # Project settings, URLs, WSGI/ASGI configurations
│   ├── media/            # Uploaded enterprise documents (PDF, DOCX, XLS)
│   ├── faiss_index/      # Serialized vector indices (.faiss, .pkl)
│   ├── Dockerfile        # Backend container configuration
│   └── requirements.txt  # Python dependencies
│
├── isl_front-end/        # Flutter Cross-Platform Frontend
│   ├── lib/
│   │   ├── core/         # State providers, API services, global models
│   │   ├── views/        # Admin and Worker dashboard screens
│   │   └── widgets/      # Reusable UI components & navigation bars
│   ├── Dockerfile        # Frontend Nginx container configuration
│   └── pubspec.yaml      # Flutter dependencies
│
└── docker-compose.yml    # Multi-container orchestration setup

```

---

## ⚙️ Local Development Setup

### Prerequisites

* Python 3.10+ & Pip
* Flutter SDK (Latest Stable)
* Git

### 1. Clone the Repository

```bash
git clone [https://github.com/Akhoon-CodeNinja/isl-nexus.git](https://github.com/Akhoon-CodeNinja/isl-nexus.git)
cd isl_nexus

```

### 2. Backend Setup (Django)

```bash
cd isl_backend
python -m venv venv
# On Windows:
venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Configure environment variables
cp .env.example .env
# (Update your .env file with your database and API keys)

# Run migrations & start server
python manage.py migrate
python manage.py runserver

```

### 3. Frontend Setup (Flutter)

Open a new terminal window:

```bash
cd isl_front-end
flutter pub get
flutter run -d chrome

```

---

## 🐳 Docker Deployment (Optional)

To run the entire stack containerized via Docker:

```bash
docker compose up --build

```
