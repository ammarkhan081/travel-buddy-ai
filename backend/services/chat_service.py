"""Travel Buddy AI chat service.

Production-ready chat:
- Conversation persistence (chat_conversations + chat_messages tables)
- Hybrid auto-routing (personal-records vs general travel knowledge)
- Embedding-backed RAG over the user's expenses / reminders / diary / voice notes
- Auto-generated conversation titles (ChatGPT-style sidebar names)
- v6 continuity: USER_NAME, LAST_LOCATION, PKR-default currency
"""

import hashlib
import json
import logging
import re
from datetime import datetime, timezone
from typing import Dict, List, Optional, Tuple

import numpy as np
import openai
from sqlalchemy.orm import Session

try:
    from ..config import settings
    from ..models.chat_conversation import ChatConversation
    from ..models.chat_message import ChatMessage
    from ..models.diary_entry import DiaryEntry
    from ..models.expense import Expense
    from ..models.rag_embedding import RagEmbedding
    from ..models.reminder import Reminder
    from ..models.voice_note import VoiceNote
    from ..utils.ai_runtime import call_chat_with_fallback, call_with_retries
    from ..utils.error_policy import ChatError, RetrievalError
    from ..utils.time_utils import now_utc_iso
except ImportError:
    from config import settings
    from models.chat_conversation import ChatConversation
    from models.chat_message import ChatMessage
    from models.diary_entry import DiaryEntry
    from models.expense import Expense
    from models.rag_embedding import RagEmbedding
    from models.reminder import Reminder
    from models.voice_note import VoiceNote
    from utils.ai_runtime import call_chat_with_fallback, call_with_retries
    from utils.error_policy import ChatError, RetrievalError
    from utils.time_utils import now_utc_iso

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Pakistan location detector (cheap, deterministic).
# Used to extract LAST_LOCATION from each turn without spending a model call.
# ---------------------------------------------------------------------------
_PAKISTAN_LOCATIONS = [
    "karachi", "lahore", "islamabad", "rawalpindi", "faisalabad", "multan",
    "peshawar", "quetta", "sialkot", "gujranwala", "hyderabad", "sargodha",
    "bahawalpur", "sukkur", "larkana", "sheikhupura", "rahim yar khan", "abbottabad",
    "mardan", "mingora", "gilgit", "skardu", "chitral", "gwadar", "thar",
    "hunza", "naran", "kaghan", "swat", "murree", "nathiagali", "shogran",
    "babusar", "fairy meadows", "deosai", "shangrila", "khaplu", "kalash",
    "neelum", "azad kashmir", "muzaffarabad",
    "badshahi mosque", "faisal mosque", "minar-e-pakistan", "lahore fort",
    "shalimar gardens", "data darbar", "anarkali", "centaurus", "clifton beach",
    "mohenjo-daro", "taxila",
]


def _extract_pk_location(text: str) -> Optional[str]:
    """Return the first Pakistani location mentioned in text, or None."""
    if not text:
        return None
    lowered = text.lower()
    for loc in sorted(_PAKISTAN_LOCATIONS, key=len, reverse=True):
        if re.search(rf"\b{re.escape(loc)}\b", lowered):
            return " ".join(w.capitalize() for w in loc.split())
    return None


# ---------------------------------------------------------------------------
# Query classification: personal | general | mixed
# ---------------------------------------------------------------------------
_PERSONAL_CUES = [
    "my ", "i spent", "i paid", "i bought", "i visited", "i went",
    "did i ", "have i ", "how much did i", "how much have i",
    "show my", "list my", "my expenses", "my reminders", "my diary",
    "my notes", "my voice notes", "my trip", "what i spent",
    "remind me when", "what reminders",
]

_GENERAL_TRAVEL_CUES = [
    "suggest", "recommend", "best ", "top ", "where ",
    "tell me about", "what is", "what's", "how to reach",
    "how do i get to", "places to visit", "things to do",
    "itinerary", "best time", "weather in", "trip to", "plan a",
    "must-see", "popular", "famous",
]


def _classify_query(text: str) -> str:
    if not text:
        return "general"
    t = text.lower().strip()
    has_personal = any(cue in t for cue in _PERSONAL_CUES)
    has_general = any(cue in t for cue in _GENERAL_TRAVEL_CUES)
    if has_personal and not has_general:
        return "personal"
    if has_general and not has_personal:
        return "general"
    return "mixed"


# ---------------------------------------------------------------------------
# RAG helpers
# ---------------------------------------------------------------------------
def _chunk_text(text: str, max_chars: int = 500, overlap: int = 80) -> List[str]:
    cleaned = (text or "").strip()
    if not cleaned:
        return []
    if len(cleaned) <= max_chars:
        return [cleaned]
    chunks: List[str] = []
    start = 0
    while start < len(cleaned):
        end = min(len(cleaned), start + max_chars)
        chunk = cleaned[start:end].strip()
        if chunk:
            chunks.append(chunk)
        if end >= len(cleaned):
            break
        start = max(0, end - overlap)
    return chunks


def _tokenize(text: str) -> set:
    return set(re.findall(r"[a-zA-Z0-9]+", (text or "").lower()))


def _lexical_overlap_score(query: str, chunk: str) -> float:
    q = _tokenize(query)
    c = _tokenize(chunk)
    if not q or not c:
        return 0.0
    return len(q.intersection(c)) / max(1, len(q))


def _cosine_similarity(a: List[float], b: List[float]) -> float:
    if not a or not b or len(a) != len(b):
        return -1.0
    va = np.array(a, dtype=np.float32)
    vb = np.array(b, dtype=np.float32)
    norm_a = np.linalg.norm(va)
    norm_b = np.linalg.norm(vb)
    if norm_a == 0.0 or norm_b == 0.0:
        return -1.0
    return float(np.dot(va, vb) / (norm_a * norm_b))


def _chunk_hash(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def _build_docs(db: Session, user_id: str) -> List[Tuple[str, int, int, str]]:
    docs: List[Tuple[str, int, int, str]] = []
    for e in db.query(Expense).filter(Expense.user_id == user_id).all():
        doc = f"Expense on {e.date}: amount={e.amount}, category={e.category}, description={e.description or ''}"
        for i, chunk in enumerate(_chunk_text(doc)):
            docs.append(("expense", int(e.id), i, chunk))
    for r in db.query(Reminder).filter(Reminder.user_id == user_id).all():
        doc = f"Reminder at {r.datetime}: title={r.title}, status={r.status}, location={r.location or ''}, transcript={r.transcript or ''}"
        for i, chunk in enumerate(_chunk_text(doc)):
            docs.append(("reminder", int(r.id), i, chunk))
    for d in db.query(DiaryEntry).filter(DiaryEntry.user_id == user_id).all():
        doc = f"Diary {d.timestamp}: title={d.title}. content={d.content}. location={d.location or ''}"
        for i, chunk in enumerate(_chunk_text(doc)):
            docs.append(("diary", int(d.id), i, chunk))
    for v in db.query(VoiceNote).filter(VoiceNote.user_id == user_id).all():
        transcript = (v.transcript or "").strip()
        if not transcript:
            continue
        doc = f"Voice note {v.timestamp or v.created_at or ''}: transcript={transcript}"
        for i, chunk in enumerate(_chunk_text(doc)):
            docs.append(("voice_note", int(v.id), i, chunk))
    return docs


def _sync_embedding_cache(db: Session, client: openai.OpenAI, user_id: str) -> None:
    docs = _build_docs(db, user_id)
    current = {(t, sid, idx): txt for t, sid, idx, txt in docs}
    existing_rows = db.query(RagEmbedding).filter(RagEmbedding.user_id == user_id).all()
    existing = {(r.source_type, r.source_id, r.chunk_index): r for r in existing_rows}
    for key in [k for k in existing if k not in current]:
        db.delete(existing[key])
    to_embed_keys = []
    to_embed_texts = []
    for key, text in current.items():
        h = _chunk_hash(text)
        row = existing.get(key)
        if row is None or row.chunk_hash != h:
            to_embed_keys.append((key, h))
            to_embed_texts.append(text)
    if to_embed_texts:
        emb_resp = call_with_retries(
            "rag_embedding_upsert",
            lambda: client.embeddings.create(model=settings.OPENAI_EMBEDDING_MODEL, input=to_embed_texts),
        )
        for ((key, h), emb_item, text) in zip(to_embed_keys, emb_resp.data, to_embed_texts):
            source_type, source_id, chunk_index = key
            vec = emb_item.embedding
            row = existing.get(key)
            if row is None:
                row = RagEmbedding(
                    user_id=user_id, source_type=source_type, source_id=source_id,
                    chunk_index=chunk_index, chunk_hash=h, chunk_text=text,
                    embedding_json=json.dumps(vec),
                    updated_at=datetime.now(timezone.utc).isoformat(),
                )
                db.add(row)
            else:
                row.chunk_hash = h
                row.chunk_text = text
                row.embedding_json = json.dumps(vec)
                row.updated_at = datetime.now(timezone.utc).isoformat()
    db.commit()


def _retrieve_relevant_context(query, db, user_id, client, top_k=6, threshold=None) -> str:
    try:
        rows = db.query(RagEmbedding).filter(RagEmbedding.user_id == user_id).all()
        if not rows:
            return "NO_CONTEXT"
        query_emb = call_with_retries(
            "rag_query_embedding",
            lambda: client.embeddings.create(model=settings.OPENAI_EMBEDDING_MODEL, input=query),
        ).data[0].embedding
        scored = []
        for row in rows:
            emb = json.loads(row.embedding_json)
            semantic = _cosine_similarity(query_emb, emb)
            lexical = _lexical_overlap_score(query, row.chunk_text)
            scored.append(((0.8 * semantic) + (0.2 * lexical), row))
        scored.sort(key=lambda x: x[0], reverse=True)
        eff = threshold if threshold is not None else settings.RAG_SIMILARITY_THRESHOLD
        top = [p for p in scored[:top_k] if p[0] >= eff]
        if not top:
            return "NO_CONTEXT"
        lines = ["RETRIEVED USER RECORDS (ground truth for personal questions):"]
        for score, row in top:
            src = f"{row.source_type}:{row.source_id}:{row.chunk_index}"
            lines.append(f"- [{src}] (sim={score:.3f}) {row.chunk_text}")
        return "\n".join(lines)[: settings.CHAT_MAX_CONTEXT_CHARS]
    except Exception as e:
        logger.error("rag_retrieval_failed", extra={"event": "rag_retrieval_failed", "error": str(e)})
        raise RetrievalError(f"RAG retrieval failed: {e}") from e


# ---------------------------------------------------------------------------
# Client + history helpers
# ---------------------------------------------------------------------------
def make_openai_client() -> openai.OpenAI:
    return openai.OpenAI(api_key=settings.OPENAI_API_KEY, timeout=30.0)


def _load_history_messages(db: Session, conversation_id: int, user_id: str) -> List[Dict[str, str]]:
    rows = (
        db.query(ChatMessage)
        .filter(ChatMessage.conversation_id == conversation_id, ChatMessage.user_id == user_id)
        .order_by(ChatMessage.id.asc())
        .all()
    )
    return [{"role": r.role, "content": r.content} for r in rows]


def _cap_messages(messages: List[Dict[str, str]]) -> List[Dict[str, str]]:
    capped = messages[-settings.CHAT_MAX_HISTORY_MESSAGES:]
    compact = []
    budget = 6000
    for m in reversed(capped):
        content = (m.get("content") or "")[:1500]
        role = m.get("role") or "user"
        if not content:
            continue
        if budget - len(content) <= 0:
            break
        budget -= len(content)
        compact.append({"role": role, "content": content})
    return list(reversed(compact))


# ---------------------------------------------------------------------------
# Prompt builders
# ---------------------------------------------------------------------------
_BASE_PERSONA = (
    "You are Travel Buddy AI, a warm and knowledgeable travel companion focused on Pakistan.\n"
    "Voice: friendly, concise, professional. You can use **bold** and bullet lists. "
    "Default all prices, budgets, and costs to PKR. Only switch to USD if the user explicitly asks.\n"
)


def _build_system_prompt(query_type, user_name, last_location, retrieved_context):
    name_line = (
        "The user's name is " + str(user_name) + ". Use it naturally when greeting or wrapping up."
    ) if user_name else ""
    location_line = (
        "The last location discussed in this conversation is: " + str(last_location) + ". "
        "If the user asks a follow-up like 'how do I get there', 'what's the weather like there', or 'how long does it take', "
        "silently inherit this location instead of asking them to repeat it."
    ) if last_location else ""

    if query_type == "personal":
        grounding = (
            "GROUNDING RULE: This question is about the user's own records.\n"
            "Use ONLY the [RETRIEVED USER RECORDS] block below for facts about their expenses, reminders, "
            "diary entries, or voice notes. If that block says NO_CONTEXT, clearly say you do not have that record yet.\n"
            "Do not invent amounts, dates, places, or any other personal detail."
        )
    elif query_type == "general":
        grounding = (
            "ANSWER MODE: General travel knowledge.\n"
            "Use your own knowledge to give specific, useful suggestions. Name real places, brief reasons why, "
            "and rough prices in PKR when relevant. Keep itineraries practical (transport, time, must-sees). "
            "You may still cite the [RETRIEVED USER RECORDS] block if anything there is naturally relevant, but "
            "do not force it."
        )
    else:
        grounding = (
            "ANSWER MODE: Hybrid. The query might be personal, general, or both.\n"
            "If [RETRIEVED USER RECORDS] contains relevant rows, ground personal facts in them. "
            "For any general travel knowledge, use your own knowledge with specific places and PKR prices. "
            "Never fabricate user records - if records aren't there, say so."
        )

    parts = [_BASE_PERSONA, name_line, location_line, "", grounding, ""]
    parts.append(retrieved_context if retrieved_context else "RETRIEVED USER RECORDS:\nNO_CONTEXT")
    return "\n".join(p for p in parts if p is not None).strip()


# ---------------------------------------------------------------------------
# Title generation
# ---------------------------------------------------------------------------
def _heuristic_title(first_message: str) -> str:
    words = re.findall(r"[A-Za-z0-9]+", first_message)[:6]
    if not words:
        return "New Chat"
    title = " ".join(words)
    return (title[:48] + "...") if len(title) > 48 else title


def _generate_title(client: openai.OpenAI, first_message: str) -> str:
    try:
        content, _ = call_chat_with_fallback(
            client=client,
            messages=[
                {"role": "system", "content": (
                    "Generate a 3 to 6 word title for a chat conversation. "
                    "Use Title Case. No quotes, no punctuation at the end, "
                    "no prefixes like 'Chat:' or 'Title:'. Just the title."
                )},
                {"role": "user", "content": first_message[:500]},
            ],
            temperature=0.3,
            response_format=None,
            primary_model=settings.OPENAI_MODEL,
            label="chat_title",
        )
        clean = re.sub(r'["\'`]', "", (content or "").strip()).strip(".!? ")
        if not clean:
            return _heuristic_title(first_message)
        return (clean[:48] + "...") if len(clean) > 48 else clean
    except Exception as e:
        logger.warning("chat_title_generation_failed", extra={"error": str(e)})
        return _heuristic_title(first_message)


# ---------------------------------------------------------------------------
# Conversation CRUD
# ---------------------------------------------------------------------------
def list_conversations(db: Session, user_id: str) -> List[ChatConversation]:
    return (
        db.query(ChatConversation)
        .filter(ChatConversation.user_id == user_id)
        .order_by(ChatConversation.updated_at.desc())
        .all()
    )


def create_conversation(db: Session, user_id: str, title: str = "New Chat") -> ChatConversation:
    now = now_utc_iso()
    conv = ChatConversation(
        user_id=user_id, title=title, last_location=None, last_intent=None,
        created_at=now, updated_at=now,
    )
    db.add(conv)
    db.commit()
    db.refresh(conv)
    return conv


def get_conversation(db: Session, conv_id: int, user_id: str) -> Optional[ChatConversation]:
    return (
        db.query(ChatConversation)
        .filter(ChatConversation.id == conv_id, ChatConversation.user_id == user_id)
        .first()
    )


def list_messages(db: Session, conv_id: int, user_id: str) -> List[ChatMessage]:
    return (
        db.query(ChatMessage)
        .filter(ChatMessage.conversation_id == conv_id, ChatMessage.user_id == user_id)
        .order_by(ChatMessage.id.asc())
        .all()
    )


def delete_conversation(db: Session, conv_id: int, user_id: str) -> bool:
    conv = get_conversation(db, conv_id, user_id)
    if not conv:
        return False
    db.query(ChatMessage).filter(
        ChatMessage.conversation_id == conv_id, ChatMessage.user_id == user_id,
    ).delete(synchronize_session=False)
    db.delete(conv)
    db.commit()
    return True


# ---------------------------------------------------------------------------
# Main turn handler
# ---------------------------------------------------------------------------
async def handle_user_turn(db, conversation, user_message, user_id, user_name=None):
    text = (user_message or "").strip()
    if not text:
        raise ChatError("Empty message.")
    now_iso = now_utc_iso()

    user_row = ChatMessage(
        conversation_id=conversation.id, user_id=user_id, role="user",
        content=text, created_at=now_iso,
    )
    db.add(user_row)
    db.commit()
    db.refresh(user_row)

    query_type = _classify_query(text)

    context = "RETRIEVED USER RECORDS:\nNO_CONTEXT"
    if settings.OPENAI_API_KEY and query_type in {"personal", "mixed"}:
        client = make_openai_client()
        try:
            _sync_embedding_cache(db, client, user_id)
        except Exception as e:
            logger.warning("chat_embedding_sync_before_retrieval_failed", extra={"error": str(e)})
        try:
            threshold = None if query_type == "personal" else max(0.15, settings.RAG_SIMILARITY_THRESHOLD - 0.1)
            retrieved = _retrieve_relevant_context(text, db, user_id, client=client, top_k=6, threshold=threshold)
            if retrieved and retrieved != "NO_CONTEXT":
                context = retrieved
        except RetrievalError as e:
            logger.warning("chat_retrieval_fallback_no_context", extra={"error": str(e)})

    if not settings.OPENAI_API_KEY:
        reply_text = (
            "AI service is not configured yet. Add your OPENAI_API_KEY to backend/.env "
            "and restart the backend to enable Travel Buddy AI chat."
        )
    else:
        system_prompt = _build_system_prompt(
            query_type=query_type, user_name=user_name,
            last_location=conversation.last_location, retrieved_context=context,
        )
        history = _load_history_messages(db, conversation.id, user_id)
        llm_messages = [{"role": "system", "content": system_prompt}] + _cap_messages(history)
        try:
            content, _ = call_chat_with_fallback(
                client=make_openai_client(), messages=llm_messages, temperature=0.4,
                response_format=None, primary_model=settings.OPENAI_MODEL, label="chat_turn",
            )
            reply_text = (content or "").strip() or "I'm here. Could you rephrase that?"
        except Exception as e:
            logger.error("chat_generation_failed", extra={"event": "chat_generation_failed", "error": str(e)})
            reply_text = _fallback_reply(text, context)

    assistant_row = ChatMessage(
        conversation_id=conversation.id, user_id=user_id, role="assistant",
        content=reply_text, created_at=now_utc_iso(),
    )
    db.add(assistant_row)

    new_location = _extract_pk_location(text) or _extract_pk_location(reply_text)
    if new_location:
        conversation.last_location = new_location
    conversation.last_intent = query_type
    conversation.updated_at = now_utc_iso()

    user_msg_count = (
        db.query(ChatMessage)
        .filter(
            ChatMessage.conversation_id == conversation.id,
            ChatMessage.user_id == user_id,
            ChatMessage.role == "user",
        ).count()
    )
    if user_msg_count <= 1 and (not conversation.title or conversation.title.lower() in {"new chat", ""}):
        if settings.OPENAI_API_KEY:
            conversation.title = _generate_title(make_openai_client(), text)
        else:
            conversation.title = _heuristic_title(text)

    db.commit()
    db.refresh(assistant_row)
    db.refresh(conversation)
    return user_row, assistant_row, conversation


def _fallback_reply(last_user_message: str, context: str) -> str:
    if context and context != "RETRIEVED USER RECORDS:\nNO_CONTEXT":
        lines = [ln for ln in context.splitlines() if ln.startswith("-")][:4]
        if lines:
            return "AI service is temporarily unavailable. Here are the closest matching records I found:\n" + "\n".join(lines)
    return "AI service is temporarily unavailable right now. Please try again shortly."


# ---------------------------------------------------------------------------
# Backwards-compat shim for the legacy POST /api/chat/reply route.
# ---------------------------------------------------------------------------
async def generate_chat_response(messages: List[Dict[str, str]], user_id: str, db: Session) -> str:
    if not messages:
        raise ChatError("Empty chat messages.")
    last_user_message = next((m.get("content", "") for m in reversed(messages) if m.get("role") == "user"), "")
    if not settings.OPENAI_API_KEY:
        return _fallback_reply(last_user_message, "")
    query_type = _classify_query(last_user_message)
    client = make_openai_client()
    context = "RETRIEVED USER RECORDS:\nNO_CONTEXT"
    if query_type in {"personal", "mixed"}:
        try:
            _sync_embedding_cache(db, client, user_id)
        except Exception as e:
            logger.warning("chat_embedding_sync_before_retrieval_failed", extra={"error": str(e)})
        try:
            threshold = None if query_type == "personal" else max(0.15, settings.RAG_SIMILARITY_THRESHOLD - 0.1)
            retrieved = _retrieve_relevant_context(last_user_message, db, user_id, client=client, top_k=6, threshold=threshold)
            if retrieved and retrieved != "NO_CONTEXT":
                context = retrieved
        except RetrievalError as e:
            logger.warning("chat_retrieval_fallback_no_context", extra={"error": str(e)})
    system_prompt = _build_system_prompt(
        query_type=query_type, user_name=None, last_location=None, retrieved_context=context,
    )
    llm_messages = [{"role": "system", "content": system_prompt}] + _cap_messages(messages)
    try:
        content, _ = call_chat_with_fallback(
            client=client, messages=llm_messages, temperature=0.4,
            response_format=None, primary_model=settings.OPENAI_MODEL, label="chat_reply_legacy",
        )
        return content.strip()
    except Exception as e:
        logger.error("chat_generation_failed", extra={"event": "chat_generation_failed", "error": str(e)})
        return _fallback_reply(last_user_message, context)


def sync_user_embeddings(db: Session, user_id: str) -> None:
    if not settings.OPENAI_API_KEY:
        return
    client = make_openai_client()
    _sync_embedding_cache(db, client, user_id)


def get_trip_context(db: Session, user_id: str) -> str:
    expenses = db.query(Expense).filter(Expense.user_id == user_id).all()
    reminders = db.query(Reminder).filter(Reminder.user_id == user_id).all()
    diary_entries = db.query(DiaryEntry).filter(DiaryEntry.user_id == user_id).all()
    lines = ["USER TRIP RECORDS:", "", "EXPENSES:"]
    if not expenses:
        lines.append("- No expenses recorded.")
    for e in expenses:
        lines.append(f"- {e.date}: {e.amount} for {e.description} (Category: {e.category})")
    lines.append("")
    lines.append("REMINDERS:")
    if not reminders:
        lines.append("- No reminders set.")
    for r in reminders:
        lines.append(f"- {r.datetime}: {r.title} (Status: {r.status})")
    lines.append("")
    lines.append("DIARY ENTRIES:")
    if not diary_entries:
        lines.append("- No diary entries yet.")
    for d in diary_entries:
        lines.append(f"- {d.timestamp}: {d.title} - {d.content} (Location: {d.location})")
    return "\n".join(lines)
