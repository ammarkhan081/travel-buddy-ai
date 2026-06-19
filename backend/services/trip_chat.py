"""Per-trip chat grounding.

Turns questions like:
  • "How much did I spend on the Kalam trip?"
  • "What were my reminders in Skardu?"
  • "How many rupees on food at Shangrila Resort?"
into exact, grounded answers by pulling the records tagged to the matching
trip(s) and computing real totals — instead of relying only on fuzzy semantic
retrieval. The resulting TRIP FACTS block is injected into the chat context as
ground truth.

It also provides:
  • trip_destination_map(): {trip_id: destination} for enriching RAG docs.
  • detect_trips_in_query(): find which of the user's trips a message refers to.
"""

import logging
import re
from typing import Dict, List, Optional

from sqlalchemy.orm import Session

try:
    from ..models.trip import Trip
    from ..models.expense import Expense
    from ..models.reminder import Reminder
    from ..models.voice_note import VoiceNote
    from ..models.diary_entry import DiaryEntry
    from . import trip_service
except ImportError:
    from models.trip import Trip
    from models.expense import Expense
    from models.reminder import Reminder
    from models.voice_note import VoiceNote
    from models.diary_entry import DiaryEntry
    from services import trip_service

logger = logging.getLogger(__name__)


def trip_destination_map(db: Session, user_id: str) -> Dict[int, str]:
    """Return {trip_id: destination} so RAG docs can be enriched with trip names."""
    out: Dict[int, str] = {}
    try:
        for t in trip_service.get_trips_for_user(db, user_id):
            out[int(t.id)] = t.destination or ""
    except Exception as e:
        logger.warning("trip_destination_map_failed", extra={"error": str(e)})
    return out


def detect_trips_in_query(db: Session, user_id: str, text: str) -> List[Trip]:
    """Find trips referenced in the message by destination name (longest match first)."""
    if not text:
        return []
    lowered = text.lower()
    matched: List[Trip] = []
    seen = set()
    try:
        trips = trip_service.get_trips_for_user(db, user_id)
    except Exception:
        return []
    # Longer destination names first so "azad kashmir" wins over "kashmir".
    for t in sorted(trips, key=lambda x: len(x.destination or ""), reverse=True):
        dest = (t.destination or "").strip().lower()
        if not dest:
            continue
        # Match the full destination, or its leading token (only if distinctive
        # enough — short tokens like "new"/"the" would cause false positives).
        first_word = dest.split(",")[0].split()[0] if dest.split() else dest
        matched_name = bool(re.search(rf"\b{re.escape(dest)}\b", lowered))
        if not matched_name and len(first_word) >= 4:
            matched_name = bool(re.search(rf"\b{re.escape(first_word)}\b", lowered))
        if matched_name:
            if t.id not in seen:
                matched.append(t)
                seen.add(t.id)
    return matched


def _records_for_trip(db: Session, user_id: str, trip: Trip):
    """Expenses/reminders/notes/diary tagged to this trip."""
    expenses = db.query(Expense).filter(Expense.user_id == user_id, Expense.trip_id == trip.id).all()
    reminders = db.query(Reminder).filter(Reminder.user_id == user_id, Reminder.trip_id == trip.id).all()
    notes = db.query(VoiceNote).filter(VoiceNote.user_id == user_id, VoiceNote.trip_id == trip.id).all()
    diary = db.query(DiaryEntry).filter(DiaryEntry.user_id == user_id, DiaryEntry.trip_id == trip.id).all()
    return expenses, reminders, notes, diary


# Map a free-text merchant/keyword mentioned in the query to expenses.
def _mentions_food(text: str) -> bool:
    return any(w in text.lower() for w in ("food", "eat", "eating", "meal", "restaurant", "dining", "dinner", "lunch", "breakfast"))


def build_trip_facts(db: Session, user_id: str, trips: List[Trip], query_text: str = "") -> Optional[str]:
    """Build a deterministic TRIP FACTS block for the matched trip(s)."""
    if not trips:
        return None

    blocks: List[str] = []
    q = (query_text or "").lower()
    for trip in trips[:3]:  # cap to avoid overlong context
        expenses, reminders, notes, diary = _records_for_trip(db, user_id, trip)

        lines: List[str] = []
        window = trip.start_date[:10] if trip.start_date else "?"
        if trip.end_date:
            window += f" to {trip.end_date[:10]}"
        lines.append(f"TRIP: {trip.destination} ({trip.status}, {window})")

        # Expenses — total + by category + by merchant.
        if expenses:
            total = sum(float(e.amount or 0) for e in expenses)
            lines.append(f"  Total spent: PKR {total:,.0f} across {len(expenses)} expense(s).")

            by_cat: Dict[str, float] = {}
            by_merchant: Dict[str, float] = {}
            for e in expenses:
                by_cat[e.category or "other"] = by_cat.get(e.category or "other", 0.0) + float(e.amount or 0)
                m = (e.merchant or "").strip()
                if m:
                    by_merchant[m] = by_merchant.get(m, 0.0) + float(e.amount or 0)
            lines.append("  By category: " + ", ".join(f"{k} PKR {v:,.0f}" for k, v in sorted(by_cat.items(), key=lambda x: -x[1])))
            if by_merchant:
                lines.append("  By place/merchant: " + ", ".join(f"{k} PKR {v:,.0f}" for k, v in sorted(by_merchant.items(), key=lambda x: -x[1])))

            # Itemised list (capped) so "what did I spend on" is answerable.
            for e in expenses[:15]:
                where = f" @ {e.merchant}" if e.merchant else (f" in {e.location}" if e.location else "")
                desc = f" — {e.description}" if e.description else ""
                lines.append(f"    • {(e.date or '')[:10]} {e.category}: PKR {float(e.amount or 0):,.0f}{where}{desc}")

            # Food-specific roll-up when the user asks about food/a place.
            if _mentions_food(q):
                food_total = sum(float(e.amount or 0) for e in expenses if (e.category or "").lower() == "food")
                lines.append(f"  Food subtotal on this trip: PKR {food_total:,.0f}.")
        else:
            lines.append("  No expenses recorded for this trip yet.")

        if reminders:
            lines.append(f"  Reminders ({len(reminders)}): " + "; ".join(
                f"{r.title} [{(r.datetime or '')[:16]}, {r.status}]" for r in reminders[:10]
            ))
        if notes:
            lines.append("  Voice notes: " + " | ".join(f'"{(n.transcript or "")[:120]}"' for n in notes[:6]))
        if diary:
            lines.append("  Diary entries: " + "; ".join((d.title or "")[:60] for d in diary[:6]))

        blocks.append("\n".join(lines))

    if not blocks:
        return None
    header = (
        "TRIP FACTS (authoritative, computed from the user's tagged records — "
        "use these exact numbers for any per-trip question):"
    )
    return header + "\n" + "\n\n".join(blocks)
