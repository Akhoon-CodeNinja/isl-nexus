"""
Document-loading helpers for the RAG pipeline.

This module intentionally owns ONLY file parsing (`_load_pages`). Indexing
itself (chunking, embedding, and writing to the FAISS store) lives in
`services.py::ISLChatBotService.rebuild_index_from_paths`, which is the
single, authoritative indexing path called from `views.py::sync_vector_store`
every time a document is uploaded/approved/activated/deactivated/deleted.

History: this file used to also define `process_and_add_document()`, wired
up to a `post_save` signal on `Document` (see `signals.py`), plus its own
module-level `HuggingFaceEmbeddings` instance to support it. That path was
removed for two reasons:
  1. Correctness/security -- `post_save` fires *during* `serializer.save()`,
     before the view's very next line (`doc.departments.set(...)`) has run,
     so the document always got indexed with `department_ids=[]` -- which
     is treated as "no restriction", making it retrievable by chat users in
     ANY department regardless of which department(s) it actually belonged
     to.
  2. Redundancy -- `sync_vector_store()` already performs a full, correctly
     ordered rebuild via `rebuild_index_from_paths()` immediately after the
     M2M `departments` is set, making the signal-driven path unnecessary.
Keeping a second, unused `HuggingFaceEmbeddings` model loaded at import time
just to back dead code wasted RAM and slowed every server start, so it was
removed along with the dead function. `signals.py` documents the same
history from the indexing side.
"""

import os
import pandas as pd
from langchain_text_splitters import RecursiveCharacterTextSplitter
from langchain_community.document_loaders import PyPDFLoader, Docx2txtLoader
from langchain_core.documents import Document as LangchainDocument

# Directory where the FAISS index (index.faiss + index.pkl) is persisted.
FAISS_INDEX_PATH = "faiss_index"


def _load_pages(doc_path):
    """
    Picks the right loader by file extension. 
    Handles PDF, DOCX, and XLSX files intelligently for RAG.
    """
    ext = os.path.splitext(doc_path)[1].lower()

    # 1. PDF Loader
    if ext == ".pdf":
        return PyPDFLoader(doc_path).load()

    # 2. Word Document Loader
    if ext in [".docx", ".doc"]:
        return Docx2txtLoader(doc_path).load()

    # 3. Excel Loader (Updated with Pandas for better RAG Context)
    if ext in [".xlsx", ".xls"]:
        docs = []
        try:
            excel_file = pd.ExcelFile(doc_path)
            for sheet_name in excel_file.sheet_names:
                df = pd.read_excel(excel_file, sheet_name=sheet_name)
                
                # Khali rows aur columns ko nikal dein
                df = df.dropna(how='all')
                if df.empty:
                    continue

                text_lines = [f"=== Excel Sheet: {sheet_name} ==="]
                
                # Har row ko 'Column_Name: Value' format mein combine karein
                for idx, row in df.iterrows():
                    row_items = [f"{str(col)}: {str(val)}" for col, val in row.items() if pd.notna(val)]
                    if row_items:
                        row_text = f"Record {idx + 1} -> " + " | ".join(row_items)
                        text_lines.append(row_text)

                sheet_content = "\n".join(text_lines)
                
                if sheet_content.strip():
                    docs.append(LangchainDocument(
                        page_content=sheet_content,
                        metadata={"source": doc_path, "sheet": sheet_name}
                    ))
            return docs
        except Exception as e:
            print(f"Error loading Excel file {doc_path}: {e}")
            return []

    raise ValueError(f"Unsupported file type for indexing: '{ext}'")