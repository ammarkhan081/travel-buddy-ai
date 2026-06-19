"""Schemas for speech-to-text API."""

from pydantic import BaseModel, Field
from typing import Optional
from datetime import datetime


class TranscriptionRequest(BaseModel):
    """Schema for transcription request."""
    user_id: str = Field(..., description="User ID")
    language: Optional[str] = Field("en", description="Language code (ISO 639-1)")
    use_fallback: Optional[bool] = Field(False, description="Use Deepgram as fallback if Whisper fails")


class TranscriptionResponse(BaseModel):
    """Schema for transcription response."""
    transcript: str = Field(..., description="Transcribed text")
    timestamp: str = Field(..., description="ISO timestamp")
    keywords: Optional[str] = Field(None, description="Extracted keywords")


class VoiceNoteResponse(BaseModel):
    """Schema for a single voice note."""
    id: int
    transcript: str
    keywords: Optional[str] = None
    timestamp: str
    trip_id: Optional[int] = None
    location: Optional[str] = None

    class Config:
        from_attributes = True


class VoiceNoteCreateFromTextRequest(BaseModel):
    """Schema to save an already-transcribed note without re-running STT."""
    transcript: str = Field(..., description="Transcribed text")
    keywords: Optional[str] = Field(None, description="Optional comma-separated keywords")
