"""Tests for speech-to-text functionality."""

import pytest
from unittest.mock import Mock, patch, AsyncMock
import io


@pytest.mark.asyncio
async def test_whisper_transcription():
    """Test Whisper API transcription."""
    from ai.inference.stt_pipeline.whisper_service import transcribe_whisper
    
    # Mock audio file
    audio_file = io.BytesIO(b"fake audio data")
    
    # Mock OpenAI response
    from unittest.mock import MagicMock
    mock_transcript = MagicMock()
    mock_transcript.text = "This is a test transcription"
    mock_transcript.language = "en"
    
    with patch('ai.inference.stt_pipeline.whisper_service.OpenAI') as mock_openai:
        mock_client = MagicMock()
        mock_client.audio.transcriptions.create.return_value = mock_transcript
        mock_openai.return_value = mock_client
        result = await transcribe_whisper(audio_file, language="en")
        
        assert result["transcript"] == "This is a test transcription"
        assert result["language"] == "en"
        assert result["provider"] == "whisper"
        assert "confidence" in result
        assert result["word_count"] > 0


@pytest.mark.asyncio
async def test_transcriber_fallback():
    """Test transcription with fallback to Deepgram."""
    from ai.inference.stt_pipeline.transcriber import transcribe_audio
    
    audio_file = io.BytesIO(b"fake audio data")
    
    # Mock Whisper failure, Deepgram success
    with patch('ai.inference.stt_pipeline.transcriber.transcribe_whisper', side_effect=Exception("Whisper failed")):
        with patch('ai.inference.stt_pipeline.transcriber.transcribe_deepgram', return_value={
            "transcript": "Deepgram transcription",
            "confidence": 0.9,
            "language": "en",
            "provider": "deepgram",
            "word_count": 2
        }):
            result = await transcribe_audio(audio_file, language="en", use_fallback=True)
            
            assert result["provider"] == "deepgram"
            assert result["transcript"] == "Deepgram transcription"


def test_transcription_endpoint():
    """Test STT API endpoint."""
    from fastapi.testclient import TestClient
    from backend.main import app
    
    client = TestClient(app)
    
    # Mock transcription service
    with patch('backend.services.voice_notes_service.transcribe_and_save', new_callable=AsyncMock) as mock_transcribe:
        mock_transcribe.return_value = {
            "id": 1,
            "transcript": "Test transcript",
            "keywords": "Test, transcript",
            "timestamp": "2026-03-03T10:00:00"
        }
        
        # Create a fake audio file
        audio_data = b"fake audio content"
        files = {"file": ("test.wav", audio_data, "audio/wav")}
        data = {
            "user_id": "test_user",
            "language": "en",
            "use_fallback": False
        }
        
        response = client.post("/api/voice-notes/transcribe", files=files, data=data)
        
        assert response.status_code == 200
        assert response.json()["transcript"] == "Test transcript"

