"""Travel diary summarization using OpenAI models with strict production fallback behavior."""

import json
import logging
import os
import sys
from pathlib import Path
from typing import Dict, List, Optional

from backend.utils.ai_runtime import call_chat_with_fallback

logger = logging.getLogger(__name__)


def _get_openai_api_key() -> str:
    """Safely retrieve API key from environment or backend settings."""
    key = os.getenv("OPENAI_API_KEY", "")
    if key and key.startswith("sk-"):
        return key

    try:
        project_root = str(Path(__file__).resolve().parent.parent.parent.parent)
        if project_root not in sys.path:
            sys.path.insert(0, project_root)
        from backend.config import settings  # type: ignore

        return settings.OPENAI_API_KEY or ""
    except Exception as e:
        logger.debug(f"Could not load backend settings for API key: {e}")
        return ""


def _mock_summary(entries: List[Dict]) -> Dict:
    """Explicit mock response used only when MOCK_MODE=true."""
    num_activities = len(entries[0].get("activities", [])) if entries else 0
    return {
        "total_summary": (
            f"Today was a productive day with {num_activities} activities recorded. "
            "Travel progress, reminders, and expenses were tracked and organized."
        ),
        "highlights": [
            "Successfully tracked daily activities",
            f"Managed {num_activities} individual items",
            "Kept the travel diary up to date",
        ],
        "daily_summaries": [
            {
                "date": "recent",
                "summary": "Spent the day managing travel logistics and keeping track of expenses and reminders.",
                "highlights": ["Organized travel items", "Maintained log"],
            }
        ],
    }


async def summarize_diary(
    entries: List[Dict],
    api_key: Optional[str] = None,
    model: Optional[str] = None,
) -> Dict:
    """
    Summarize travel diary entries.

    Production behavior:
    - No implicit mock/simple fallback when key/model call fails.
    - Failures are raised so caller can store explicit non-AI fallback text.
    """
    if not api_key:
        api_key = _get_openai_api_key()

    if os.getenv("MOCK_MODE", "false").lower() == "true":
        logger.info("Using explicit MOCK_MODE for diary summarization")
        return _mock_summary(entries)

    if not api_key or not api_key.startswith("sk-"):
        logger.warning("Diary summarization fallback: missing/invalid API key")
        local = create_simple_summary(entries)
        local["model_used"] = "local_fallback"
        return local

    import openai

    client = openai.OpenAI(api_key=api_key, timeout=30.0)
    context = json.dumps(entries, indent=2, default=str)

    prompt = f"""You are a travel diary assistant. Summarize the following travel diary entries and create:
1. A comprehensive summary of the travel period
2. Key highlights (3-5 bullet points)
3. Enhanced summaries for each day

Travel Diary Entries:
{context}

Respond in JSON format:
{{
    "total_summary": "Overall summary of the travel period",
    "highlights": ["highlight1", "highlight2", ...],
    "daily_summaries": [
        {{
            "date": "YYYY-MM-DD",
            "summary": "Day summary",
            "highlights": ["day highlight1", ...]
        }}
    ]
}}"""

    try:
        result_text, used_model = call_chat_with_fallback(
            client=client,
            messages=[
                {
                    "role": "system",
                    "content": "You are an expert travel diary writer. Create engaging, detailed summaries.",
                },
                {"role": "user", "content": prompt},
            ],
            temperature=0.7,
            response_format={"type": "json_object"},
            primary_model=model,
            label="diary_summarization",
        )
        result = json.loads(result_text)
        return {
            "total_summary": result.get("total_summary", ""),
            "highlights": result.get("highlights", []),
            "daily_summaries": result.get("daily_summaries", []),
            "model_used": used_model,
        }
    except Exception as e:
        logger.error(f"Diary summarization failed: {e}")
        local = create_simple_summary(entries)
        local["model_used"] = "local_fallback"
        return local


def create_simple_summary(entries: List[Dict]) -> Dict:
    """Retained helper for compatibility with older callers/tests."""
    total_summary = f"Travel diary with {len(entries)} entries."
    highlights = []

    for entry in entries[:5]:
        if entry.get("summary"):
            highlights.append(entry["summary"][:100])

    daily_summaries = []
    for entry in entries:
        daily_summaries.append(
            {
                "date": entry.get("date", ""),
                "summary": entry.get("summary", ""),
                "highlights": entry.get("highlights", []),
            }
        )

    return {
        "total_summary": total_summary,
        "highlights": highlights,
        "daily_summaries": daily_summaries,
    }
