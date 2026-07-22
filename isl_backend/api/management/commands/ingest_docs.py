import os
from django.core.management.base import BaseCommand
from langchain_community.document_loaders import PyPDFDirectoryLoader
from langchain_text_splitters import RecursiveCharacterTextSplitter
from langchain_huggingface import HuggingFaceEmbeddings
from langchain_community.vectorstores import FAISS

class Command(BaseCommand):
    help = 'Ingest company documents (PDFs) into the FAISS vector store for ISL Nexus'

    def handle(self, *args, **kwargs):
        # Folder jahan aap apne PDFs rakhenge
        docs_dir = "docs_to_ingest"
        
        if not os.path.exists(docs_dir):
            os.makedirs(docs_dir)
            self.stdout.write(self.style.WARNING(f"Created '{docs_dir}' directory. Please put your PDF documents there and run the command again."))
            return

        self.stdout.write("Loading documents...")
        loader = PyPDFDirectoryLoader(docs_dir)
        documents = loader.load()

        if not documents:
            self.stdout.write(self.style.ERROR(f"No PDF documents found in '{docs_dir}' directory."))
            return

        self.stdout.write(f"Loaded {len(documents)} document pages.")

        # Text ko chotay chunks mein split karein taake LLM ko parhne mein asani ho
        self.stdout.write("Splitting documents into chunks...")
        text_splitter = RecursiveCharacterTextSplitter(
            chunk_size=1000,
            chunk_overlap=200,
            separators=["\n\n", "\n", ".", " ", ""]
        )
        chunks = text_splitter.split_documents(documents)
        self.stdout.write(f"Created {len(chunks)} chunks.")

        # Embeddings model (wahi jo services.py mein use kiya hai)
        self.stdout.write("Generating embeddings... This might take a moment.")
        embeddings = HuggingFaceEmbeddings(model_name="all-MiniLM-L6-v2")

        # Vector Database (FAISS) banayen aur save karein
        vector_store_path = "faiss_index"
        vector_store = FAISS.from_documents(chunks, embeddings)
        vector_store.save_local(vector_store_path)

        self.stdout.write(self.style.SUCCESS(f"Successfully ingrained company knowledge! Index saved to '{vector_store_path}'."))