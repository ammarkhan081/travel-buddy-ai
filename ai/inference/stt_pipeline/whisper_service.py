"""OpenAI Whisper API service for speech-to-text transcription."""

import asyncio
import os
import logging
from typing import Optional, BinaryIO
from openai import OpenAI
import sys
from pathlib import Path
sys.path.append(str(Path(__file__).parent.parent.parent))
from backend.config import settings
from backend.utils.ai_runtime import call_with_retries
from backend.utils.error_policy import STTError

logger = logging.getLogger(__name__)

def _is_mock_mode() -> bool:
    return os.getenv("MOCK_MODE", "false").lower() == "true"


async def transcribe_whisper(
    audio_file: BinaryIO,
    language: Optional[str] = "en",
    model: str = "whisper-1"
) -> dict:
    """
    Transcribe audio using OpenAI Whisper API.
    
    Args:
        audio_file: Audio file object (BinaryIO)
        language: Language code (ISO 639-1)
        model: Whisper model to use
        
    Returns:
        dict with transcript, confidence, language, duration
    """
    try:
        # Mock mode if explicitly requested
        if _is_mock_mode():
            logger.info("Using mock mode for transcription")
            from backend.utils.mock_mode import get_mock_transcription
            return get_mock_transcription("Remind me to visit Badshahi Mosque tomorrow at 3 PM")
        
        # Reset file pointer
        audio_file.seek(0)

        if not settings.OPENAI_API_KEY:
            raise STTError("OPENAI_API_KEY is not configured for Whisper.")
        
        # Initialize OpenAI client
        client = OpenAI(api_key=settings.OPENAI_API_KEY, timeout=30.0)
        
        # Call Whisper API
        transcript = await asyncio.to_thread(
            call_with_retries,
            "whisper_transcription",
            lambda: client.audio.transcriptions.create(
                model=model,
                file=audio_file,
                language=language if language != "en" else None,
            ),
        )
        
        text = transcript.text if hasattr(transcript, 'text') else str(transcript)
        detected_language = getattr(transcript, 'language', language) or language
        
        # Calculate word count
        word_count = len(text.split())
        
        # Whisper doesn't provide confidence scores directly
        # Using a heuristic based on text length and completeness
        confidence = min(0.95, 0.7 + (word_count / 100) * 0.25) if word_count > 0 else 0.5
        
        return {
            "transcript": text.strip(),
            "confidence": confidence,
            "language": detected_language,
            "provider": "whisper",
            "word_count": word_count
        }
    except Exception as e:
        logger.error(f"Whisper transcription failed: {e}")
        raise STTError(f"Whisper transcription failed: {e}") from e


def transcribe_whisper_sync(
    audio_file: BinaryIO,
    language: Optional[str] = "en",
    model: str = "whisper-1"
) -> dict:
    """Synchronous version of transcribe_whisper."""
    try:
        client = OpenAI(api_key=settings.OPENAI_API_KEY, timeout=30.0)
        audio_file.seek(0)
        transcript = client.audio.transcriptions.create(
            model=model,
            file=audio_file,
            language=language if language != "en" else None
        )
        
        text = transcript.text if hasattr(transcript, 'text') else str(transcript)
        detected_language = getattr(transcript, 'language', language) or language
        word_count = len(text.split())
        confidence = min(0.95, 0.7 + (word_count / 100) * 0.25) if word_count > 0 else 0.5
        
        return {
            "transcript": text.strip(),
            "confidence": confidence,
            "language": detected_language,
            "provider": "whisper",
            "word_count": word_count
        }
    except Exception as e:
        logger.error(f"Whisper transcription failed: {e}")
        raise

