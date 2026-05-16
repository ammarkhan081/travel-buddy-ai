"""Deepgram API service for speech-to-text transcription (fallback)."""

import asyncio
import os
import logging
from typing import Optional, BinaryIO
from backend.utils.error_policy import STTError

logger = logging.getLogger(__name__)


async def transcribe_deepgram(
    audio_file: BinaryIO,
    language: Optional[str] = "en",
    api_key: Optional[str] = None
) -> dict:
    """
    Transcribe audio using Deepgram API (fallback).
    
    Args:
        audio_file: Audio file object (BinaryIO)
        language: Language code
        api_key: Deepgram API key
        
    Returns:
        dict with transcript, confidence, language, duration
    """
    try:
        try:
            from deepgram import DeepgramClient
        except Exception as import_err:
            raise STTError(f"Deepgram SDK unavailable or incompatible: {import_err}") from import_err

        import sys
        from pathlib import Path
        sys.path.append(str(Path(__file__).parent.parent.parent))
        from backend.config import settings
        
        api_key = api_key or settings.DEEPGRAM_API_KEY
        if not api_key:
            raise ValueError("Deepgram API key not provided")
        
        # Reset file pointer
        audio_file.seek(0)
        
        # Read audio data
        audio_data = audio_file.read()
        
        # Initialize Deepgram client
        client = DeepgramClient(api_key)
        
        # Configure options as plain dict for broader SDK compatibility.
        options = {
            "model": "nova-2",
            "language": language,
            "punctuate": True,
            "diarize": False,
            "smart_format": True,
        }
        
        # Create file source
        payload = {
            "buffer": audio_data,
        }
        
        # Transcribe
        # Fixed for SDK v3.x: use prerecorded instead of rest
        response = await asyncio.to_thread(
            client.listen.prerecorded.v("1").transcribe_file,
            payload,
            options,
        )
        
        # Extract results
        if response.results and response.results.channels:
            channel = response.results.channels[0]
            if channel.alternatives:
                alternative = channel.alternatives[0]
                text = alternative.transcript
                confidence = alternative.confidence if hasattr(alternative, 'confidence') else 0.9
                
                # Get metadata
                metadata = response.metadata
                duration = metadata.duration if hasattr(metadata, 'duration') else None
                
                word_count = len(text.split())
                
                return {
                    "transcript": text.strip(),
                    "confidence": confidence,
                    "language": language,
                    "provider": "deepgram",
                    "duration": duration,
                    "word_count": word_count
                }
        
        raise ValueError("No transcription results from Deepgram")
        
    except ImportError:
        logger.warning("Deepgram SDK not installed. Install with: pip install deepgram-sdk")
        raise
    except Exception as e:
        logger.error(f"Deepgram transcription failed: {e}")
        raise STTError(f"Deepgram transcription failed: {e}") from e
