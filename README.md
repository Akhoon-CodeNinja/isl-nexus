# ISL Nexus - Enterprise Knowledge Base & Management System

An AI-powered document management and workflow automation system. The platform consists of a Django REST Framework backend and a cross-platform Flutter frontend. It features a RAG (Retrieval-Augmented Generation) pipeline for intelligent document querying and distinct dashboards for Workers and Department Heads.

## 🚀 Features
* **AI Knowledge Base (RAG):** Context-aware chatbot for querying enterprise documents (e.g., Leave Policies, Safety Guidelines).
* **Role-Based Access Control:** Secure portals for Admin/Department Heads and standard Workers.
* **Document Management:** Upload, versioning, status toggling, and bulk actions.
* **Analytics Dashboard:** Real-time metrics and dynamic data visualization (Fl_Chart).
* **Robust Auth:** Token-based authentication with automated background refresh.

## 🛠️ Tech Stack
* **Frontend:** Flutter, Dart, Dio, Provider, Fl_Chart.
* **Backend:** Python, Django, Django REST Framework.
* **AI/Vector Services:** LangChain, FAISS (or relevant Vector DB).
* **Deployment:** Docker, Docker Compose.

## 🐳 Quick Start with Docker (Recommended)

You can run the entire stack (Backend + Frontend) using Docker Compose.

### Prerequisites
* [Docker](https://docs.docker.com/get-docker/) and Docker Compose installed.

### Steps to Run
1. **Clone the repository:**
   ```bash
   git clone [https://github.com/YourUsername/isl_nexus.git](https://github.com/YourUsername/isl_nexus.git)
   cd isl_nexuss