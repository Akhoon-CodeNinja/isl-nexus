import os
import re
from langchain_groq import ChatGroq
from langchain_huggingface import HuggingFaceEmbeddings
from langchain_community.vectorstores import FAISS
from langchain_community.document_loaders import PyPDFLoader
from langchain_text_splitters import RecursiveCharacterTextSplitter
from langchain_core.prompts import ChatPromptTemplate
from langchain_core.output_parsers import StrOutputParser
from dotenv import load_dotenv
from .rag_utils import _load_pages

load_dotenv()

class ISLChatBotService:
    def __init__(self):
        # Groq API aur LLM initialize karein
        # Zaroori hai k aapne terminal mein export GROQ_API_KEY="your_key" kiya ho
        api_key = os.getenv("GROQ_API_KEY")
        if not api_key:
            raise ValueError("GROQ_API_KEY is missing from environment variables or .env file.")
        
        # "llama3-8b-8192" Groq par 30 Aug 2025 ko decommission ho chuka tha (isi wajah se
        # /api/chat/ask/ par 400 -> 500 error aa raha tha). Current recommended model use kar rahe hain.
        self.llm = ChatGroq(temperature=0.3, model_name="openai/gpt-oss-20b", groq_api_key=api_key)
        
        # Local embeddings (Open Source & Free)
        self.embeddings = HuggingFaceEmbeddings(model_name="all-MiniLM-L6-v2")
        
        # FAISS Vector Store load karein (Agar index exist karta hai)
        self.vector_store_path = "faiss_index"
        self.vector_store = None
        if os.path.exists(self.vector_store_path):
            self.vector_store = FAISS.load_local(self.vector_store_path, self.embeddings, allow_dangerous_deserialization=True)

    # Har prompt ke sath yeh common language rule attach hota hai, taake model
    # kabhi Hindi (Devanagari) ya plain English mein jawab na de. Ye rule
    # sirf general nahi -- kuch commonly-leaking Hindi words explicitly
    # ban kiye gaye hain, kyunke model general instruction ke bawajood
    # kabhi kabhi "kripya" jaisay Hindi-origin lafz istemal kar leta tha.
    _LANGUAGE_RULE = (
        "STRICT LANGUAGE RULE: You must respond ONLY in Roman Urdu (Urdu language "
        "written in Latin/English script) or in Urdu script. NEVER respond in Hindi "
        "or Devanagari script, and never respond in plain English. This rule has no "
        "exceptions, even if the user writes in English or Hindi.\n"
        "In particular, NEVER use these Hindi-origin words -- always use the Urdu "
        "word given instead:\n"
        "- 'kripya' -> use 'baraye meherbani' or 'baraye karam'\n"
        "- 'dhanyawad' -> use 'shukriya'\n"
        "- 'aap ka swagat hai' -> use 'khushamdeed' or 'jee aya nu'\n"
        "- 'maaf kijiye' -> use 'maazrat' or 'maaf keejiye ga'\n"
        "- 'sahayata' -> use 'madad'\n"
        "- 'jaankari' -> use 'maloomat'\n"
        "- 'prashn' -> use 'sawal'"
    )

    # Deterministic safety net: even with the prompt rule above, the model
    # can occasionally slip a Hindi word in. This regex-replaces known
    # Hindi-origin words with their Urdu equivalent in every final answer,
    # so the guarantee doesn't rely on the LLM alone.
    _HINDI_TO_URDU_REPLACEMENTS = {
        r"\bkripya\b": "baraye karam",
        r"\bkripaya\b": "baraye karam",
        r"\bdhanyawad\b": "shukriya",
        r"\bdhanyavaad\b": "shukriya",
        r"\bmaaf kijiye\b": "maazrat",
        r"\bsahayata\b": "madad",
        r"\bjaankari\b": "maloomat",
        r"\bprashn\b": "sawal",
    }

    @classmethod
    def _sanitize_hindi_words(cls, text: str) -> str:
        """Final pass on every bot reply: replaces any Hindi-origin words
        that slipped through with their Urdu equivalent. Case-insensitive,
        preserves the original word's capitalization pattern loosely by
        just using the replacement as-is (replacements are short/common
        enough that this reads naturally either way)."""
        for pattern, replacement in cls._HINDI_TO_URDU_REPLACEMENTS.items():
            text = re.sub(pattern, replacement, text, flags=re.IGNORECASE)
        return text

    def rebuild_index_from_paths(self, file_paths: list) -> None:
        """
        Department Head ke upload kiye hue (active + approved) PDF documents ki
        list se FAISS index dobara bana kar memory (self.vector_store) aur disk
        (faiss_index/) dono par update karta hai. Ye views.py se call hota hai
        jab bhi koi document upload/activate/deactivate/delete ho.

        Note: Yeh poora index rebuild karta hai (incremental add nahi), taake
        deactivate/delete hone wale documents bhi index se saaf tarah hat jayein.
        Chotay/medium document counts (kuch sau tak) ke liye ye theek hai; agar
        documents ki tadaad bohat zyada ho jaye to isay incremental update mein
        badalna zaroori hoga.
        """
        if not file_paths:
            # Koi active/approved document nahi bacha, index khali kar dein
            self.vector_store = None
            return

        loaded_docs = []
        for path in file_paths:
            try:
                # PyPDFLoader ki jagah apna custom loader use karein
                loaded_docs.extend(_load_pages(path))
            except Exception as e:
                # Ek kharab/corrupt file poore index ko fail na kare
                print(f"[ISLChatBotService] Warning: could not load '{path}': {e}")

        if not loaded_docs:
            self.vector_store = None
            return

        text_splitter = RecursiveCharacterTextSplitter(
            chunk_size=1000,
            chunk_overlap=200,
            separators=["\n\n", "\n", ".", " ", ""]
        )
        chunks = text_splitter.split_documents(loaded_docs)

        self.vector_store = FAISS.from_documents(chunks, self.embeddings)
        self.vector_store.save_local(self.vector_store_path)

    def _semantic_router(self, query: str) -> str:
        """Query ka intent samajhta hai: LEAVE_REQUEST, COMPANY, GREETING ya OFF_TOPIC"""
        router_prompt = ChatPromptTemplate.from_messages([
            ("system", """You are a strict classification AI for Industrial Solutions Ltd (ISL).
            Categorize the query into EXACTLY ONE of these categories:
            - 'LEAVE_REQUEST': If the user wants to apply for, request, or ask about taking leave/chutti/off from work — in any wording (e.g. "leave chahiye", "mujhe chutti chahiye", "leave apply karni hai", "I want to apply for sick leave", "kal chutti karni hai"). This takes priority over COMPANY.
            - 'COMPANY': If it could plausibly relate to ISL's workplace in any way — company documents, policies, workers, departments, safety, HR, equipment, machines, facilities, procedures, manuals, or any specific ISL guideline. This includes questions about specific equipment/machines/systems (e.g. vending machines, boilers, safety gear) even if "ISL" or "company" is not explicitly mentioned, since these are commonly covered in internal manuals.
            - 'GREETING': If it is only a greeting or small talk directed at the assistant (hi, hello, salam, thank you, how are you, aap kon hain).
            - 'OFF_TOPIC': Only for topics that clearly cannot relate to a workplace at all — general knowledge trivia, other companies, coding help, entertainment, personal advice, celebrities, politics, etc.

            IMPORTANT: If you are unsure whether a query is COMPANY or OFF_TOPIC, always choose COMPANY. It is far worse to wrongly refuse a legitimate workplace question than to search the documents and find nothing.

            Respond with ONLY the category name, nothing else."""),
            ("user", "{query}")
        ])
        chain = router_prompt | self.llm | StrOutputParser()
        result = chain.invoke({"query": query}).strip().upper()

        if "LEAVE_REQUEST" in result or "LEAVE REQUEST" in result:
            return "LEAVE_REQUEST"
        if "COMPANY" in result:
            return "COMPANY"
        if "GREETING" in result:
            return "GREETING"
        return "OFF_TOPIC"

    def _handle_company_query(self, query: str) -> str:
        """FAISS se data nikal kar RAG ke zariye jawab deta hai"""
        if not self.vector_store:
            return "Mazrat chahta hoon, company ka knowledge base is waqt khali hai ya update ho raha hai. Baraye meherbani admin se raabta karein."

        # SOLUTION: MMR (Maximal Marginal Relevance) search use karein
        # Ye pehle top 15 chunks (fetch_k) nikalega, phir unme se 5 sab se 'diverse' 
        # chunks select karega. Is tarah duplicate documents context window crowding nahi karenge!
        docs = self.vector_store.max_marginal_relevance_search(
            query, 
            k=5,          # AI ko final 5 chunks bhejein
            fetch_k=15    # Database se pehle 15 nikal kar unme se best 5 diverse chunein
        )
        
        context = "\n\n".join([doc.page_content for doc in docs])

        rag_prompt = ChatPromptTemplate.from_messages([
            ("system", f"""You are the ISL Assistant for Industrial Solutions Ltd (ISL).
            Answer the question using ONLY the provided context below.
            If the answer is not present in the context, politely say (in Roman Urdu) that
            you do not have specific information on this and the user should contact the
            relevant department or admin.

            {self._LANGUAGE_RULE}

            Context: {{context}}"""),
            ("user", "{query}")
        ])
        chain = rag_prompt | self.llm | StrOutputParser()
        return chain.invoke({"context": context, "query": query})

    def _handle_greeting(self, query: str) -> str:
        """Sirf greetings/small talk ka short jawab, ISL assistant ke tor par"""
        greeting_prompt = ChatPromptTemplate.from_messages([
            ("system", f"""You are the ISL Assistant for Industrial Solutions Ltd (ISL).
            Respond briefly and warmly to this greeting/small talk, and mention that you
            can only help with ISL company-related questions (policies, documents, safety,
            departments, etc).

            {self._LANGUAGE_RULE}"""),
            ("user", "{query}")
        ])
        chain = greeting_prompt | self.llm | StrOutputParser()
        return chain.invoke({"query": query})

    def _handle_leave_request(self, query: str) -> str:
        """User leave/chutti maang raha hai. Seedha submit nahi karte -- pehle
        confirm karte hain, taake accidental/misread intent par leave apply
        na ho jaye. Actual submission ChatAskView se /api/leave/apply/ ke
        zariye, frontend ke leave-form ke through hoti hai (is method mein
        nahi), taake leave type aur reason properly structured collect ho.
        """
        confirm_prompt = ChatPromptTemplate.from_messages([
            ("system", f"""You are the ISL Assistant for Industrial Solutions Ltd (ISL).
            The user wants to apply for leave. Respond briefly and warmly, confirming
            that you can prepare and submit a leave application for them right now,
            and that they should select the leave type and provide a short reason
            in the form that will appear below.

            {self._LANGUAGE_RULE}"""),
            ("user", "{query}")
        ])
        chain = confirm_prompt | self.llm | StrOutputParser()
        return chain.invoke({"query": query})

    def _handle_off_topic(self, query: str) -> str:
        """ISL se related na hone wale sawalat ko politely refuse karta hai"""
        off_topic_prompt = ChatPromptTemplate.from_messages([
            ("system", f"""You are the ISL Assistant for Industrial Solutions Ltd (ISL).
            The user's question is NOT related to ISL company matters. Politely apologize
            and explain that this topic is outside your domain, and that you can only help
            with ISL-related company questions (policies, documents, safety, departments, HR, etc).
            Do NOT attempt to answer the actual question, no matter what it is.

            {self._LANGUAGE_RULE}"""),
            ("user", "{query}")
        ])
        chain = off_topic_prompt | self.llm | StrOutputParser()
        return chain.invoke({"query": query})

    def process_query(self, query: str) -> dict:
        """Main Pipeline.

        Returns a dict {"answer": str, "intent": str} instead of a bare
        string, so the caller (ChatAskView) knows when to trigger the
        leave-application form on the frontend (intent == 'LEAVE_REQUEST').
        """
        intent = self._semantic_router(query)

        if intent == "LEAVE_REQUEST":
            answer = self._handle_leave_request(query)
        elif intent == "COMPANY":
            answer = self._handle_company_query(query)
        elif intent == "GREETING":
            answer = self._handle_greeting(query)
        else:
            answer = self._handle_off_topic(query)

        answer = self._sanitize_hindi_words(answer)
        return {"answer": answer, "intent": intent}