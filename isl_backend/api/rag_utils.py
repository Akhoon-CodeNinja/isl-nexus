import os
import pandas as pd
from langchain_text_splitters import RecursiveCharacterTextSplitter
from langchain_community.document_loaders import PyPDFLoader, Docx2txtLoader
from langchain_community.vectorstores import FAISS
from langchain_community.embeddings import HuggingFaceEmbeddings
from langchain_core.documents import Document as LangchainDocument

# FAISS index kahan save hoga 
FAISS_INDEX_PATH = "faiss_index"

# Embedding model
embeddings = HuggingFaceEmbeddings(model_name="all-MiniLM-L6-v2")

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

def process_and_add_document(doc_path, doc_id, doc_title):
    try:
        # SECURITY FIX: this function runs from a post_save signal on
        # every Document save, which previously meant a document could
        # get indexed (and become searchable via chat by ANY user,
        # regardless of department) the instant it was uploaded --
        # before a Head/Admin ever approved it. It also never recorded
        # which department(s) a document belongs to, so once indexed a
        # document was retrievable by every user regardless of role or
        # department.
        #
        # Both are fixed here: (1) look up the actual Document row and
        # skip indexing entirely if it isn't active yet (sync_vector_store
        # in views.py will pick it up for real once it's approved+active),
        # and (2) tag every chunk with the department(s) it belongs to, so
        # retrieval (services.py::_handle_company_query) can filter results
        # to only what the querying user is actually allowed to see. An
        # empty department_ids list means "no department restriction" (a
        # general/company-wide document), visible to everyone -- same
        # convention as target_department=None elsewhere in this codebase.
        department_ids = []
        try:
            from .models import Document as DocumentModel
            doc_row = DocumentModel.objects.filter(id=doc_id).first()
            if doc_row is None:
                print(f"[process_and_add_document] doc_id={doc_id} not found, skipping index.")
                return
            if not doc_row.is_active:
                print(f"[process_and_add_document] '{doc_title}' is not active/approved yet -- "
                      f"skipping index until it is (sync_vector_store will add it once approved).")
                return
            department_ids = list(doc_row.departments.values_list('id', flat=True))
        except Exception as e:
            print(f"[process_and_add_document] Warning: could not resolve departments for "
                  f"doc_id={doc_id}, indexing with NO department restriction as a fail-safe "
                  f"would be unsafe -- aborting index instead: {e}")
            return

        pages = _load_pages(doc_path)

        text_splitter = RecursiveCharacterTextSplitter(chunk_size=1000, chunk_overlap=150)
        chunks = text_splitter.split_documents(pages)
        
        for chunk in chunks:
            chunk.metadata['doc_id'] = str(doc_id)
            chunk.metadata['doc_title'] = doc_title
            chunk.metadata['department_ids'] = department_ids
            
        if os.path.exists(FAISS_INDEX_PATH):
            db = FAISS.load_local(FAISS_INDEX_PATH, embeddings, allow_dangerous_deserialization=True)
            db.add_documents(chunks)
            db.save_local(FAISS_INDEX_PATH)
        else:
            db = FAISS.from_documents(chunks, embeddings)
            db.save_local(FAISS_INDEX_PATH)
            
        print(f"✅ Document '{doc_title}' successfully indexed in FAISS! (department_ids={department_ids})")
    except Exception as e:
        print(f"❌ FAISS Indexing failed for '{doc_title}': {e}")