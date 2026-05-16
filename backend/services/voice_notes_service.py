"""Service for voice note management using SQLAlchemy."""

import logging
import tempfile
from datetime import datetime
from typing import List, Optional, BinaryIO, cast
from sqlalchemy.orm import Session
try:
    from ..models.voice_note import VoiceNote
    from ..schemas.stt import TranscriptionResponse, VoiceNoteResponse
    from ..config import settings
except ImportError:
    from models.voice_note import VoiceNote
    from schemas.stt import TranscriptionResponse, VoiceNoteResponse
    from config import settings
from ai.inference.stt_pipeline.transcriber import transcribe_audio
from openai import OpenAI
from backend.utils.time_utils import now_utc_iso
from backend.utils.transcript_utils import extract_keywords

logger = logging.getLogger(__name__)


def create_note_from_text(db: Session, transcript: str, user_id: str, keywords: Optional[str] = None) -> VoiceNote:
    """Persist a voice note from an existing transcript (no STT pass)."""
    text = (transcript or "").strip()
    if not text:
        raise ValueError("Transcript cannot be empty")

    computed_keywords = keywords or extract_keywords(text)
    now_iso = now_utc_iso()
    db_note = VoiceNote(
        user_id=user_id,
        transcript=text,
        keywords=computed_keywords,
        timestamp=now_iso,
        created_at=now_iso,
    )
    db.add(db_note)
    db.commit()
    db.refresh(db_note)
    return db_note

async def transcribe_and_save(db: Session, audio_file, user_id: str) -> VoiceNote:
    """Audit Step 7: Transcribe audio and save to VoiceNote model."""
    try:
        # Use an auto-cleaned temp handle and transcribe before it closes.
        with tempfile.NamedTemporaryFile(suffix=".wav") as tmp:
            tmp.write(audio_file.read())
            tmp.seek(0)

            # Transcribe
            result = await transcribe_audio(cast(BinaryIO, tmp.file))
        
        transcript = result.get("transcript", "")
        
        # Deterministic keyword extraction for better retrieval quality.
        keywords = extract_keywords(transcript)
        
        now_iso = now_utc_iso()
        db_note = VoiceNote(
            user_id=user_id,
            transcript=transcript,
            keywords=keywords,
            timestamp=now_iso,
            created_at=now_iso
        )
        db.add(db_note)
        db.commit()
        db.refresh(db_note)
        return db_note
        
    except Exception as e:
        logger.error(f"Error transcribing voice note: {e}")
        db.rollback()
        raise

def get_voice_notes(db: Session, user_id: str, q: Optional[str] = None) -> List[VoiceNote]:
    query = db.query(VoiceNote).filter(VoiceNote.user_id == user_id)
    if q:
        query = query.filter(VoiceNote.transcript.contains(q))
    return query.order_by(VoiceNote.timestamp.desc()).all()


def delete_voice_note(db: Session, note_id: int, user_id: str) -> bool:
    """Delete a voice note only if it belongs to user_id."""
    note = (
        db.query(VoiceNote)
        .filter(VoiceNote.id == note_id, VoiceNote.user_id == user_id)
        .first()
    )
    if note:
        db.delete(note)
        db.commit()
        return True
    return False

