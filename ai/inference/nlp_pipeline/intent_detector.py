"""Intent detection using OpenAI GPT-4 Turbo and spaCy fallback."""

import logging
import json
import os
import asyncio
from pathlib import Path
from typing import Dict, Optional
import openai
from datetime import datetime, timedelta, timezone
import re
from backend.utils.ai_runtime import call_chat_with_fallback
from backend.utils.error_policy import IntentError
from backend.utils.time_utils import parse_utc_datetime

logger = logging.getLogger(__name__)

_LOCAL_INTENT_MODEL = None
_LOCAL_INTENT_TOKENIZER = None
_LOCAL_INTENT_LABEL_MAP = None
_LOCAL_INTENT_MODEL_PATH = None

# Try to import spaCy for fallback
SPACY_AVAILABLE = False
nlp = None
try:
    import spacy
    try:
        nlp = spacy.load("en_core_web_sm")
        SPACY_AVAILABLE = True
    except OSError:
        logger.warning("spaCy model 'en_core_web_sm' not found. Run: python -m spacy download en_core_web_sm")
        SPACY_AVAILABLE = False
    except Exception as e:
        logger.warning(f"spaCy initialization failed: {e}. Continuing without spaCy fallback.")
        SPACY_AVAILABLE = False
except ImportError:
    logger.warning("spaCy not installed. Install with: pip install spacy")
    SPACY_AVAILABLE = False


async def detect_intent_gpt(
    text: str,
    api_key: Optional[str] = None,
    model: Optional[str] = None,
    user_local_time: Optional[str] = None,
) -> Dict:
    """
    Detect intent and extract entities using OpenAI GPT-4 Turbo.
    
    Args:
        text: Input text
        api_key: OpenAI API key
        model: Model to use
        
    Returns:
        dict with intent, scheduled_time, location, entities
    """
    mode = os.getenv("INTENT_DETECTOR_MODE", "openai").lower()
    local_min_confidence = _normalize_confidence(os.getenv("INTENT_LOCAL_MIN_CONF", 0.7))

    if mode in {"local_first", "local_only"}:
        # Run local inference off the event loop to avoid blocking async request handling.
        local_result = await asyncio.to_thread(_detect_intent_local_model, text)
        if local_result and (mode == "local_only" or local_result.get("confidence", 0.0) >= local_min_confidence):
            return _validate_intent_response(local_result)

    if mode == "local_only":
        raise IntentError("INTENT_DETECTOR_MODE=local_only but local model inference is unavailable")

    try:
        if not api_key:
            import sys
            sys.path.append(str(Path(__file__).parent.parent.parent))
            from backend.config import settings
            api_key = settings.OPENAI_API_KEY
        
        # Check for mock mode
        MOCK_MODE = os.getenv("MOCK_MODE", "false").lower() == "true"
        
        if MOCK_MODE:
            logger.info("Using mock mode for intent detection (no API key)")
            from backend.utils.mock_mode import get_mock_intent
            return get_mock_intent(text)
        
        client = openai.OpenAI(api_key=api_key, timeout=30.0)
        
        if user_local_time:
            time_context = f"Current user local time: {user_local_time}"
        else:
            # Pakistan-specific app: when the client doesn't send its local time,
            # resolve relative times in Pakistan Standard Time (UTC+5, no DST)
            # rather than UTC, so "at 4pm" means 4pm in Pakistan.
            _pk_now = datetime.now(timezone(timedelta(hours=5)))
            time_context = (
                f"Current user local time: {_pk_now.strftime('%Y-%m-%dT%H:%M:%S')}+05:00 "
                "(Asia/Karachi, Pakistan)"
            )

        prompt = f"""Analyze the following text and extract:
1. Intent (reminder, note, query, expense, other)
2. Scheduled time/date if mentioned — convert to UTC and include the Z suffix
3. Location if mentioned
4. Priority (low, medium, high) if mentioned
5. Any other relevant entities

{time_context}

CRITICAL TIME RULES:
- Use the user local time above as "now" to resolve all time references.
- If the user says "at 4pm" or "at 9am" with NO day mentioned, assume they mean TODAY.
  Example: user_local_time = 2026-05-24T14:00:00+05:00, "at 4pm" → 2026-05-24T16:00:00+05:00 → UTC 2026-05-24T11:00:00Z
- If the mentioned time has already passed today, assume TOMORROW.
- Always convert the final answer to UTC with Z suffix.
- "today at 4pm" means the same as "at 4pm today" — both refer to today at that hour.
- Be highly confident (≥0.85) when a clear time is stated even without an explicit day.

Text: "{text}"

Respond in JSON format:
{{
    "intent": "reminder|note|query|expense|other",
    "scheduled_time": "YYYY-MM-DDTHH:MM:SSZ or null",
    "location": "location name or null",
    "priority": "low|medium|high",
    "confidence": <0-1>,
    "title": "brief summary of the reminder",
    "entities": {{}}
}}"""

        result_text, used_model = await asyncio.to_thread(
            call_chat_with_fallback,
            client=client,
            messages=[
                {"role": "system", "content": "You are an expert at extracting intent and entities from travel-related text. Always respond with valid JSON."},
                {"role": "user", "content": prompt}
            ],
            temperature=0.2,
            response_format={"type": "json_object"},
            primary_model=model,
            label="intent_detection",
        )
        result = json.loads(result_text)

        heuristic_intent = _heuristic_intent(text)
        
        # Parse scheduled_time if present
        scheduled_time = None
        if result.get("scheduled_time"):
            try:
                scheduled_time = parse_utc_datetime(result["scheduled_time"])
            except Exception:
                scheduled_time = parse_time_from_text(text)

        confidence = _normalize_confidence(result.get("confidence", 0.0))
        intent = _resolve_intent(
            llm_intent=result.get("intent", "other"),
            heuristic_intent=heuristic_intent,
            confidence=confidence,
        )
        if intent == "other" and confidence < 0.4 and heuristic_intent != "other":
            intent = heuristic_intent

        response = {
            "intent": intent,
            "title": result.get("title"),
            "scheduled_time": scheduled_time,
            "location": result.get("location"),
            "priority": result.get("priority", "medium"),
            "confidence": confidence,
            "entities": result.get("entities", {}),
            "model_used": used_model,
        }
        return _validate_intent_response(response)
    except Exception as e:
        logger.error(f"GPT intent detection failed: {e}")
        # Fallback to spaCy
        if SPACY_AVAILABLE:
            return detect_intent_spacy(text)
        raise IntentError(f"Intent detection failed: {e}") from e


def _load_local_intent_artifacts(model_path: Path):
    global _LOCAL_INTENT_MODEL, _LOCAL_INTENT_TOKENIZER, _LOCAL_INTENT_LABEL_MAP, _LOCAL_INTENT_MODEL_PATH
    resolved_model_path = str(model_path.resolve())
    if (
        _LOCAL_INTENT_MODEL is not None
        and _LOCAL_INTENT_TOKENIZER is not None
        and _LOCAL_INTENT_LABEL_MAP is not None
        and _LOCAL_INTENT_MODEL_PATH == resolved_model_path
    ):
        return _LOCAL_INTENT_MODEL, _LOCAL_INTENT_TOKENIZER, _LOCAL_INTENT_LABEL_MAP

    import importlib
    transformers = importlib.import_module("transformers")
    AutoModelForSequenceClassification = getattr(transformers, "AutoModelForSequenceClassification")
    AutoTokenizer = getattr(transformers, "AutoTokenizer")

    label_map_path = model_path / "label_map.json"
    if not label_map_path.exists():
        raise FileNotFoundError(f"Missing label_map.json in {model_path}")

    with label_map_path.open("r", encoding="utf-8") as f:
        label_map = json.load(f)

    label_to_id = {str(k): int(v) for k, v in label_map.get("label_to_id", {}).items()}
    id_to_label = {int(k): str(v) for k, v in label_map.get("id_to_label", {}).items()}
    if not id_to_label and label_to_id:
        id_to_label = {v: k for k, v in label_to_id.items()}

    _LOCAL_INTENT_MODEL = AutoModelForSequenceClassification.from_pretrained(model_path)
    _LOCAL_INTENT_MODEL.eval()
    _LOCAL_INTENT_TOKENIZER = AutoTokenizer.from_pretrained(model_path)
    _LOCAL_INTENT_LABEL_MAP = {"label_to_id": label_to_id, "id_to_label": id_to_label}
    _LOCAL_INTENT_MODEL_PATH = resolved_model_path
    return _LOCAL_INTENT_MODEL, _LOCAL_INTENT_TOKENIZER, _LOCAL_INTENT_LABEL_MAP


def _detect_intent_local_model(text: str) -> Optional[Dict]:
    model_path = Path(os.getenv("INTENT_LOCAL_MODEL_PATH", "ai/models/intent_model"))
    if not model_path.exists():
        return None

    try:
        model, tokenizer, label_map = _load_local_intent_artifacts(model_path)
        id_to_label = label_map.get("id_to_label", {})

        inputs = tokenizer(text, return_tensors="pt", truncation=True, padding=True)
        with __import__("torch").no_grad():
            outputs = model(**inputs)
            probs = outputs.logits.softmax(dim=-1)
            pred_id = int(probs.argmax(dim=-1).item())
            confidence = float(probs[0][pred_id].item())

        local_intent = str(id_to_label.get(pred_id, "other")).lower()
        if local_intent not in {"reminder", "expense", "note", "query", "other"}:
            local_intent = "other"

        scheduled_time = parse_time_from_text(text) if local_intent == "reminder" else None
        return {
            "intent": local_intent,
            "title": text[:60],
            "scheduled_time": scheduled_time,
            "location": None,
            "priority": "medium",
            "confidence": _normalize_confidence(confidence),
            "entities": {},
            "model_used": "local_intent_model",
        }
    except Exception as e:
        logger.warning(f"Local intent model inference unavailable: {e}")
        return None


def _normalize_confidence(value) -> float:
    try:
        c = float(value)
    except Exception:
        return 0.0
    return max(0.0, min(1.0, c))


def _heuristic_intent(text: str) -> str:
    t = (text or "").lower()
    if any(k in t for k in ["spent", "expense", "paid", "cost", "bought", "buy", "usd", "$"]):
        return "expense"
    if any(k in t for k in ["remind", "reminder", "don't forget", "schedule", "tomorrow", "today", "at "]):
        return "reminder"
    if any(k in t for k in ["what", "when", "where", "how", "show", "list", "did i", "have i"]):
        return "query"
    if any(k in t for k in ["note", "write this", "save this", "record this"]):
        return "note"
    return "other"


def _resolve_intent(llm_intent: str, heuristic_intent: str, confidence: float) -> str:
    allowed = {"reminder", "expense", "note", "query", "other"}
    llm = (llm_intent or "other").lower()
    if llm not in allowed:
        llm = "other"

    c = _normalize_confidence(confidence)
    if c < 0.6 and heuristic_intent in allowed and heuristic_intent != "other":
        return heuristic_intent
    return llm


def _validate_intent_response(payload: Dict) -> Dict:
    allowed_intents = {"reminder", "expense", "note", "query", "other"}
    allowed_priorities = {"low", "medium", "high"}

    intent = (payload.get("intent") or "other").lower()
    if intent not in allowed_intents:
        intent = "other"
    payload["intent"] = intent

    priority = (payload.get("priority") or "medium").lower()
    if priority not in allowed_priorities:
        priority = "medium"
    payload["priority"] = priority

    payload["confidence"] = _normalize_confidence(payload.get("confidence", 0.0))
    if not isinstance(payload.get("entities"), dict):
        payload["entities"] = {}
    return payload


def detect_intent_spacy(text: str) -> Dict:
    """
    Fallback intent detection using spaCy.
    
    Args:
        text: Input text
        
    Returns:
        dict with intent, scheduled_time, location, entities
    """
    if not SPACY_AVAILABLE or nlp is None:
        return {
            "intent": "other",
            "scheduled_time": None,
            "location": None,
            "priority": "medium",
            "entities": {}
        }
    
    doc = nlp(text.lower())
    
    # Simple intent detection
    intent = "other"
    reminder_keywords = ["remind", "remember", "don't forget", "schedule", "at", "tomorrow", "today"]
    note_keywords = ["note", "write", "record", "save"]
    
    if any(keyword in text.lower() for keyword in reminder_keywords):
        intent = "reminder"
    elif any(keyword in text.lower() for keyword in note_keywords):
        intent = "note"
    
    # Extract location (GPE entities)
    location = None
    for ent in doc.ents:
        if ent.label_ == "GPE":  # Geopolitical entity
            location = ent.text
            break
    
    # Extract time
    scheduled_time = parse_time_from_text(text)
    
    # Extract entities
    entities = {}
    for ent in doc.ents:
        entities[ent.label_] = entities.get(ent.label_, [])
        entities[ent.label_].append(ent.text)
    
    return {
        "intent": intent,
        "title": text[:30] + "...",
        "scheduled_time": scheduled_time,
        "location": location,
        "priority": "medium",
        "confidence": 0.5,  # Lower confidence for fallback
        "entities": entities
    }


def parse_time_from_text(
    text: str, reference_dt: Optional[datetime] = None
) -> Optional[datetime]:
    """Parse time from text using regex patterns.

    reference_dt: the user's current local datetime (timezone-aware). When
    provided it is used as "now" so relative phrases resolve in the correct
    timezone. Falls back to the server clock when omitted.
    """
    from datetime import datetime, timedelta, timezone

    text_lower = text.lower()
    # Pakistan-specific default: when the caller doesn't pass the user's local
    # reference time, treat "now" as Pakistan Standard Time (UTC+5, no DST)
    # instead of the server's local clock (which is UTC in most deployments).
    now = reference_dt if reference_dt is not None else datetime.now(timezone(timedelta(hours=5)))

    def _parse_hour_minute(match: re.Match) -> tuple[int, int]:
        hour = int(match.group(1))
        minute = int(match.group(2)) if match.group(2) else 0
        meridiem = (match.group(3) or "").lower()

        # 12-hour normalization when AM/PM is present
        if meridiem == "pm" and hour < 12:
            hour += 12
        if meridiem == "am" and hour == 12:
            hour = 0

        # If no AM/PM and value is invalid for 24h, clamp out by failing later
        return hour, minute

    # tomorrow at 3 pm / today at 09:30 / next monday at 8 am
    for day_word, day_offset in (("tomorrow", 1), ("today", 0)):
        m = re.search(rf"{day_word}\s+at\s+(\d{{1,2}}):?(\d{{2}})?\s*(am|pm)?", text_lower)
        if not m:
            m = re.search(rf"at\s+(\d{{1,2}}):?(\d{{2}})?\s*(am|pm)?\s+{day_word}", text_lower)
        if m:
            try:
                hour, minute = _parse_hour_minute(m)
                if not (0 <= hour <= 23 and 0 <= minute <= 59):
                    return None
                base = now + timedelta(days=day_offset)
                return base.replace(hour=hour, minute=minute, second=0, microsecond=0, tzinfo=now.tzinfo)
            except Exception:
                return None

    weekday_map = {
        "monday": 0, "tuesday": 1, "wednesday": 2, "thursday": 3,
        "friday": 4, "saturday": 5, "sunday": 6
    }
    m = re.search(r"(next\s+)?(monday|tuesday|wednesday|thursday|friday|saturday|sunday)(?:\s+at\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)?)?", text_lower)
    if m:
        is_next = bool(m.group(1))
        weekday = weekday_map[m.group(2)]
        hour = int(m.group(3)) if m.group(3) else 9
        minute = int(m.group(4)) if m.group(4) else 0
        mer = (m.group(5) or "").lower()
        if mer == "pm" and hour < 12:
            hour += 12
        if mer == "am" and hour == 12:
            hour = 0
        days_ahead = (weekday - now.weekday()) % 7
        if days_ahead == 0 or is_next:
            days_ahead = max(days_ahead, 7)
        dt = now + timedelta(days=days_ahead)
        return dt.replace(hour=hour, minute=minute, second=0, microsecond=0, tzinfo=now.tzinfo)

    # in 2 hours / in 45 minutes
    m = re.search(r"in\s+(\d+)\s+(hours?|minutes?)", text_lower)
    if m:
        try:
            value = int(m.group(1))
            unit = m.group(2)
            if "hour" in unit:
                return now + timedelta(hours=value)
            return now + timedelta(minutes=value)
        except Exception:
            return None

    # ── "at 4pm" / "at 4:00 am" / "at 16:30" — no day word ─────────────────
    # When no day is mentioned, use today; if the time already passed, use tomorrow.
    m = re.search(r"\bat\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\b", text_lower)
    if m:
        try:
            hour, minute = _parse_hour_minute(m)
            if not (0 <= hour <= 23 and 0 <= minute <= 59):
                return None
            # Build candidate for today
            candidate = now.replace(hour=hour, minute=minute, second=0, microsecond=0)
            # Push to tomorrow if that moment has already passed
            if candidate <= now:
                candidate = candidate + timedelta(days=1)
            return candidate
        except Exception:
            return None

    # ── Bare "4pm" / "4:30am" / "4 pm" — absolute last resort ───────────────
    # Requires an explicit am/pm marker to avoid matching bare numbers.
    m = re.search(r"\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b", text_lower)
    if m:
        try:
            hour, minute = _parse_hour_minute(m)
            if not (0 <= hour <= 23 and 0 <= minute <= 59):
                return None
            candidate = now.replace(hour=hour, minute=minute, second=0, microsecond=0)
            if candidate <= now:
                candidate = candidate + timedelta(days=1)
            return candidate
        except Exception:
            return None

    return None
