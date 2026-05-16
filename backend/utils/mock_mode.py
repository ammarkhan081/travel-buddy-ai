"""Mock AI responses for testing and development without API keys."""
import logging
from datetime import datetime, timedelta
from typing import List, Dict

logger = logging.getLogger(__name__)


def get_mock_transcription(text: str = "This is a mock transcription.") -> Dict:
    """Mock Whisper transcription payload used by STT pipeline."""
    cleaned = (text or "This is a mock transcription.").strip()
    return {
        "transcript": cleaned,
        "confidence": 0.9,
        "language": "en",
        "provider": "mock",
        "word_count": len(cleaned.split()),
    }


def get_mock_intent(text: str) -> Dict:
    """Mock intent payload compatible with detect_intent_gpt callers."""
    text_l = (text or "").lower()
    now = datetime.now()

    intent = "other"
    scheduled_time = None
    title = (text or "Mock entry").strip()[:80] or "Mock entry"

    if any(k in text_l for k in ["remind", "reminder", "tomorrow", "today", "schedule"]):
        intent = "reminder"
        scheduled_time = (now + timedelta(days=1, hours=1)).replace(second=0, microsecond=0)
    elif any(k in text_l for k in ["spent", "expense", "paid", "cost", "bought"]):
        intent = "expense"
    elif any(k in text_l for k in ["note", "remember this", "save this"]):
        intent = "note"
    elif any(k in text_l for k in ["what", "when", "where", "how", "show", "list"]):
        intent = "query"

    return {
        "intent": intent,
        "title": title,
        "scheduled_time": scheduled_time,
        "location": None,
        "priority": "medium",
        "confidence": 0.75,
        "entities": {},
    }


def get_mock_expense(text: str) -> Dict:
    """Mock expense payload compatible with extract_expense_gpt callers."""
    text_l = (text or "").lower()
    category = "other"
    if any(k in text_l for k in ["food", "restaurant", "lunch", "dinner", "breakfast"]):
        category = "food"
    elif any(k in text_l for k in ["taxi", "uber", "bus", "train", "flight"]):
        category = "transport"
    elif any(k in text_l for k in ["hotel", "hostel", "airbnb"]):
        category = "accommodation"
    elif any(k in text_l for k in ["museum", "ticket", "tour"]):
        category = "entertainment"
    elif any(k in text_l for k in ["shop", "shopping", "buy", "purchase"]):
        category = "shopping"

    return {
        "amount": 25.0,
        "currency": "USD",
        "category": category,
        "description": (text or "Mock expense").strip()[:100] or "Mock expense",
        "location": None,
        "confidence": 0.7,
    }

def get_mock_summary(entries: List[Dict]) -> Dict:
    """Returns a fake summary when AI is disabled/unavailable."""
    logger.info("Generating mock diary summary")
    
    # Calculate some basic facts
    num_activities = len(entries[0].get("activities", [])) if entries else 0
    
    return {
        "total_summary": f"Today was a productive day with {num_activities} activities recorded. I tracked my travel progress, reminders, and expenses to keep everything organized.",
        "highlights": [
            "Successfully tracked daily activities",
            f"Managed {num_activities} individual items",
            "Kept the travel diary up to date"
        ],
        "daily_summaries": [
            {
                "date": "recent",
                "summary": "Spent the day managing travel logistics and keeping track of expenses and reminders.",
                "highlights": ["Organized travel items", "Maintained log"]
            }
        ]
    }
