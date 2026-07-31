import os
import datetime
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

    # Har prompt ke sath yeh common language rule attach hota hai. Rule ab
    # user ki apni query ki language MIRROR karta hai (English sawal ->
    # English jawab, Urdu/Roman Urdu sawal -> Roman Urdu jawab) -- sirf
    # Hindi/Devanagari har surat mein banned hai, chahe jawab English ho
    # ya Urdu. Pehle ye rule hamesha Urdu force karta tha chahe user ne
    # English mein poocha ho, jo galat tha.
    _LANGUAGE_RULE = (
        "STRICT LANGUAGE RULE: Detect the language of the user's message and reply in "
        "THAT SAME language:\n"
        "- If the user's message is written in English, respond ONLY in English.\n"
        "- If the user's message is written in Urdu -- whether in Roman Urdu (Urdu "
        "written in Latin/English script) or in Urdu script -- respond ONLY in Roman "
        "Urdu (Urdu written in Latin/English script).\n"
        "Do not mix languages within a single reply, and do not default to Urdu just "
        "because that is your usual style -- match the user's message.\n\n"
        "HOWEVER, one exception applies regardless of the above: NEVER respond in Hindi "
        "or Devanagari script under any circumstance, even if the user's message itself "
        "is in Hindi or Devanagari -- treat Hindi input the same as Urdu input and reply "
        "in Roman Urdu instead.\n"
        "In particular, when replying in Roman Urdu, NEVER use these Hindi-origin words "
        "-- always use the Urdu word given instead:\n"
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

    def rebuild_index_from_paths(self, docs_info: list) -> None:
        """
        Department Head/Admin ke upload kiye hue (active + approved) documents
        se FAISS index dobara bana kar memory (self.vector_store) aur disk
        (faiss_index/) dono par update karta hai. Ye views.py ke
        sync_vector_store() se call hota hai jab bhi koi document
        upload/activate/deactivate/delete/approve/reject ho.

        docs_info: list of dicts, one per active+approved Document:
            {'path': <file path str>, 'doc_id': <id>, 'doc_title': <str>,
             'department_ids': [<int>, ...]}
        department_ids=[] means the document has no department restriction
        (a general/company-wide document, visible to everyone). This is
        tagged onto every resulting chunk's metadata so
        _handle_company_query() can filter retrieval results to only what
        the querying user's department is actually allowed to see --
        without this, ANY indexed document (e.g. an IT-only document) was
        searchable by ANY user regardless of department.

        Note: Yeh poora index rebuild karta hai (incremental add nahi), taake
        deactivate/delete hone wale documents bhi index se saaf tarah hat jayein.
        Chotay/medium document counts (kuch sau tak) ke liye ye theek hai; agar
        documents ki tadaad bohat zyada ho jaye to isay incremental update mein
        badalna zaroori hoga.
        """
        if not docs_info:
            # Koi active/approved document nahi bacha, index khali kar dein
            self.vector_store = None
            return

        text_splitter = RecursiveCharacterTextSplitter(
            chunk_size=1000,
            chunk_overlap=200,
            separators=["\n\n", "\n", ".", " ", ""]
        )

        all_chunks = []
        for info in docs_info:
            path = info.get('path')
            if not path:
                continue
            try:
                # PyPDFLoader ki jagah apna custom loader use karein
                pages = _load_pages(path)
            except Exception as e:
                # Ek kharab/corrupt file poore index ko fail na kare
                print(f"[ISLChatBotService] Warning: could not load '{path}': {e}")
                continue

            doc_chunks = text_splitter.split_documents(pages)
            for chunk in doc_chunks:
                chunk.metadata['doc_id'] = str(info.get('doc_id', ''))
                chunk.metadata['doc_title'] = info.get('doc_title', '')
                chunk.metadata['department_ids'] = info.get('department_ids', [])
            all_chunks.extend(doc_chunks)

        if not all_chunks:
            self.vector_store = None
            return

        self.vector_store = FAISS.from_documents(all_chunks, self.embeddings)
        self.vector_store.save_local(self.vector_store_path)

        try:
            timestamp_file = os.path.join(self.vector_store_path, "sync_timestamp.txt")
            with open(timestamp_file, "w") as f:
                f.write(datetime.datetime.now().isoformat())
        except Exception as e:
            print(f"[ISLChatBotService] Warning: could not save sync timestamp: {e}")


    def _semantic_router(self, query: str) -> str:
        """Query ka intent samajhta hai: LEAVE_REQUEST, COMPANY, GREETING ya OFF_TOPIC"""
        router_prompt = ChatPromptTemplate.from_messages([
            ("system", """You are a strict classification AI for Industrial Solutions Ltd (ISL).
            Categorize the query into EXACTLY ONE of these categories:
            - 'LEAVE_REQUEST': ONLY if the user is expressing an intent to actually APPLY FOR or
              TAKE leave/chutti/off right now for themselves (e.g. "leave chahiye", "mujhe chutti
              chahiye", "leave apply karni hai", "I want to apply for sick leave", "kal chutti karni
              hai", "mujhe parson off chahiye"). This takes priority over COMPANY, but ONLY for this
              narrow "wants to take leave now" case.
            - 'COMPANY': If it could plausibly relate to ISL's workplace in any way — company documents,
              policies, workers, departments, safety, HR, equipment, machines, facilities, procedures,
              manuals, or any specific ISL guideline. This includes questions about specific
              equipment/machines/systems (e.g. vending machines, boilers, safety gear) even if "ISL" or
              "company" is not explicitly mentioned, since these are commonly covered in internal manuals.
              IMPORTANT: this also includes any INFORMATIONAL question ABOUT the leave policy itself —
              e.g. "how many days of leave am I entitled to", "what is the sick leave policy", "leave
              apply karne ka process kya hai", "kitni leave milti hai", "what happens if I resign", "how
              much notice period is required". These are requests for INFORMATION, not a request to take
              leave, so they are COMPANY, never LEAVE_REQUEST — even though the word "leave" appears.
            - 'GREETING': If it is only a greeting or small talk directed at the assistant (hi, hello, salam, thank you, how are you, aap kon hain).
            - 'OFF_TOPIC': Only for topics that clearly cannot relate to a workplace at all — general knowledge trivia, other companies, coding help, entertainment, personal advice, celebrities, politics, etc.

            DISAMBIGUATION RULE: Ask yourself "Is the user asking me to DO something (submit/start a
            leave application for them right now), or are they asking a QUESTION about policy/facts?"
            Only the former is LEAVE_REQUEST. A question containing the word "leave", "chutti", or a
            number of days is still just COMPANY if it is asking for information rather than requesting
            an action.

            ALSO NOTE: the word "leave" has other everyday meanings unrelated to time-off from work
            (e.g. "leave a message", "leave a review", "don't leave without saying bye", "leave the
            building"). These are NOT leave-of-absence requests at all — classify them as COMPANY or
            OFF_TOPIC based on their actual subject, never LEAVE_REQUEST, just because the word "leave"
            appears.

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

    # Best-effort, non-LLM language guess -- used ONLY for the one hardcoded
    # fallback string below (vector store empty), since that path returns
    # before ever calling the LLM and so can't rely on the model's own
    # language-matching. Not meant to be perfect; common English function
    # words vs. common Roman Urdu words is enough to catch the obvious case.
    _ENGLISH_HINT_WORDS = {
        "the", "is", "are", "what", "where", "when", "how", "please",
        "can", "could", "would", "should", "do", "does", "did", "i", "you",
    }

    @classmethod
    def _looks_like_english(cls, query: str) -> bool:
        words = re.findall(r"[a-zA-Z']+", query.lower())
        if not words:
            return False
        hits = sum(1 for w in words if w in cls._ENGLISH_HINT_WORDS)
        return hits / len(words) >= 0.3

    @staticmethod
    def _allowed_department_ids(user):
        """None means unrestricted (Admin/superuser see every department's
        documents). Otherwise a list containing the user's own department id
        (or an empty list if they have none) -- used by _doc_chunk_allowed
        below to filter retrieval results."""
        if user is None:
            return None
        if getattr(user, 'is_superuser', False) or getattr(user, 'role', None) == 'ADMIN':
            return None
        dept_id = getattr(user, 'department_id', None)
        return [dept_id] if dept_id else []

    @staticmethod
    def _doc_chunk_allowed(chunk_metadata, allowed_dept_ids) -> bool:
        """Checks a retrieved chunk's department_ids (tagged at index time
        in rag_utils.py / rebuild_index_from_paths above) against what the
        querying user is allowed to see."""
        if allowed_dept_ids is None:
            return True
        doc_dept_ids = chunk_metadata.get('department_ids') or []
        if not doc_dept_ids:
            return True  # general/company-wide document, no restriction
        return any(d in allowed_dept_ids for d in doc_dept_ids)

    def _handle_company_query(self, query: str, user=None) -> str:
        """FAISS se data nikal kar RAG ke zariye jawab deta hai.

        SECURITY: retrieved chunks are filtered to only what the querying
        user is actually allowed to see (their own department's documents,
        plus any company-wide documents with no department restriction).
        Admin/superuser see everything. Without this filter, any indexed
        document (e.g. one uploaded for IT only) was retrievable in any
        user's chat answers regardless of their department."""
        if not self.vector_store:
            if self._looks_like_english(query):
                return ("Sorry, the company knowledge base is currently empty or being "
                         "updated. Please contact the admin.")
            return "Mazrat chahta hoon, company ka knowledge base is waqt khali hai ya update ho raha hai. Baraye meherbani admin se raabta karein."

        allowed_dept_ids = self._allowed_department_ids(user)

        # SOLUTION: MMR (Maximal Marginal Relevance) search use karein
        # Ye pehle top 40 chunks (fetch_k) nikalega, phir unme se 20 sab se
        # 'diverse' chunks select karega. Over-fetching (20 instead of the
        # final 5) so the department filter below still has enough left to
        # choose from -- if we only pulled 5 upfront and most got filtered
        # out for department access, we could end up with too little (or
        # no) context even when relevant, permitted documents exist.
        candidates = self.vector_store.max_marginal_relevance_search(
            query,
            k=20,
            fetch_k=40,
        )

        docs = [d for d in candidates if self._doc_chunk_allowed(d.metadata, allowed_dept_ids)][:5]

        if not docs:
            # Matches may exist in the knowledge base, but none are visible
            # to this user's department -- say so explicitly rather than
            # silently falling through to a generic "no info" answer that
            # would look identical to a true no-match case.
            if self._looks_like_english(query):
                return ("I couldn't find information on this within your department's "
                        "accessible documents. Please contact the relevant department or admin.")
            return ("Mujhe aapke department ke accessible documents mein is baray mein "
                    "maloomat nahi mili. Baraye meherbani mutaliqa department ya admin se "
                    "rabta karein.")

        context = "\n\n".join([doc.page_content for doc in docs])

        rag_prompt = ChatPromptTemplate.from_messages([
            ("system", f"""You are the ISL Assistant for Industrial Solutions Ltd (ISL).
            Answer the question using ONLY the provided context below.
            If the answer is not present in the context, politely say (matching the
            user's language per the rule below) that you do not have specific
            information on this and the user should contact the relevant department
            or admin.

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

    def process_query(self, query: str, user=None) -> dict:
        """Main Pipeline.

        Returns a dict {"answer": str, "intent": str} instead of a bare
        string, so the caller (ChatAskView) knows when to trigger the
        leave-application form on the frontend (intent == 'LEAVE_REQUEST').

        `user` is threaded through to _handle_company_query so retrieval
        can be filtered to only documents that user's department is
        allowed to see (see _allowed_department_ids / _doc_chunk_allowed
        above).
        """
        intent = self._semantic_router(query)

        if intent == "LEAVE_REQUEST":
            answer = self._handle_leave_request(query)
        elif intent == "COMPANY":
            answer = self._handle_company_query(query, user)
        elif intent == "GREETING":
            answer = self._handle_greeting(query)
        else:
            answer = self._handle_off_topic(query)

        answer = self._sanitize_hindi_words(answer)
        return {"answer": answer, "intent": intent}