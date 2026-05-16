"""Expense extraction using GPT-4 Turbo NER + Regex hybrid."""

import logging
import json
import re
from typing import Dict, Optional
import openai
from backend.utils.ai_runtime import call_chat_with_fallback
from backend.utils.error_policy import ExtractionError

logger = logging.getLogger(__name__)

# Common expense categories
EXPENSE_CATEGORIES = [
    "food", "restaurant", "cafe", "dining",
    "transport", "taxi", "uber", "flight", "train", "bus",
    "accommodation", "hotel", "hostel", "airbnb",
    "shopping", "souvenir", "clothing",
    "entertainment", "tour", "museum", "activity",
    "other"
]

# Currency patterns
CURRENCY_PATTERNS = {
    r'PKR|(?<!\w)Rs\.?(?!\w)': 'PKR',  # Pakistani Rupee — checked first (app default)
    r'\$|USD|dollar': 'USD',
    r'€|EUR|euro': 'EUR',
    r'£|GBP|pound': 'GBP',
    r'₹|INR|Indian\s+rupee': 'INR',
    r'¥|JPY|yen': 'JPY',
}


async def extract_expense_gpt(
    text: str,
    api_key: Optional[str] = None,
    model: Optional[str] = None
) -> Dict:
    """
    Extract expense information using GPT-4 Turbo.
    
    Args:
        text: Input text containing expense information
        api_key: OpenAI API key
        model: Model to use
        
    Returns:
        dict with amount, currency, category, description, location, confidence
    """
    try:
        if not api_key:
            import sys
            from pathlib import Path
            sys.path.append(str(Path(__file__).parent.parent.parent))
            from backend.config import settings
            api_key = settings.OPENAI_API_KEY
        
        # Check for mock mode
        import os
        MOCK_MODE = os.getenv("MOCK_MODE", "false").lower() == "true"
        
        if MOCK_MODE:
            logger.info("Using mock mode for expense extraction (no API key)")
            from backend.utils.mock_mode import get_mock_expense
            return get_mock_expense(text)
        
        client = openai.OpenAI(api_key=api_key, timeout=30.0)
        
        prompt = f"""Extract expense information from the following text:
"{text}"

Respond in JSON format:
{{
    "amount": <number>,
    "currency": "PKR|USD|EUR|GBP|INR|JPY|etc",
    "category": "food|transport|accommodation|shopping|entertainment|other",
    "description": "brief description",
    "location": "location if mentioned or null",
    "confidence": <0-1>
}}
Default currency is PKR (Pakistani Rupees) if none is mentioned."""

        result_text, used_model = call_chat_with_fallback(
            client=client,
            messages=[
                {"role": "system", "content": "You are an expert at extracting expense information from text. Always respond with valid JSON."},
                {"role": "user", "content": prompt}
            ],
            temperature=0.1,
            response_format={"type": "json_object"},
            primary_model=model,
            label="expense_extraction",
        )
        result = json.loads(result_text)
        
        # Validate and enhance with regex
        amount = result.get("amount", 0)
        currency = result.get("currency", "USD")
        category = result.get("category", "other")

        # Use regex to extract all amount mentions (multi-amount utterances).
        # Keep backward compatibility: `amount` remains a single numeric total.
        parsed_amounts, regex_currency = extract_all_amounts_with_regex(text)
        if parsed_amounts:
            # If the model missed amount or returned 0/invalid, trust parsed total.
            if not amount or float(amount) <= 0:
                amount = round(_resolve_multi_amount_value(text, parsed_amounts), 2)
            # If model returned one amount but transcript has multiple numbers,
            # prefer parsed sum because users often say "100 for X and 50 for Y".
            elif len(parsed_amounts) > 1:
                amount = round(_resolve_multi_amount_value(text, parsed_amounts), 2)
        if regex_currency and currency == "USD":
            currency = regex_currency
        
        # Validate category
        if category not in EXPENSE_CATEGORIES:
            category = classify_category(text)
        
        payload = {
            "amount": float(amount),
            "currency": currency.upper(),
            "category": category.lower(),
            "description": result.get("description", text[:100]),
            "location": result.get("location"),
            "confidence": result.get("confidence", 0.85),
            "model_used": used_model,
        }
        return _validate_expense_payload(payload)
    except Exception as e:
        logger.error(f"GPT expense extraction failed: {e}")
        # Fallback to regex
        fallback = extract_with_regex_hybrid(text)
        fallback["model_used"] = "regex_fallback"
        return _validate_expense_payload(fallback)


def extract_with_regex(text: str) -> tuple:
    """Extract amount and currency using regex patterns."""
    # Amount patterns — PKR first since it's the app default currency
    amount_patterns = [
        (r'(\d+\.?\d*)\s*(PKR|Rs\.?)', 'PKR'),
        (r'\$(\d+\.?\d*)', 'USD'),
        (r'(\d+\.?\d*)\s*(dollars?|USD)', 'USD'),
        (r'€(\d+\.?\d*)', 'EUR'),
        (r'(\d+\.?\d*)\s*(euros?|EUR)', 'EUR'),
        (r'£(\d+\.?\d*)', 'GBP'),
        (r'(\d+\.?\d*)\s*(pounds?|GBP)', 'GBP'),
        (r'₹(\d+\.?\d*)', 'INR'),
        (r'(\d+\.?\d*)\s*(Indian\s+rupees?|INR)', 'INR'),
    ]

    amount = None
    currency = None

    for pattern, curr in amount_patterns:
        match = re.search(pattern, text, re.IGNORECASE)
        if match:
            amount = float(match.group(1))
            currency = curr
            break
    
    # If no currency found, check for currency symbols
    if not currency:
        for pattern, curr in CURRENCY_PATTERNS.items():
            if re.search(pattern, text, re.IGNORECASE):
                currency = curr
                break
    
    return amount, currency


def extract_all_amounts_with_regex(text: str) -> tuple:
    """Extract all explicit monetary amounts and inferred currency."""
    # PKR first — app default currency for Pakistan
    amount_patterns = [
        (r'(\d+\.?\d*)\s*(PKR|Rs\.?)', 'PKR'),
        (r'\$(\d+\.?\d*)', 'USD'),
        (r'(\d+\.?\d*)\s*(dollars?|USD)', 'USD'),
        (r'€(\d+\.?\d*)', 'EUR'),
        (r'(\d+\.?\d*)\s*(euros?|EUR)', 'EUR'),
        (r'£(\d+\.?\d*)', 'GBP'),
        (r'(\d+\.?\d*)\s*(pounds?|GBP)', 'GBP'),
        (r'₹(\d+\.?\d*)', 'INR'),
        (r'(\d+\.?\d*)\s*(Indian\s+rupees?|INR)', 'INR'),
    ]

    amounts = []
    currency = None

    for pattern, curr in amount_patterns:
        for match in re.finditer(pattern, text, re.IGNORECASE):
            try:
                amounts.append(float(match.group(1)))
            except Exception:
                continue
            if not currency:
                currency = curr

    # Fallback currency inference if symbol/word was present but no direct pattern matched.
    if not currency:
        for pattern, curr in CURRENCY_PATTERNS.items():
            if re.search(pattern, text, re.IGNORECASE):
                currency = curr
                break

    return amounts, currency


def _resolve_multi_amount_value(text: str, amounts: list[float]) -> float:
    """
    Disambiguate multiple amounts:
    - If segments are connected with 'and/plus' and each has expense cue, sum them.
    - Otherwise prefer the largest amount (common for mentions like "budget 500, spent 50").
    """
    if not amounts:
        return 0.0
    if len(amounts) == 1:
        return amounts[0]

    segments = re.split(r"\band\b|\bplus\b|,", text.lower())
    cues = ("spent", "paid", "cost", "bought", "for", "$", "pkr", "rs", "usd", "eur", "inr", "gbp")
    segment_amount_counts = 0
    for seg in segments:
        seg_amounts, _ = extract_all_amounts_with_regex(seg)
        if seg_amounts and any(c in seg for c in cues):
            segment_amount_counts += 1
    if segment_amount_counts >= 2:
        return sum(amounts)
    return max(amounts)


def _validate_expense_payload(payload: Dict) -> Dict:
    try:
        payload["amount"] = float(payload.get("amount", 0.0))
    except Exception:
        payload["amount"] = 0.0
    if payload["amount"] < 0:
        payload["amount"] = 0.0
    payload["currency"] = str(payload.get("currency", "USD")).upper()
    payload["category"] = str(payload.get("category", "other")).lower()
    if payload["category"] not in EXPENSE_CATEGORIES:
        payload["category"] = "other"
    try:
        c = float(payload.get("confidence", 0.0))
    except Exception:
        c = 0.0
    payload["confidence"] = max(0.0, min(1.0, c))
    if not payload.get("description"):
        payload["description"] = "Expense entry"
    return payload


def extract_with_regex_hybrid(text: str) -> Dict:
    """Extract expense using regex only (fallback)."""
    amount, currency = extract_with_regex(text)
    
    if not amount:
        # Try to find any number
        numbers = re.findall(r'\d+\.?\d*', text)
        if numbers:
            amount = float(numbers[0])
    
    if not currency:
        currency = "USD"  # Default
    
    category = classify_category(text)
    
    return {
        "amount": float(amount) if amount else 0.0,
        "currency": currency,
        "category": category,
        "description": text[:100],
        "location": None,
        "confidence": 0.6
    }


def classify_category(text: str) -> str:
    """Classify expense category based on keywords."""
    text_lower = text.lower()
    
    category_keywords = {
        "food": ["food", "restaurant", "cafe", "dining", "meal", "lunch", "dinner", "breakfast"],
        "transport": ["taxi", "uber", "flight", "train", "bus", "metro", "transport"],
        "accommodation": ["hotel", "hostel", "airbnb", "accommodation", "stay"],
        "shopping": ["shopping", "souvenir", "clothing", "buy", "purchase"],
        "entertainment": ["tour", "museum", "activity", "entertainment", "ticket"]
    }
    
    for category, keywords in category_keywords.items():
        if any(keyword in text_lower for keyword in keywords):
            return category
    
    return "other"

