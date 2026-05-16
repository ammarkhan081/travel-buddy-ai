"""Routes for voice notes management."""

import logging
from fastapi import APIRouter, HTTPException, UploadFile, File, Depends, Query
from typing import List, Optional
from sqlalchemy.orm import Session
try:
    from ..auth import AuthenticatedUser, get_current_user
    from ..database import get_db
    from ..schemas.stt import VoiceNoteResponse, VoiceNoteCreateFromTextRequest
    from ..services import voice_notes_service
except ImportError:
    from auth import AuthenticatedUser, get_current_user
    from database import get_db
    from schemas.stt import VoiceNoteResponse, VoiceNoteCreateFromTextRequest
    from services import voice_notes_service

router = APIRouter()
logger = logging.getLogger(__name__)


@router.post("/transcribe", response_model=VoiceNoteResponse)
async def transcribe_audio(
    file: UploadFile = File(...),
    user_id: Optional[str] = Query(default="default"),
    db: Session = Depends(get_db),
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    """POST /api/voice-notes/transcribe: Transcribes audio and saves to SQLite."""
    try:
        return await voice_notes_service.transcribe_and_save(db, file.file, current_user.uid)
    except Exception as e:
        logger.exception("voice_note_transcribe_failed", exc_info=e)
        raise HTTPException(status_code=500, detail="Failed to transcribe and save voice note.")


@router.post("/from-text", response_model=VoiceNoteResponse)
async def create_from_text(
    payload: VoiceNoteCreateFromTextRequest,
    db: Session = Depends(get_db),
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    """POST /api/voice-notes/from-text: Save provided transcript as a voice note."""
    try:
        return voice_notes_service.create_note_from_text(
            db,
            transcript=payload.transcript,
            user_id=current_user.uid,
            keywords=payload.keywords,
        )
    except ValueError as e:
        raise HTTPException(status_code=422, detail=str(e))
    except Exception as e:
        logger.exception("voice_note_from_text_failed", exc_info=e)
        raise HTTPException(status_code=500, detail="Failed to save voice note from text.")


@router.get("/", response_model=List[VoiceNoteResponse])
async def list_voice_notes(
    q: Optional[str] = Query(None),
    db: Session = Depends(get_db),
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    """GET /api/voice-notes/: Returns all transcribed notes. Supports ?q= search."""
    return voice_notes_service.get_voice_notes(db, current_user.uid, q)


# Keep /notes as an alias so existing Flutter calls to that path still work
@router.get("/notes", response_model=List[VoiceNoteResponse])
async def list_voice_notes_alias(
    q: Optional[str] = Query(None),
    db: Session = Depends(get_db),
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    """GET /api/voice-notes/notes: Alias for / — kept for backward compatibility."""
    return voice_notes_service.get_voice_notes(db, current_user.uid, q)


@router.get("/search", response_model=List[VoiceNoteResponse])
async def search_voice_notes(
    q: str = Query(..., description="Search query"),
    db: Session = Depends(get_db),
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    """GET /api/voice-notes/search?q=: Search notes by transcript content."""
    return voice_notes_service.get_voice_notes(db, current_user.uid, q)


@router.delete("/{note_id}")
async def delete_voice_note(
    note_id: int,
    db: Session = Depends(get_db),
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    """DELETE /api/voice-notes/{id}: Deletes note — only if it belongs to the caller."""
    if voice_notes_service.delete_voice_note(db, note_id, current_user.uid):
        return {"message": "Voice note deleted successfully"}
    raise HTTPException(status_code=404, detail="Voice note not found")
