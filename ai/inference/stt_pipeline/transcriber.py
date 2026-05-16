"""Main transcriber service with fallback logic."""

import logging
from typing import Optional, BinaryIO
from .whisper_service import transcribe_whisper
from .deepgram_service import transcribe_deepgram
from backend.utils.transcript_utils import clean_transcript, normalize_for_nlp
from backend.utils.error_policy import STTError

logger = logging.getLogger(__name__)


def normalize_transcript(text: str) -> str:
    return clean_transcript(text)


async def transcribe_audio(
    audio_file: BinaryIO,
    language: Optional[str] = "en",
    use_fallback: bool = True
) -> dict:
    """
    Transcribe audio with automatic fallback.
    
    Args:
        audio_file: Audio file object
        language: Language code
        use_fallback: Whether to use Deepgram if Whisper fails
        
    Returns:
        dict with transcription results
    """
    # Try Whisper first (primary)
    try:
        result = await transcribe_whisper(audio_file, language)
        result["transcript"] = normalize_transcript(result.get("transcript", ""))
        result["normalized_for_nlp"] = normalize_for_nlp(result.get("transcript", ""))
        logger.info(f"Transcription successful using Whisper")
        return result
    except Exception as e:
        logger.warning(f"Whisper transcription failed: {e}")
        
        if use_fallback:
            # Try Deepgram as fallback
            try:
                result = await transcribe_deepgram(audio_file, language)
                result["transcript"] = normalize_transcript(result.get("transcript", ""))
                result["normalized_for_nlp"] = normalize_for_nlp(result.get("transcript", ""))
                logger.info(f"Transcription successful using Deepgram (fallback)")
                return result
            except Exception as e2:
                logger.error(f"Deepgram transcription also failed: {e2}")
                raise STTError(f"Both transcription services failed. Whisper: {e}, Deepgram: {e2}") from e2
        else:
            raise STTError(f"Whisper transcription failed and fallback disabled: {e}") from e

