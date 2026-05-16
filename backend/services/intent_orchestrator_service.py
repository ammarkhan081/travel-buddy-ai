"""Unified speech command orchestration: STT -> Intent -> Branch -> Store."""

import logging
import json
from datetime import datetime, timezone
from typing import Dict
from sqlalchemy.orm import Session

from ai.inference.stt_pipeline.transcriber import transcribe_audio
from ai.inference.nlp_pipeline.intent_detector import detect_intent_gpt, parse_time_from_text
from ai.inference.expense_parser.expense_extractor import extract_expense_gpt
from backend.utils.time_utils import now_utc_iso, parse_utc_datetime
from backend.utils.transcript_utils import extract_keywords
try:
    from ..models.decision_review import DecisionReview
    from ..models.reminder import Reminder
    from ..models.expense import Expense
    from ..models.voice_note import VoiceNote
    from ..utils.time_utils import now_utc_iso, parse_utc_datetime
except ImportError:
    from models.decision_review import DecisionReview
    from models.reminder import Reminder
    from models.expense import Expense
    from models.voice_note import VoiceNote
    from backend.utils.time_utils import now_utc_iso, parse_utc_datetime


logger = logging.getLogger(__name__)


def _heuristic_intent(text: str) -> str:
    t = (text or "").lower()
    if any(k in t for k in ["spent", "expense", "paid", "cost", "bought", "$", "pkr", "usd", "eur"]):
        return "expense"
    if any(k in t for k in ["remind", "reminder", "don't forget", "schedule", "tomorrow", "today", "at "]):
        return "reminder"
    if any(k in t for k in ["what", "when", "where", "how", "show", "list", "did i", "have i"]):
        return "query"
    if any(k in t for k in ["note", "save this", "record this", "write this"]):
        return "note"
    return "other"


def _create_decision_review(
    db: Session,
    *,
    user_id: str,
    transcript: str,
    intent: str,
    source_action: str,
    suggested_payload: Dict,
) -> int | None:
    """Persist a pending decision record for auditable accept/reject/edit flow."""
    try:
        record = DecisionReview(
            user_id=user_id,
            transcript=transcript,
            intent=intent,
            source_action=source_action,
            suggested_payload=json.dumps(suggested_payload or {}, ensure_ascii=False),
            status="pending",
            resolution_payload=None,
            created_at=now_utc_iso(),
            resolved_at=None,
        )
        db.add(record)
        db.commit()
        db.refresh(record)
        rid = getattr(record, "id", None)
        return rid if isinstance(rid, int) else None
    except Exception as e:
        logger.warning("decision_review_persist_failed", extra={"error": str(e)})
        try:
            db.rollback()
        except Exception:
            pass
        return None


async def process_voice_command(
    db: Session,
    audio_file,
    user_id: str = "default",
    persist: bool = True,
) -> Dict:
    """
    Unified pipeline:
    1) Speech-to-text
    2) Intent detection
    3) Branch to reminder/expense/knowledge storage
    """
    stt_result = await transcribe_audio(audio_file, use_fallback=True)
    transcript = (stt_result.get("transcript") or "").strip()
    normalized_for_nlp = (stt_result.get("normalized_for_nlp") or transcript).strip()
    if not transcript:
        return {
            "transcript": "",
            "intent": "other",
            "action": "none",
            "record_id": None,
            "requires_review": True,
            "details": {"error": "empty_transcript"},
        }

    intent_fallback_reason = None
    try:
        intent_data = await detect_intent_gpt(normalized_for_nlp)
    except Exception as e:
        logger.warning("intent_detection_unavailable", extra={"error": str(e)})
        intent_data = {
            "intent": _heuristic_intent(normalized_for_nlp),
            "confidence": 0.0,
            "title": transcript[:80],
            "scheduled_time": None,
            "location": None,
            "priority": "medium",
        }
        intent_fallback_reason = "intent_detection_unavailable"
    intent = (intent_data.get("intent") or "other").lower()
    now_iso = now_utc_iso()

    # Branch: Reminder
    if intent == "reminder":
        scheduled = parse_utc_datetime(intent_data.get("scheduled_time"))
        # Fallback: if model omits scheduled_time but transcript contains time words,
        # parse directly from transcript to preserve direct Accept flow in UI.
        if scheduled is None:
            fallback_dt = parse_time_from_text(transcript)
            scheduled = parse_utc_datetime(fallback_dt) if fallback_dt is not None else None
        confidence = float(intent_data.get("confidence", 0.0))
        title = intent_data.get("title") or transcript[:80]
        if confidence < 0.55:
            detected_dt = scheduled.isoformat() if isinstance(scheduled, datetime) else None
            details = {
                "title": title,
                "datetime": detected_dt,
                "confidence": confidence,
                "reason": "low_intent_confidence",
            }
            review_id = _create_decision_review(
                db,
                user_id=user_id,
                transcript=transcript,
                intent="reminder",
                source_action="reminder_needs_review",
                suggested_payload=details,
            )
            return {
                "transcript": transcript,
                "intent": "reminder",
                "action": "reminder_needs_review",
                "record_id": None,
                "review_id": review_id,
                "requires_review": True,
                "details": details,
            }

        if not (isinstance(scheduled, datetime) and scheduled > datetime.now(timezone.utc)):
            details = {
                "title": title,
                "datetime": None,
                "confidence": confidence,
                "reason": "missing_invalid_or_past_time",
            }
            review_id = _create_decision_review(
                db,
                user_id=user_id,
                transcript=transcript,
                intent="reminder",
                source_action="reminder_needs_review",
                suggested_payload=details,
            )
            return {
                "transcript": transcript,
                "intent": "reminder",
                "action": "reminder_needs_review",
                "record_id": None,
                "review_id": review_id,
                "requires_review": True,
                "details": details,
            }

        scheduled_iso = scheduled.isoformat()
        if not persist:
            details = {
                "title": title,
                "datetime": scheduled_iso,
                "confidence": confidence,
            }
            review_id = _create_decision_review(
                db,
                user_id=user_id,
                transcript=transcript,
                intent="reminder",
                source_action="reminder_detected",
                suggested_payload=details,
            )
            return {
                "transcript": transcript,
                "intent": "reminder",
                "action": "reminder_detected",
                "record_id": None,
                "review_id": review_id,
                "requires_review": False,
                "details": details,
            }

        db_item = Reminder(
            title=title,
            text=title,
            datetime=scheduled_iso,
            transcript=transcript,
            intent="reminder",
            user_id=user_id,
            location=intent_data.get("location"),
            priority=intent_data.get("priority") or "medium",
            status="pending",
            created_at=now_iso,
        )
        db.add(db_item)
        db.commit()
        db.refresh(db_item)
        return {
            "transcript": transcript,
            "intent": "reminder",
            "action": "reminder_created",
            "record_id": db_item.id,
            "requires_review": False,
            "details": {
                "title": db_item.title,
                "datetime": db_item.datetime,
                "confidence": confidence,
            },
        }

    # Branch: Expense
    if intent == "expense":
        try:
            expense = await extract_expense_gpt(transcript)
        except Exception as e:
            logger.warning("expense_extraction_unavailable", extra={"error": str(e)})
            details = {
                "amount": 0.0,
                "category": "other",
                "confidence": float(intent_data.get("confidence", 0.0)),
                "reason": "expense_extraction_unavailable",
            }
            review_id = _create_decision_review(
                db,
                user_id=user_id,
                transcript=transcript,
                intent="expense",
                source_action="expense_needs_review",
                suggested_payload=details,
            )
            return {
                "transcript": transcript,
                "intent": "expense",
                "action": "expense_needs_review",
                "record_id": None,
                "review_id": review_id,
                "requires_review": True,
                "details": details,
            }
        amount = float(expense.get("amount") or 0.0)
        intent_confidence = float(intent_data.get("confidence", 0.0))
        extract_confidence = float(expense.get("confidence", 0.0))
        effective_confidence = min(intent_confidence, extract_confidence)

        if intent_confidence < 0.55:
            details = {
                "amount": amount,
                "category": expense.get("category") or "other",
                "confidence": effective_confidence,
                "intent_confidence": intent_confidence,
                "extract_confidence": extract_confidence,
                "reason": "low_intent_confidence",
            }
            review_id = _create_decision_review(
                db,
                user_id=user_id,
                transcript=transcript,
                intent="expense",
                source_action="expense_needs_review",
                suggested_payload=details,
            )
            return {
                "transcript": transcript,
                "intent": "expense",
                "action": "expense_needs_review",
                "record_id": None,
                "review_id": review_id,
                "requires_review": True,
                "details": details,
            }

        if amount <= 0:
            details = {
                "amount": amount,
                "category": expense.get("category") or "other",
                "confidence": effective_confidence,
                "intent_confidence": intent_confidence,
                "extract_confidence": extract_confidence,
                "reason": "missing_or_invalid_amount",
            }
            review_id = _create_decision_review(
                db,
                user_id=user_id,
                transcript=transcript,
                intent="expense",
                source_action="expense_needs_review",
                suggested_payload=details,
            )
            return {
                "transcript": transcript,
                "intent": "expense",
                "action": "expense_needs_review",
                "record_id": None,
                "review_id": review_id,
                "requires_review": True,
                "details": details,
            }

        if not persist:
            details = {
                "amount": amount,
                "category": (expense.get("category") or "other"),
                "confidence": effective_confidence,
                "intent_confidence": intent_confidence,
                "extract_confidence": extract_confidence,
            }
            review_id = _create_decision_review(
                db,
                user_id=user_id,
                transcript=transcript,
                intent="expense",
                source_action="expense_detected",
                suggested_payload=details,
            )
            return {
                "transcript": transcript,
                "intent": "expense",
                "action": "expense_detected",
                "record_id": None,
                "review_id": review_id,
                "requires_review": False,
                "details": details,
            }

        db_item = Expense(
            amount=amount,
            category=(expense.get("category") or "other"),
            description=expense.get("description") or transcript,
            date=now_iso,
            intent="expense",
            user_id=user_id,
            created_at=now_iso,
        )
        db.add(db_item)
        db.commit()
        db.refresh(db_item)
        return {
            "transcript": transcript,
            "intent": "expense",
            "action": "expense_created",
            "record_id": db_item.id,
            "requires_review": False,
            "details": {
                "amount": db_item.amount,
                "category": db_item.category,
                "confidence": effective_confidence,
                "intent_confidence": intent_confidence,
                "extract_confidence": extract_confidence,
            },
        }

    # Branch: Note / Query / Other -> knowledge storage
    keywords = extract_keywords(transcript)
    note_id = None
    if persist:
        note = VoiceNote(
            user_id=user_id,
            transcript=transcript,
            keywords=keywords,
            timestamp=now_iso,
            created_at=now_iso,
        )
        db.add(note)
        db.commit()
        db.refresh(note)
        note_id = note.id
    return {
        "transcript": transcript,
        "intent": intent if intent in {"note", "query", "other"} else "other",
        "action": "stored_as_knowledge" if persist else "knowledge_detected",
        "record_id": note_id,
        "requires_review": False,
        "details": {
            "confidence": intent_data.get("confidence", 0.0),
            **({"fallback_reason": intent_fallback_reason} if intent_fallback_reason else {}),
        },
    }
