"""Service for diary management using SQLAlchemy."""

import asyncio
import logging
import os
from datetime import datetime, timedelta
from pathlib import Path
from typing import List, Optional, Dict
from sqlalchemy.orm import Session
try:
    from ..models.diary_entry import DiaryEntry
    from ..models.reminder import Reminder
    from ..models.expense import Expense
    from ..models.voice_note import VoiceNote
    from ..schemas.diary import DiaryCreateManual, DiaryGenerateRequest, DiaryUpdateRequest
except ImportError:
    from models.diary_entry import DiaryEntry
    from models.reminder import Reminder
    from models.expense import Expense
    from models.voice_note import VoiceNote
    from schemas.diary import DiaryCreateManual, DiaryGenerateRequest, DiaryUpdateRequest
from ai.inference.summarizer.diary_summarizer import summarize_diary
from backend.utils.time_utils import now_utc_iso

logger = logging.getLogger(__name__)

# Directory where exported files are saved
EXPORT_DIR = os.getenv("DIARY_FILES_DIR", "diary_files")


async def create_manual_entry(db: Session, entry_data: DiaryCreateManual, user_id: str) -> DiaryEntry:
    """POST /api/diary/manual."""
    try:
        db_entry = DiaryEntry(
            user_id=user_id,
            title=entry_data.title,
            content=entry_data.content,
            location=entry_data.location,
            imageUrl=entry_data.imageUrl,
            timestamp=now_utc_iso(),
            is_auto_generated=False
        )
        db.add(db_entry)
        db.commit()
        db.refresh(db_entry)
        return db_entry
    except Exception as e:
        logger.error(f"Error creating manual diary entry: {e}")
        db.rollback()
        raise


async def generate_diary_ai(db: Session, request: DiaryGenerateRequest) -> DiaryEntry:
    """POST /api/diary/auto-generate: AI summarization with optional GPS tagging."""
    user_id = request.user_id or "default"
    now_dt = datetime.now()
    date_str = now_dt.strftime("%B %d, %Y")
    now_iso = now_utc_iso()
    days = max(1, int(request.days or 7))
    window_start = now_dt - timedelta(days=days)

    def _in_window(dt_str: Optional[str]) -> bool:
        if not dt_str:
            return False
        try:
            dt = datetime.fromisoformat(dt_str.replace("Z", "+00:00"))
            if dt.tzinfo is not None:
                dt = dt.astimezone().replace(tzinfo=None)
            return dt >= window_start
        except Exception:
            return False

    try:
        # M-2: Push date-window filter to SQL to avoid full-table hydration
        window_start_iso = window_start.isoformat()
        reminders = (
            db.query(Reminder)
            .filter(Reminder.user_id == user_id, Reminder.datetime >= window_start_iso)
            .order_by(Reminder.datetime.asc())
            .all()
        )
        expenses = (
            db.query(Expense)
            .filter(Expense.user_id == user_id, Expense.date >= window_start_iso)
            .order_by(Expense.date.asc())
            .all()
        )
        # Voice notes use created_at; limit kept as guard
        voice_notes = (
            db.query(VoiceNote)
            .filter(VoiceNote.user_id == user_id, VoiceNote.created_at >= window_start_iso)
            .order_by(VoiceNote.created_at.asc())
            .limit(50)
            .all()
        )

        all_activities = []
        for r in reminders:
            if not _in_window(r.datetime):
                continue
            all_activities.append({
                "time": r.datetime,
                "text": f"Reminder: {r.title} at {r.datetime}"
            })
        for e in expenses:
            if not _in_window(e.date):
                continue
            all_activities.append({
                "time": e.date,
                "text": f"Expense: {e.amount} for {e.category} ({e.description or ''})"
            })
        for v in voice_notes:
            if not _in_window(v.created_at):
                continue
            if v.transcript:
                all_activities.append({
                    "time": v.created_at,
                    "text": f"Voice Note: {v.transcript[:100]}"
                })

        # Final sort by time
        all_activities.sort(key=lambda x: x["time"])
        activities = [a["text"] for a in all_activities]

        # GPS reverse geocoding if coordinates provided
        location = "Unknown location"
        if request.latitude and request.longitude:
            try:
                from geopy.geocoders import Nominatim
                geolocator = Nominatim(user_agent="travel_buddy_app")
                geo_result = await asyncio.to_thread(
                    geolocator.reverse,
                    f"{request.latitude},{request.longitude}",
                    timeout=5,
                )
                location = geo_result.address if geo_result else f"{request.latitude},{request.longitude}"
            except Exception as geo_err:
                logger.warning(f"Geocoding failed: {geo_err}")
                location = f"{request.latitude},{request.longitude}"

        # Call AI summarizer (has its own fallback to mock mode)
        summary_result = await summarize_diary([{"date": f"last_{days}_days", "activities": activities}])
        summary_text = summary_result.get("total_summary", "No activities recorded recently.")

        db_entry = DiaryEntry(
            user_id=user_id,
            title=f"Travel Diary — {date_str}",
            content=f"Location: {location}\n\n{summary_text}",
            location=location,
            timestamp=now_iso,
            is_auto_generated=True
        )
        db.add(db_entry)
        db.commit()
        db.refresh(db_entry)
        return db_entry

    except Exception as e:
        logger.error(f"Error generating AI diary entry: {e}")
        try:
            db.rollback()
        except Exception:
            pass

        # Fallback — use a fresh session to avoid broken transaction state
        try:
            try:
                from ..database import SessionLocal
            except ImportError:
                from database import SessionLocal
            fallback_db = SessionLocal()
            db_entry = DiaryEntry(
                user_id=user_id,
                title=f"Travel Diary — {date_str}",
                content="An automatic summary could not be generated. Add an API key to enable AI features, or add activities (reminders/expenses) and try again.",
                location=None,
                timestamp=now_iso,
                is_auto_generated=True
            )
            fallback_db.add(db_entry)
            fallback_db.commit()
            fallback_db.refresh(db_entry)
            fallback_db.close()
            return db_entry
        except Exception as fallback_err:
            logger.error(f"Fallback diary save also failed: {fallback_err}")
            raise RuntimeError(f"Could not save diary entry: {fallback_err}") from fallback_err


def get_diary_entries(db: Session, user_id: str = "default") -> List[DiaryEntry]:
    """GET /api/diary."""
    return db.query(DiaryEntry).filter(DiaryEntry.user_id == user_id).order_by(DiaryEntry.timestamp.desc()).all()


def get_diary_summary(db: Session, user_id: str = "default") -> Dict:
    """GET /api/diary/summary."""
    entries = (
        db.query(DiaryEntry)
        .filter(DiaryEntry.user_id == user_id)
        .order_by(DiaryEntry.timestamp.desc())
        .all()
    )
    total_entries = len(entries)
    auto_gen_count = sum(1 for e in entries if e.is_auto_generated)
    manual_count = total_entries - auto_gen_count
    return {
        "total_entries": total_entries,
        "auto_generated": auto_gen_count,
        "manual_entries": manual_count,
        "last_entry_at": entries[0].timestamp if entries else None
    }


def update_entry(db: Session, entry_id: int, update: DiaryUpdateRequest, user_id: str) -> Optional[DiaryEntry]:
    """PUT /api/diary/{id}: Update diary entry only if it belongs to user_id."""
    entry = (
        db.query(DiaryEntry)
        .filter(DiaryEntry.id == entry_id, DiaryEntry.user_id == user_id)
        .first()
    )
    if not entry:
        return None
    if update.content is not None:
        entry.content = update.content
    if update.title is not None:
        entry.title = update.title
    if update.location is not None:
        entry.location = update.location
    if update.imageUrl is not None:
        entry.imageUrl = update.imageUrl
    db.commit()
    db.refresh(entry)
    return entry


def delete_entry(db: Session, entry_id: int, user_id: str) -> bool:
    """DELETE /api/diary/{id}: Delete only if it belongs to user_id."""
    entry = (
        db.query(DiaryEntry)
        .filter(DiaryEntry.id == entry_id, DiaryEntry.user_id == user_id)
        .first()
    )
    if entry:
        db.delete(entry)
        db.commit()
        return True
    return False


def export_diary(db: Session, fmt: str, user_id: Optional[str] = None) -> str:
    """
    GET /api/diary/export?format=pdf|docx
    Returns the file path of the generated export file, scoped to user_id.
    """
    query = db.query(DiaryEntry).order_by(DiaryEntry.timestamp.asc())
    if user_id:
        query = query.filter(DiaryEntry.user_id == user_id)
    entries = query.all()

    # Ensure export directory exists
    Path(EXPORT_DIR).mkdir(parents=True, exist_ok=True)

    if fmt.lower() == "docx":
        return _export_docx(entries, user_id=user_id)
    else:
        return _export_pdf(entries, user_id=user_id)


def _export_pdf(entries: List[DiaryEntry], user_id: Optional[str] = None) -> str:
    """Generate PDF using reportlab, scoped to a specific user."""
    from reportlab.lib.pagesizes import A4
    from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer
    from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
    from reportlab.lib.units import cm

    safe_uid = (user_id or "shared").replace("/", "_")[:32]
    ts = datetime.utcnow().strftime("%Y%m%d_%H%M%S_%f")
    file_path = os.path.join(EXPORT_DIR, f"travel_diary_{safe_uid}_{ts}.pdf")
    doc = SimpleDocTemplate(file_path, pagesize=A4,
                            leftMargin=2*cm, rightMargin=2*cm,
                            topMargin=2*cm, bottomMargin=2*cm)
    styles = getSampleStyleSheet()
    title_style = ParagraphStyle('Title', parent=styles['Title'], fontSize=18, spaceAfter=12)
    heading_style = ParagraphStyle('Heading', parent=styles['Heading2'], fontSize=12, spaceAfter=6)
    body_style = styles['BodyText']

    story = [Paragraph("Travel Diary", title_style), Spacer(1, 0.5*cm)]

    for entry in entries:
        story.append(Paragraph(entry.title, heading_style))
        story.append(Paragraph(f"📅 {entry.timestamp[:10]}", body_style))
        if entry.location:
            story.append(Paragraph(f"📍 {entry.location}", body_style))
        story.append(Spacer(1, 0.2*cm))
        # Escape HTML characters for reportlab
        content = entry.content.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')
        story.append(Paragraph(content, body_style))
        story.append(Spacer(1, 0.5*cm))

    doc.build(story)
    return file_path


def _export_docx(entries: List[DiaryEntry], user_id: Optional[str] = None) -> str:
    """Generate DOCX using python-docx, scoped to a specific user."""
    from docx import Document
    from docx.shared import Pt

    safe_uid = (user_id or "shared").replace("/", "_")[:32]
    ts = datetime.utcnow().strftime("%Y%m%d_%H%M%S_%f")
    file_path = os.path.join(EXPORT_DIR, f"travel_diary_{safe_uid}_{ts}.docx")
    doc = Document()
    doc.add_heading("Travel Diary", 0)

    for entry in entries:
        doc.add_heading(entry.title, level=2)
        doc.add_paragraph(f"Date: {entry.timestamp[:10]}")
        if entry.location:
            doc.add_paragraph(f"Location: {entry.location}")
        doc.add_paragraph(entry.content)
        doc.add_paragraph("")  # Spacer

    doc.save(file_path)
    return file_path
