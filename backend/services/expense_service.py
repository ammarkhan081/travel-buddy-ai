"""Service for expense management using SQLAlchemy."""

import logging
import tempfile
from datetime import datetime
from typing import Optional, List, Dict
from sqlalchemy.orm import Session
from sqlalchemy import func
try:
    from ..models.expense import Expense
    from ..schemas.expenses import ExpenseCreate, ExpenseResponse
    from ..config import settings
except ImportError:
    from models.expense import Expense
    from schemas.expenses import ExpenseCreate, ExpenseResponse
    from config import settings
from ai.inference.expense_parser.expense_extractor import extract_expense_gpt
from ai.inference.stt_pipeline.transcriber import normalize_transcript
from backend.utils.transcript_utils import normalize_for_nlp
from openai import OpenAI
from backend.utils.error_policy import ExtractionError
from backend.utils.time_utils import now_utc_iso, to_utc_iso
from backend.utils.ai_runtime import call_with_retries

logger = logging.getLogger(__name__)

async def create_expense(db: Session, expense_data: ExpenseCreate) -> Expense:
    """Create a new manual expense (auto-scoped to the user's active trip)."""
    try:
        user_id = getattr(expense_data, "user_id", "default")
        spend_date = to_utc_iso(expense_data.date)

        # Resolve the trip this expense belongs to (explicit > active trip).
        trip_id = getattr(expense_data, "trip_id", None)
        if trip_id is None:
            try:
                from .trip_service import resolve_trip_id_for_new_record
            except ImportError:
                from services.trip_service import resolve_trip_id_for_new_record
            trip_id = resolve_trip_id_for_new_record(db, user_id, spend_date)

        db_expense = Expense(
            amount=expense_data.amount,
            category=expense_data.category,
            description=expense_data.description,
            date=spend_date,
            user_id=user_id,
            intent="manual",
            created_at=now_utc_iso(),
            location=getattr(expense_data, "location", None),
            merchant=getattr(expense_data, "merchant", None),
            trip_id=trip_id,
        )
        db.add(db_expense)
        db.commit()
        db.refresh(db_expense)
        return db_expense
    except Exception as e:
        logger.error(f"Error creating expense: {e}")
        db.rollback()
        raise

async def extract_expense_from_voice(audio_file) -> Dict:
    """Extract expense from voice: Whisper STT + GPT extraction. Does NOT save to DB."""
    try:
        # --- Check API key before attempting AI calls ---
        api_key = settings.OPENAI_API_KEY
        if not api_key or not api_key.startswith("sk-"):
            raise ValueError("OpenAI API key not configured.")

        # Use an auto-cleaned temp handle and transcribe before it closes.
        with tempfile.NamedTemporaryFile(suffix=".wav") as tmp:
            tmp.write(audio_file.read())
            tmp.seek(0)

            # Transcribe with Whisper
            client = OpenAI(api_key=api_key, timeout=30.0)
            transcript_obj = call_with_retries(
                "expense_voice_whisper",
                lambda: client.audio.transcriptions.create(
                    model=settings.WHISPER_MODEL,
                    file=tmp
                ),
            )
        transcript = normalize_transcript(transcript_obj.text)

        # Extract expense details via GPT
        extraction = await extract_expense_gpt(normalize_for_nlp(transcript))
        
        # Ensure description is present
        if not extraction.get("description"):
            extraction["description"] = transcript

        return extraction

    except Exception as e:
        logger.error(f"Error in voice expense extraction: {e}")
        raise ExtractionError(f"Voice expense extraction failed: {e}") from e


def get_expenses(db: Session, user_id: str) -> List[Expense]:
    return db.query(Expense).filter(Expense.user_id == user_id).all()

def delete_expense(db: Session, expense_id: int, user_id: str) -> bool:
    """Delete an expense only if it belongs to user_id."""
    expense = (
        db.query(Expense)
        .filter(Expense.id == expense_id, Expense.user_id == user_id)
        .first()
    )
    if expense:
        db.delete(expense)
        db.commit()
        return True
    return False

def get_expense_summary(db: Session, user_id: str) -> Dict:
    """Audit Step 9: GET /api/expenses/summary."""
    expenses = db.query(Expense).filter(Expense.user_id == user_id).all()
    if not expenses:
        return {"total": 0, "by_category": {}, "by_date": []}
    
    total = sum(e.amount for e in expenses)
    
    by_category = {}
    for e in expenses:
        by_category[e.category] = by_category.get(e.category, 0) + e.amount
        
    # By date (simple aggregation)
    by_date_dict = {}
    for e in expenses:
        date_str = e.date.split('T')[0] if 'T' in e.date else e.date
        by_date_dict[date_str] = by_date_dict.get(date_str, 0) + e.amount
    
    by_date = [{"date": d, "total": t} for d, t in sorted(by_date_dict.items())]
    
    return {
        "total": total,
        "by_category": by_category,
        "by_date": by_date
    }

def filter_expenses(db: Session, user_id: str, category: Optional[str] = None, start: Optional[str] = None, end: Optional[str] = None) -> List[Expense]:
    """Audit Step 9: GET /api/expenses/filter."""
    query = db.query(Expense).filter(Expense.user_id == user_id)
    if category:
        query = query.filter(Expense.category == category)
    if start:
        query = query.filter(Expense.date >= start)
    if end:
        query = query.filter(Expense.date <= end)
    return query.all()
