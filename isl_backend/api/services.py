import os
import json
import shutil
import datetime
import re
from collections import OrderedDict
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
    """
    RAG service backed by a SHARDED FAISS knowledge base (one index per
    department, plus a shared "common" index) instead of one monolithic
    index. See the shard-management block below for the full design; the
    short version:

      faiss_index/
        doc_shard_map.json          <- global doc_id -> shard_key lookup
        common/                     <- always loaded; docs with 0 or 2+
                                        linked departments live here
        dept_<department_id>/       <- docs linked to EXACTLY one
                                        department; lazy-loaded, LRU-capped

    Only `common/` is unconditionally kept in RAM. Department shards are
    loaded on first query and evicted (LRU, capped at
    MAX_LOADED_DEPT_SHARDS) once too many are cached at once -- a Worker's
    query only ever touches their own department's shard + common, never
    the other departments' vectors.

    Documents are also no longer indexed just because they're active --
    see `Document.include_in_chatbot` in models.py / `sync_single_document`
    in views.py, which gates whether index_document() gets called at all.
    """

    # Per-shard chunk registry filename: doc_id -> [chunk_id, ...] for the
    # documents stored IN THAT SHARD. Lets index_document()/remove_document()
    # touch only the one document that changed, without reprocessing
    # anything else in the same shard.
    CHUNK_REGISTRY_FILENAME = "chunk_registry.json"

    # Global (base-level, not per-shard) file: doc_id -> shard_key. Needed
    # because a document can move between shards over its lifetime (e.g.
    # its department assignment changes from 1 department to 2, which
    # moves it from a dept_<id> shard to the common shard) -- without this,
    # remove_document() wouldn't know which shard's chunks to delete.
    DOC_SHARD_MAP_FILENAME = "doc_shard_map.json"

    COMMON_SHARD_KEY = "common"

    # Max number of department shards kept loaded in RAM at once (LRU-
    # evicted beyond this). The common shard is separate and always loaded.
    MAX_LOADED_DEPT_SHARDS = 10

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

        # Base directory holding every shard's subfolder + the global
        # doc_id -> shard_key map.
        self.base_index_path = "faiss_index"

        # shard_key -> FAISS vector store, for department shards only.
        # OrderedDict so we can LRU-evict (move_to_end on access, pop the
        # oldest when over MAX_LOADED_DEPT_SHARDS).
        self._dept_shard_cache: "OrderedDict[str, FAISS]" = OrderedDict()

        # The common shard is small (only 0-department / multi-department
        # docs) and needed on nearly every query, so it's kept outside the
        # LRU entirely and loaded eagerly here rather than lazily.
        self._common_store = self._load_shard_from_disk(self.COMMON_SHARD_KEY)

        # shard_key -> {doc_id: [chunk_id, ...]}. Kept fully in memory
        # (these are small JSON dicts, unlike the FAISS vector stores) so
        # registry lookups never depend on which shards are LRU-loaded.
        self._shard_registries: dict = {}

        # doc_id (str) -> shard_key, persisted at the base level.
        self._doc_shard_map: dict = self._load_doc_shard_map()

    # -------------------------------------------------------------------
    # Shard path / key helpers
    # -------------------------------------------------------------------
    def _shard_dir(self, shard_key: str) -> str:
        return os.path.join(self.base_index_path, shard_key)

    @staticmethod
    def _shard_key_for_department_ids(department_ids) -> str:
        """Docs linked to EXACTLY one department get their own shard.
        Docs with no department restriction (company-wide) OR linked to
        multiple departments at once go into the shared 'common' shard --
        this avoids duplicating a multi-department doc's chunks across
        several department shards."""
        department_ids = department_ids or []
        if len(department_ids) == 1:
            return f"dept_{department_ids[0]}"
        return ISLChatBotService.COMMON_SHARD_KEY

    def _shard_keys_for_query(self, user) -> list:
        """Which shard(s) a given user's query should search.
        Worker: their own department's shard + common.
        Admin/superuser: common + every dept_* shard that exists on disk
        (per the confirmed design, an Admin query loads whatever isn't
        already cached rather than skipping uncached shards)."""
        allowed_dept_ids = self._allowed_department_ids(user)

        if allowed_dept_ids is None:  # Admin / superuser: everything
            keys = [self.COMMON_SHARD_KEY]
            if os.path.isdir(self.base_index_path):
                for name in sorted(os.listdir(self.base_index_path)):
                    full = os.path.join(self.base_index_path, name)
                    if name.startswith("dept_") and os.path.isdir(full):
                        keys.append(name)
            return keys

        keys = [self.COMMON_SHARD_KEY]
        for dept_id in allowed_dept_ids:
            if dept_id:
                keys.append(f"dept_{dept_id}")
        return keys

    # -------------------------------------------------------------------
    # Shard loading / LRU cache
    # -------------------------------------------------------------------
    def _load_shard_from_disk(self, shard_key: str):
        """Returns a loaded FAISS store for this shard, or None if the
        shard doesn't exist on disk yet (e.g. no document has ever landed
        in that department's shard)."""
        shard_dir = self._shard_dir(shard_key)
        if not os.path.exists(os.path.join(shard_dir, "index.faiss")):
            return None
        try:
            return FAISS.load_local(shard_dir, self.embeddings, allow_dangerous_deserialization=True)
        except Exception as e:
            print(f"[ISLChatBotService] Warning: could not load shard '{shard_key}': {e}")
            return None

    def _cache_dept_shard(self, shard_key: str, store) -> None:
        self._dept_shard_cache[shard_key] = store
        self._dept_shard_cache.move_to_end(shard_key)
        # Evict least-recently-used dept shards beyond the cap. This is
        # purely a RAM-cache eviction -- the shard's data is already
        # persisted on disk, so evicting here just drops the in-memory
        # FAISS object; the next query that needs it lazy-loads it again.
        while len(self._dept_shard_cache) > self.MAX_LOADED_DEPT_SHARDS:
            self._dept_shard_cache.popitem(last=False)

    def _get_shard(self, shard_key: str):
        """Returns the shard's FAISS store, lazy-loading (and LRU-caching,
        for department shards) from disk if needed. None if the shard has
        no documents yet."""
        if shard_key == self.COMMON_SHARD_KEY:
            return self._common_store

        if shard_key in self._dept_shard_cache:
            self._dept_shard_cache.move_to_end(shard_key)
            return self._dept_shard_cache[shard_key]

        store = self._load_shard_from_disk(shard_key)
        if store is not None:
            self._cache_dept_shard(shard_key, store)
        return store

    def _set_shard(self, shard_key: str, store) -> None:
        """Registers a freshly created (or just-modified) shard's vector
        store in the right cache slot."""
        if shard_key == self.COMMON_SHARD_KEY:
            self._common_store = store
        else:
            self._cache_dept_shard(shard_key, store)

    def _save_shard(self, shard_key: str) -> None:
        shard_dir = self._shard_dir(shard_key)
        os.makedirs(shard_dir, exist_ok=True)
        store = self._get_shard(shard_key)
        if store is not None:
            store.save_local(shard_dir)
        registry = self._shard_registries.get(shard_key, {})
        try:
            with open(os.path.join(shard_dir, self.CHUNK_REGISTRY_FILENAME), "w", encoding="utf-8") as f:
                json.dump(registry, f)
        except Exception as e:
            print(f"[ISLChatBotService] Warning: could not save registry for shard '{shard_key}': {e}")

    # -------------------------------------------------------------------
    # Per-shard chunk registry (doc_id -> chunk_ids within that shard)
    # -------------------------------------------------------------------
    def _get_shard_registry(self, shard_key: str) -> dict:
        if shard_key not in self._shard_registries:
            path = os.path.join(self._shard_dir(shard_key), self.CHUNK_REGISTRY_FILENAME)
            if os.path.exists(path):
                try:
                    with open(path, "r", encoding="utf-8") as f:
                        self._shard_registries[shard_key] = json.load(f)
                except Exception as e:
                    print(f"[ISLChatBotService] Warning: could not load registry for "
                          f"shard '{shard_key}', starting empty: {e}")
                    self._shard_registries[shard_key] = {}
            else:
                self._shard_registries[shard_key] = {}
        return self._shard_registries[shard_key]

    # -------------------------------------------------------------------
    # Global doc_id -> shard_key map persistence
    # -------------------------------------------------------------------
    def _doc_shard_map_path(self) -> str:
        return os.path.join(self.base_index_path, self.DOC_SHARD_MAP_FILENAME)

    def _load_doc_shard_map(self) -> dict:
        path = self._doc_shard_map_path()
        if not os.path.exists(path):
            return {}
        try:
            with open(path, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception as e:
            print(f"[ISLChatBotService] Warning: could not load doc_shard_map, "
                  f"starting empty (a full resync will rebuild it correctly): {e}")
            return {}

    def _save_doc_shard_map(self) -> None:
        os.makedirs(self.base_index_path, exist_ok=True)
        try:
            with open(self._doc_shard_map_path(), "w", encoding="utf-8") as f:
                json.dump(self._doc_shard_map, f)
        except Exception as e:
            print(f"[ISLChatBotService] Warning: could not save doc_shard_map: {e}")

    def _wipe_all_shards(self) -> None:
        """Used only by rebuild_index_from_paths (full/bulk rebuild) --
        clears every shard on disk and in memory so it can be rebuilt from
        scratch, cleanly (no leftover documents from before)."""
        if os.path.isdir(self.base_index_path):
            shutil.rmtree(self.base_index_path)
        os.makedirs(self.base_index_path, exist_ok=True)
        self._common_store = None
        self._dept_shard_cache = OrderedDict()
        self._shard_registries = {}
        self._doc_shard_map = {}

    # -------------------------------------------------------------------
    # Language rule (unchanged)
    # -------------------------------------------------------------------
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
        Full/bulk (re)index of every given (active + include_in_chatbot)
        document, from scratch. Wipes every shard first, then re-adds each
        document via `index_document()` so it lands in the correct shard
        (department-specific or common) based on its department_ids.

        docs_info: list of dicts, one per active+include_in_chatbot
        Document: {'path': <file path str>, 'doc_id': <id>,
                   'doc_title': <str>, 'department_ids': [<int>, ...]}

        Used only for bulk/initial backfill (the `sync_faiss_index`
        management command) and as a manual escape hatch if any shard's
        registry / doc_shard_map ever drifts out of sync and needs a
        clean, from-scratch rebuild. Per-document actions (upload,
        activate/deactivate, chatbot-inclusion toggle, approve/reject,
        replace, delete) call the targeted `index_document()` /
        `remove_document()` methods below instead, so a single document
        change doesn't touch any other document's shard.
        """
        self._wipe_all_shards()

        if not docs_info:
            return

        for info in docs_info:
            path = info.get("path")
            if not path:
                continue
            self.index_document(
                doc_id=info.get("doc_id", ""),
                doc_title=info.get("doc_title", ""),
                department_ids=info.get("department_ids", []),
                path=path,
            )

        try:
            timestamp_file = os.path.join(self.base_index_path, "sync_timestamp.txt")
            with open(timestamp_file, "w") as f:
                f.write(datetime.datetime.now().isoformat())
        except Exception as e:
            print(f"[ISLChatBotService] Warning: could not save sync timestamp: {e}")

    # -------------------------------------------------------------------
    # Targeted (incremental) indexing -- touches only the ONE shard that
    # the changed document belongs to.
    # -------------------------------------------------------------------
    def index_document(self, doc_id, doc_title, department_ids, path) -> bool:
        """(Re-)adds ONE document's chunks to its shard (a single-
        department shard, or 'common' for company-wide / multi-department
        docs -- see `_shard_key_for_department_ids`). Safe to call for a
        document that's already indexed, including if its department
        assignment changed since -- its old chunks are removed first
        (from whichever shard they were in, via doc_shard_map), so this
        also serves as the "update"/"move" path. Returns True on success."""
        doc_id = str(doc_id)
        department_ids = department_ids or []
        new_shard_key = self._shard_key_for_department_ids(department_ids)

        # Drop any existing chunks for this doc_id first (from whichever
        # shard it's currently in -- may differ from new_shard_key if the
        # document's departments changed), so replacing a file or moving
        # it between shards doesn't leave stale chunks behind.
        self.remove_document(doc_id, _skip_save=True)

        try:
            pages = _load_pages(path)
        except Exception as e:
            print(f"[ISLChatBotService.index_document] Could not load '{path}': {e}")
            return False

        text_splitter = RecursiveCharacterTextSplitter(
            chunk_size=1000, chunk_overlap=200, separators=["\n\n", "\n", ".", " ", ""],
        )
        chunks = text_splitter.split_documents(pages)
        if not chunks:
            self._save_doc_shard_map()
            return False

        for chunk in chunks:
            chunk.metadata['doc_id'] = doc_id
            chunk.metadata['doc_title'] = doc_title
            chunk.metadata['department_ids'] = department_ids

        store = self._get_shard(new_shard_key)
        if store is None:
            store = FAISS.from_documents(chunks, self.embeddings)
            # FAISS.from_documents doesn't hand back ids directly; read
            # them off the freshly-built docstore instead.
            new_ids = list(store.docstore._dict.keys())
            self._set_shard(new_shard_key, store)
        else:
            new_ids = store.add_documents(chunks)

        registry = self._get_shard_registry(new_shard_key)
        registry[doc_id] = [str(i) for i in new_ids]
        self._doc_shard_map[doc_id] = new_shard_key

        self._save_shard(new_shard_key)
        self._save_doc_shard_map()
        return True

    def remove_document(self, doc_id, _skip_save: bool = False) -> bool:
        """Removes ONE document's chunks from its shard (looked up via
        doc_shard_map), without touching any other shard or any other
        document's vectors. Safe no-op if the doc was never indexed (e.g.
        rejecting a still-PENDING document, or one with
        include_in_chatbot=False)."""
        doc_id = str(doc_id)
        shard_key = self._doc_shard_map.get(doc_id)
        if shard_key is None:
            return False

        registry = self._get_shard_registry(shard_key)
        chunk_ids = registry.pop(doc_id, None)
        store = self._get_shard(shard_key)

        if chunk_ids and store is not None:
            try:
                store.delete(ids=chunk_ids)
            except Exception as e:
                print(f"[ISLChatBotService.remove_document] Could not delete chunks "
                      f"for doc_id={doc_id} in shard '{shard_key}': {e}")

        self._doc_shard_map.pop(doc_id, None)

        if not _skip_save:
            self._save_shard(shard_key)
            self._save_doc_shard_map()
        return bool(chunk_ids)

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

        Retrieval is now SHARDED by department (see the shard-management
        block above `_semantic_router`): a Worker's query only ever loads
        their own department's shard + the always-loaded common shard, so
        a single query never has to touch the other departments' vectors
        at all. An Admin query loads every shard (lazy-loading any that
        aren't currently cached) since Admin can see everything.

        SECURITY: even though shards already scope most of this, a chunk
        in the common shard can still belong to a *subset* of departments
        (e.g. a 2-department document) that doesn't include this user's
        own department -- so the metadata filter below stays as the final
        per-chunk check regardless of which shard(s) were searched.
        Admin/superuser see everything."""
        allowed_dept_ids = self._allowed_department_ids(user)
        shard_keys = self._shard_keys_for_query(user)

        candidates = []
        for shard_key in shard_keys:
            store = self._get_shard(shard_key)
            if store is None:
                continue
            # Over-fetch per shard (k=10, fetch_k=20) so the department
            # filter below still has enough candidates left to choose
            # from after combining every searched shard's results --
            # mirrors the same over-fetch reasoning the old single-index
            # search used (there it was k=20/fetch_k=40 against one
            # index; here it's a smaller budget per shard since results
            # from multiple shards get merged together below).
            try:
                candidates.extend(store.max_marginal_relevance_search(query, k=10, fetch_k=20))
            except Exception as e:
                print(f"[ISLChatBotService._handle_company_query] Shard '{shard_key}' search failed: {e}")

        if not candidates:
            if self._looks_like_english(query):
                return ("Sorry, the company knowledge base is currently empty or being "
                         "updated. Please contact the admin.")
            return "Mazrat chahta hoon, company ka knowledge base is waqt khali hai ya update ho raha hai. Baraye meherbani admin se raabta karein."

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