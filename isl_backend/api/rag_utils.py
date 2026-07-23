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
        pages = _load_pages(doc_path)

        text_splitter = RecursiveCharacterTextSplitter(chunk_size=1000, chunk_overlap=150)
        chunks = text_splitter.split_documents(pages)
        
        for chunk in chunks:
            chunk.metadata['doc_id'] = str(doc_id)
            chunk.metadata['doc_title'] = doc_title
            
        if os.path.exists(FAISS_INDEX_PATH):
            db = FAISS.load_local(FAISS_INDEX_PATH, embeddings, allow_dangerous_deserialization=True)
            db.add_documents(chunks)
            db.save_local(FAISS_INDEX_PATH)
        else:
            db = FAISS.from_documents(chunks, embeddings)
            db.save_local(FAISS_INDEX_PATH)
            
        print(f"✅ Document '{doc_title}' successfully indexed in FAISS!")
    except Exception as e:
        print(f"❌ FAISS Indexing failed for '{doc_title}': {e}")