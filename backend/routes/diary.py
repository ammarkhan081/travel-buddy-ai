"""Routes for travel diary API."""

import os
import logging
from fastapi import APIRouter, HTTPException, Depends, Query, UploadFile, File
from fastapi.responses import FileResponse
from typing import List, Optional
from sqlalchemy.orm import Session
try:
    from ..auth import AuthenticatedUser, get_current_user
    from ..database import get_db
    from ..schemas.diary import (
        DiaryCreateManual, DiaryEntryResponse, DiaryGenerateRequest,
        DiaryUpdateRequest, TripDiaryGenerateRequest,
    )
    from ..services import diary_service
except ImportError:
    from auth import AuthenticatedUser, get_current_user
    from database import get_db
    from schemas.diary import (
        DiaryCreateManual, DiaryEntryResponse, DiaryGenerateRequest,
        DiaryUpdateRequest, TripDiaryGenerateRequest,
    )
    from services import diary_service

router = APIRouter()
logger = logging.getLogger(__name__)


@router.get("/", response_model=List[DiaryEntryResponse])
async def get_diary_entries(
    user_id: str = Query("default", description="User ID"),
    db: Session = Depends(get_db),
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    """GET /api/diary: Returns all entries from SQLite."""
    return diary_service.get_diary_entries(db, current_user.uid)


@router.post("/voice", response_model=DiaryEntryResponse)
async def create_voice_diary(
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    """POST /api/diary/voice: Record a voice note → AI writes an English diary entry.

    Analyses the transcript together with recent tour reminders, voice notes,
    weather cues and alerts to produce a rich narrative entry in English.
    """
    try:
        return await diary_service.generate_voice_diary(
            db=db,
            user_id=current_user.uid,
            audio_file=file.file,
        )
    except Exception as e:
        logger.exception("diary_voice_create_failed", exc_info=e)
        raise HTTPException(status_code=500, detail="Failed to create voice diary entry.")


@router.post("/manual", response_model=DiaryEntryResponse)
async def create_manual_entry(
    entry: DiaryCreateManual,
    user_id: str = Query("default", description="User ID"),
    db: Session = Depends(get_db),
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    """POST /api/diary/manual: Accepts {title, content, location} and saves to SQLite."""
    try:
        return await diary_service.create_manual_entry(db, entry, current_user.uid)
    except Exception as e:
        logger.exception("diary_create_manual_failed", exc_info=e)
        raise HTTPException(status_code=500, detail="Failed to create diary entry.")


@router.post("/auto-generate", response_model=DiaryEntryResponse)
async def auto_generate_diary(
    request: DiaryGenerateRequest,
    db: Session = Depends(get_db),
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    """POST /api/diary/auto-generate: Triggers AI summarization with GPS tagging."""
    try:
        request.user_id = current_user.uid
        return await diary_service.generate_diary_ai(db, request)
    except Exception as e:
        logger.exception("diary_auto_generate_failed", exc_info=e)
        raise HTTPException(status_code=500, detail="Failed to auto-generate diary entry.")


@router.post("/trip-diary", response_model=DiaryEntryResponse)
async def generate_trip_diary(
    request: TripDiaryGenerateRequest,
    db: Session = Depends(get_db),
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    """POST /api/diary/trip-diary: Generate a destination-specific trip diary.

    Works for both booked trips (pass booking_id) and unplanned friend trips
    (just provide destination_name, from_date, optional return_date and notes).
    """
    try:
        return await diary_service.generate_trip_diary(
            db=db,
            user_id=current_user.uid,
            destination_name=request.destination_name,
            from_date=request.from_date,
            return_date=request.return_date,
            notes=request.notes,
            booking_id=request.booking_id,
        )
    except Exception as e:
        logger.exception("diary_trip_generate_failed", exc_info=e)
        raise HTTPException(status_code=500, detail="Failed to generate trip diary.")


# Keep /generate as alias for backward compatibility
@router.post("/generate", response_model=DiaryEntryResponse)
async def generate_diary_alias(
    request: DiaryGenerateRequest,
    db: Session = Depends(get_db),
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    """POST /api/diary/generate: Alias for /auto-generate."""
    try:
        request.user_id = current_user.uid
        return await diary_service.generate_diary_ai(db, request)
    except Exception as e:
        logger.exception("diary_generate_alias_failed", exc_info=e)
        raise HTTPException(status_code=500, detail="Failed to auto-generate diary entry.")



@router.put("/{entry_id}", response_model=DiaryEntryResponse)
async def update_diary_entry(
    entry_id: int,
    update: DiaryUpdateRequest,
    db: Session = Depends(get_db),
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    """PUT /api/diary/{id}: Update diary entry content — only if it belongs to the caller."""
    entry = diary_service.update_entry(db, entry_id, update, current_user.uid)
    if not entry:
        raise HTTPException(status_code=404, detail="Diary entry not found")
    return entry


@router.delete("/{entry_id}")
async def delete_diary_entry(
    entry_id: int,
    db: Session = Depends(get_db),
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    """DELETE /api/diary/{id}: Delete diary entry — only if it belongs to the caller."""
    if diary_service.delete_entry(db, entry_id, current_user.uid):
        return {"message": "Diary entry deleted successfully"}
    raise HTTPException(status_code=404, detail="Diary entry not found")


@router.get("/export")
async def export_diary(
    fmt: str = Query("pdf", alias="format", description="Export format: pdf or docx"),
    db: Session = Depends(get_db),
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    """GET /api/diary/export?format=pdf|docx: Export current user's diary entries."""
    try:
        file_path = diary_service.export_diary(db, fmt, user_id=current_user.uid)
        if not file_path or not os.path.exists(file_path):
            raise HTTPException(status_code=500, detail="Export failed")
        if fmt.lower() == "docx":
            media_type = "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
            filename = "travel_diary.docx"
        else:
            media_type = "application/pdf"
            filename = "travel_diary.pdf"
        return FileResponse(file_path, media_type=media_type, filename=filename)
    except HTTPException:
        raise
    except Exception as e:
        logger.exception("diary_export_failed", exc_info=e)
        raise HTTPException(status_code=500, detail="Failed to export diary.")


@router.get("/summary")
async def get_diary_summary(
    user_id: str = Query("default", description="User ID"),
    db: Session = Depends(get_db),
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    """GET /api/diary/summary: Returns aggregated stats."""
    return diary_service.get_diary_summary(db, current_user.uid)
