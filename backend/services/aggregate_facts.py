"""Deterministic account-wide aggregate facts for chat grounding.

Aggregation questions ("how much did I spend in total?", "how much on food?",
"how many reminders do I have?") must be answered from real SQL aggregates, not
from fuzzy semantic retrieval — which can miss or double-count chunks and produce
wrong totals. This module computes authoritative totals/counts straight from the
database and returns a labelled facts block that is injected into the chat
context as ground truth (mirrors how trip_chat.build_trip_facts grounds per-trip
questions).

All amounts are in PKR (the app default). Every query is scoped strictly to the
requesting user.
"""

import logging
from typing import Optional

from sqlalchemy import func
from sqlalchemy.orm import Session

try:
    from ..models.expense import Expense
    from ..models.reminder import Reminder
    from ..models.voice_note import VoiceNote
    from ..models.diary_entry import DiaryEntry
except ImportError:
    from models.expense import Expense
    from models.reminder import Reminder
    from models.voice_note import VoiceNote
    from models.diary_entry import DiaryEntry

logger = logging.getLogger(__name__)

# Phrases that signal an aggregation / counting question. We only build the facts
# block when one of these is present, so ordinary personal questions
# ("what was my reminder about?") are not cluttered with totals.
_AGG_CUES = (
    "how much", "how many", "total", "in total", "altogether", "overall",
    "sum of", "on average", "average", "number of", "count of", "so far",
    "all time", "all-time", "across all", "grand total", "combined", "spent",
)

# Map free-text words in the question to the canonical stored expense category.
_CATEGORY_SYNONYMS = {
    "food": ("food", "eat", "eating", "meal", "meals", "restaurant", "dining",
             "dinner", "lunch", "breakfast", "cafe"),
    "transport": ("transport", "transportation", "taxi", "uber", "bus", "train",
                  "flight", "fuel", "petrol", "fare"),
    "accommodation": ("accommodation", "hotel", "hostel", "stay", "lodging", "airbnb"),
    "shopping": ("shopping", "shop", "souvenir", "souvenirs", "clothes", "clothing"),
    "entertainment": ("entertainment", "tour", "museum", "ticket", "tickets",
                      "activity", "activities"),
}


def _has_agg_cue(text: str) -> bool:
    t = (text or "").lower()
    return any(cue in t for cue in _AGG_CUES)


def _detected_category(text: str) -> Optional[str]:
    t = (text or "").lower()
    for category, words in _CATEGORY_SYNONYMS.items():
        if any(w in t for w in words):
            return category
    return None


def build_aggregate_facts(db: Session, user_id: str, query_text: str) -> Optional[str]:
    """Return an authoritative ACCOUNT FACTS block, or None when the message is
    not an aggregation/count question (so normal turns are unaffected)."""
    if not _has_agg_cue(query_text):
        return None

    lines = []

    # ── Expense aggregates (grouped in SQL, not summed in Python) ─────────────
    cat_rows = (
        db.query(
            Expense.category,
            func.coalesce(func.sum(Expense.amount), 0.0),
            func.count(Expense.id),
        )
        .filter(Expense.user_id == user_id)
        .group_by(Expense.category)
        .all()
    )
    total_amount = sum(float(r[1] or 0) for r in cat_rows)
    total_count = sum(int(r[2] or 0) for r in cat_rows)

    if total_count > 0:
        lines.append(
            f"- Total spent (all trips, all time): PKR {total_amount:,.0f} "
            f"across {total_count} expense(s)."
        )
        # Normalise stored categories to lowercase so casing differences
        # (e.g. a manually-entered "Food" vs a voice-extracted "food") don't
        # break per-category lookups.
        by_cat = sorted(
            ((str(r[0] or "other").strip().lower(), float(r[1] or 0), int(r[2] or 0)) for r in cat_rows),
            key=lambda x: -x[1],
        )
        lines.append(
            "- By category: "
            + ", ".join(f"{c} PKR {v:,.0f} ({n})" for c, v, n in by_cat)
        )

        # If the user named a category, surface that subtotal. Match the
        # canonical category OR any of its synonyms (case-insensitive), so
        # "food"/"Food"/"dining"/"restaurant" all roll up together — otherwise
        # the AI gets a contradictory "food = 0 but total = 800" signal.
        cat = _detected_category(query_text)
        if cat:
            wanted = set(_CATEGORY_SYNONYMS.get(cat, ())) | {cat}
            matched = [x for x in by_cat if x[0] in wanted]
            if matched:
                cat_total = sum(x[1] for x in matched)
                cat_count = sum(x[2] for x in matched)
                lines.append(
                    f"- Spent on {cat}: PKR {cat_total:,.0f} across {cat_count} expense(s)."
                )
            else:
                lines.append(f"- Spent on {cat}: PKR 0 (no {cat} expenses recorded).")
    else:
        lines.append("- No expenses recorded yet.")

    # ── Counts for reminders / voice notes / diary ────────────────────────────
    reminder_total = (
        db.query(func.count(Reminder.id)).filter(Reminder.user_id == user_id).scalar() or 0
    )
    reminder_pending = (
        db.query(func.count(Reminder.id))
        .filter(Reminder.user_id == user_id, Reminder.status == "pending")
        .scalar()
        or 0
    )
    voice_count = (
        db.query(func.count(VoiceNote.id)).filter(VoiceNote.user_id == user_id).scalar() or 0
    )
    diary_count = (
        db.query(func.count(DiaryEntry.id)).filter(DiaryEntry.user_id == user_id).scalar() or 0
    )

    lines.append(f"- Reminders: {reminder_pending} pending of {reminder_total} total.")
    lines.append(f"- Voice notes saved: {voice_count}. Diary entries: {diary_count}.")

    header = (
        "ACCOUNT FACTS (authoritative, computed directly from ALL your saved "
        "records — use these exact totals for overall/all-time questions; do "
        "NOT add up the retrieved snippets yourself):"
    )
    return header + "\n" + "\n".join(lines)
