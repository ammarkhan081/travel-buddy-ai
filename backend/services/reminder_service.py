"""Service for reminder management using SQLAlchemy."""

import logging
import tempfile
from datetime import datetime
from typing import Optional, List, Dict
from sqlalchemy.orm import Session
try:
    from ..models.reminder import Reminder
    from ..schemas.reminders import ReminderCreate, ReminderResponse, ReminderIntent, ReminderUpdate
    from ..config import settings
except ImportError:
    from models.reminder import Reminder
    from schemas.reminders import ReminderCreate, ReminderResponse, ReminderIntent, ReminderUpdate
    from config import settings
from ai.inference.nlp_pipeline.intent_detector import detect_intent_gpt
from ai.inference.stt_pipeline.transcriber import normalize_transcript
from backend.utils.transcript_utils import normalize_for_nlp
from openai import OpenAI
from backend.utils.error_policy import ExtractionError
from backend.utils.time_utils import parse_utc_datetime, now_utc_iso, to_utc_iso
from backend.utils.ai_runtime import call_with_retries

logger = logging.getLogger(__name__)

async def create_reminder(db: Session, reminder_data: ReminderCreate) -> Reminder:
    """Create a new manual reminder with optional intent detection."""
    try:
        # Detect intent if title looks like a sentence. This is a best-effort
        # enhancement only — a manual reminder MUST still save even if the AI
        # call fails (no key, rate limit, network), so failures are swallowed.
        intent = "manual"
        if len(reminder_data.title.split()) > 2:
            try:
                intent_dict = await detect_intent_gpt(reminder_data.title)
                intent = intent_dict.get("intent", "manual")
            except Exception as intent_err:
                logger.warning(f"Manual reminder intent detection skipped: {intent_err}")
                intent = "manual"
            
        dt_utc = to_utc_iso(reminder_data.datetime)
        user_id = getattr(reminder_data, 'user_id', 'default')
        created_iso = now_utc_iso()

        # Resolve trip (explicit > active trip at creation time).
        trip_id = getattr(reminder_data, "trip_id", None)
        if trip_id is None:
            try:
                from .trip_service import resolve_trip_id_for_new_record
            except ImportError:
                from services.trip_service import resolve_trip_id_for_new_record
            trip_id = resolve_trip_id_for_new_record(db, user_id, created_iso)

        db_reminder = Reminder(
            title=reminder_data.title,
            text=reminder_data.title, # Using title as text fallback
            datetime=dt_utc,
            user_id=user_id,
            intent=intent,
            transcript=None,
            location=getattr(reminder_data, 'location', None),
            priority=getattr(reminder_data, 'priority', 'medium'),
            status="pending",
            created_at=created_iso,
            trip_id=trip_id,
        )
        db.add(db_reminder)
        db.commit()
        db.refresh(db_reminder)
        return db_reminder
    except Exception as e:
        logger.error(f"Error creating reminder: {e}")
        db.rollback()
        raise

async def extract_reminder_from_voice(audio_file) -> Dict:
    """Extract reminder from voice. Does NOT save to DB."""
    try:
        # Use an auto-cleaned temp handle and call Whisper before the handle closes.
        with tempfile.NamedTemporaryFile(suffix=".wav") as tmp:
            tmp.write(audio_file.read())
            tmp.seek(0)

            # Call Whisper
            client = OpenAI(api_key=settings.OPENAI_API_KEY, timeout=30.0)
            transcript_obj = call_with_retries(
                "reminder_voice_whisper",
                lambda: client.audio.transcriptions.create(
                    model=settings.WHISPER_MODEL,
                    file=tmp
                ),
            )
        transcript = normalize_transcript(transcript_obj.text)
        
        # Pass transcript to intent detection (returns dict with confidence, title, etc)
        intent_dict = await detect_intent_gpt(normalize_for_nlp(transcript))
        scheduled_time = parse_utc_datetime(intent_dict.get("scheduled_time"))
        now = datetime.now().astimezone()

        # Ambiguous/invalid time handling for reminder voice extraction.
        if intent_dict.get("intent") == "reminder":
            if not isinstance(scheduled_time, datetime):
                intent_dict["scheduled_time"] = None
                intent_dict["needs_clarification"] = True
                intent_dict["clarification_reason"] = "missing_or_ambiguous_time"
            elif isinstance(scheduled_time, datetime) and scheduled_time <= now:
                intent_dict["scheduled_time"] = None
                intent_dict["needs_clarification"] = True
                intent_dict["clarification_reason"] = "past_time_detected"
            else:
                intent_dict["scheduled_time"] = scheduled_time
                intent_dict["needs_clarification"] = False
                intent_dict["clarification_reason"] = None

        intent_dict["transcript"] = transcript
        
        return intent_dict
        
    except Exception as e:
        logger.error(f"Error in voice reminder extraction: {e}")
        raise ExtractionError(f"Voice reminder extraction failed: {e}") from e


def get_reminders(db: Session, user_id: str) -> List[Reminder]:
    return db.query(Reminder).filter(Reminder.user_id == user_id).all()

def delete_reminder(db: Session, reminder_id: int, user_id: str) -> bool:
    """Delete a reminder only if it belongs to user_id."""
    reminder = (
        db.query(Reminder)
        .filter(Reminder.id == reminder_id, Reminder.user_id == user_id)
        .first()
    )
    if reminder:
        db.delete(reminder)
        db.commit()
        return True
    return False


def update_reminder(db: Session, reminder_id: int, update: ReminderUpdate, user_id: str) -> Optional[Reminder]:
    """Update reminder status only if the record belongs to user_id."""
    reminder = (
        db.query(Reminder)
        .filter(Reminder.id == reminder_id, Reminder.user_id == user_id)
        .first()
    )
    if not reminder:
        return None

    setattr(reminder, "status", update.status)
    db.commit()
    db.refresh(reminder)
    return reminder
