"""Transcript normalization helpers for robust downstream NLP."""

from collections import Counter
import re

FILLERS = {
    "um", "uh", "er", "ah", "like", "you know", "hmm", "mm"
}

NUMBER_WORDS = {
    "zero": "0",
    "one": "1",
    "two": "2",
    "three": "3",
    "four": "4",
    "five": "5",
    "six": "6",
    "seven": "7",
    "eight": "8",
    "nine": "9",
    "ten": "10",
    "eleven": "11",
    "twelve": "12",
    "thirteen": "13",
    "fourteen": "14",
    "fifteen": "15",
    "sixteen": "16",
    "seventeen": "17",
    "eighteen": "18",
    "nineteen": "19",
    "twenty": "20",
    "thirty": "30",
    "forty": "40",
    "fifty": "50",
    "sixty": "60",
    "seventy": "70",
    "eighty": "80",
    "ninety": "90",
    "hundred": "100",
}

STOPWORDS = {
    "a", "an", "and", "are", "as", "at", "be", "by", "for", "from", "has", "have", "i", "in",
    "is", "it", "its", "me", "my", "of", "on", "or", "our", "that", "the", "this", "to", "was",
    "we", "were", "with", "you", "your", "please", "can", "could", "would", "should", "will", "just",
    "then", "than", "about", "into", "over", "under", "up", "down", "today", "tomorrow",
}


def clean_transcript(text: str) -> str:
    if not text:
        return ""
    cleaned = re.sub(r"\s+", " ", text).strip()
    cleaned = re.sub(r"[.]{3,}", "...", cleaned)
    cleaned = re.sub(r"[!?]{2,}", lambda m: m.group(0)[0], cleaned)
    cleaned = cleaned.strip(" \"'`")
    return cleaned


def normalize_for_nlp(text: str) -> str:
    """
    Lowercase, remove filler words, and normalize simple number words.
    Keeps this as NLP-only representation (not for UI display).
    """
    cleaned = clean_transcript(text).lower()
    if not cleaned:
        return ""

    tokens = cleaned.split()
    out = []
    for tok in tokens:
        t = re.sub(r"[^a-z0-9$€£₹.:/-]", "", tok)
        if not t:
            continue
        if t in FILLERS:
            continue
        out.append(NUMBER_WORDS.get(t, t))
    return " ".join(out).strip()


def extract_keywords(text: str, max_keywords: int = 6) -> str:
    """Extract deterministic high-signal keywords for retrieval-friendly indexing."""
    normalized = normalize_for_nlp(text)
    if not normalized:
        return ""

    tokens = re.findall(r"[a-z0-9$€£₹]+", normalized)
    filtered = [
        t for t in tokens
        if (t not in STOPWORDS) and (len(t) > 1 or t.isdigit())
    ]

    if not filtered:
        # Fallback to first cleaned tokens to avoid empty keyword fields.
        filtered = re.findall(r"[a-z0-9$€£₹]+", clean_transcript(text).lower())[:max_keywords]

    if not filtered:
        return ""

    first_index = {}
    for idx, tok in enumerate(filtered):
        if tok not in first_index:
            first_index[tok] = idx

    freq = Counter(filtered)
    ranked = sorted(freq.keys(), key=lambda t: (-freq[t], first_index[t]))
    return ", ".join(ranked[:max_keywords])
