"""Routes for reminders API."""

import logging
from fastapi import APIRouter, HTTPException, UploadFile, File, Depends, Query
from typing import List, Optional
from sqlalchemy.orm import Session
try:
    from ..auth import AuthenticatedUser, get_current_user
    from ..database import get_db
    from ..schemas.reminders import ReminderCreate, ReminderResponse, ReminderIntent, ReminderUpdate
    from ..services import reminder_service, intent_orchestrator_service
except ImportError:
    from auth import AuthenticatedUser, get_current_user
    from database import get_db
    from schemas.reminders import ReminderCreate, ReminderResponse, ReminderIntent, ReminderUpdate
    from services import reminder_service, intent_orchestrator_service

router = APIRouter()
logger = logging.getLogger(__name__)


@router.get("/", response_model=List[ReminderResponse])
async def get_reminders(
    db: Session = Depends(get_db),
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    """GET /api/reminders: Returns all reminders from SQLite."""
    return reminder_service.get_reminders(db, current_user.uid)


@router.post("/", response_model=ReminderResponse)
async def create_reminder(
    reminder: ReminderCreate,
    db: Session = Depends(get_db),
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    """POST /api/reminders: Creates a new reminder and saves to SQLite."""
    try:
        reminder.user_id = current_user.uid
        return await reminder_service.create_reminder(db, reminder)
    except Exception as e:
        logger.exception("create_reminder_failed", exc_info=e)
        raise HTTPException(status_code=500, detail="Failed to create reminder.")


@router.delete("/{reminder_id}")
async def delete_reminder(
    reminder_id: int,
    db: Session = Depends(get_db),
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    """DELETE /api/reminders/{id}: Deletes reminder — only if it belongs to the caller."""
    if reminder_service.delete_reminder(db, reminder_id, current_user.uid):
        return {"message": "Reminder deleted successfully"}
    raise HTTPException(status_code=404, detail="Reminder not found")


@router.put("/{reminder_id}", response_model=ReminderResponse)
async def update_reminder(
    reminder_id: int,
    update: ReminderUpdate,
    db: Session = Depends(get_db),
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    """PUT /api/reminders/{id}: Update reminder status — only if it belongs to the caller."""
    reminder = reminder_service.update_reminder(db, reminder_id, update, current_user.uid)
    if not reminder:
        raise HTTPException(status_code=404, detail="Reminder not found")
    return reminder


@router.post("/voice", response_model=ReminderIntent)
async def create_reminder_voice(
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    """
    POST /api/reminders/voice:
    Accepts multipart audio, runs Whisper STT + extraction (Review-first).
    """
    try:
        result = await intent_orchestrator_service.process_voice_command(
            db,
            file.file,
            current_user.uid,
            persist=False,
        )
        if result.get("intent") != "reminder":
            return ReminderIntent(
                intent=result.get("intent", "other"),
                scheduled_time=None,
                location=None,
                priority="medium",
                entities={},
                confidence=float(result.get("details", {}).get("confidence", 0.0)),
                title=result.get("details", {}).get("title"),
            )

        scheduled_time = None
        if result.get("details", {}).get("datetime"):
            from datetime import datetime
            scheduled_time = datetime.fromisoformat(result["details"]["datetime"].replace("Z", "+00:00"))
        return ReminderIntent(
            intent="reminder",
            scheduled_time=scheduled_time,
            location=None,
            priority="medium",
            entities={},
            confidence=float(result.get("details", {}).get("confidence", 0.0)),
            title=result.get("details", {}).get("title"),
        )
    except Exception as e:
        logger.exception("create_reminder_voice_failed", exc_info=e)
        raise HTTPException(status_code=422, detail="Failed to process voice reminder.")
