"""Tests for intent detection functionality."""

import pytest
from unittest.mock import patch, AsyncMock, Mock, MagicMock


@pytest.mark.asyncio
async def test_intent_detection_gpt():
    """Test GPT-based intent detection."""
    from ai.inference.nlp_pipeline.intent_detector import detect_intent_gpt
    
    mock_response = MagicMock()
    mock_response.choices = [MagicMock(message=MagicMock(
        content='{"intent": "reminder", "scheduled_time": "2024-01-15T10:00:00", "location": "Paris", "priority": "high", "confidence": 0.9, "entities": {}}'
    ))]
    
    with patch('openai.OpenAI') as mock_openai:
        mock_client = Mock()
        mock_client.chat.completions.create.return_value = mock_response
        mock_openai.return_value = mock_client
        
        result = await detect_intent_gpt("Remind me to visit the Eiffel Tower tomorrow at 10 AM in Paris")
        
        assert result["intent"] == "reminder"
        assert result["location"] == "Paris"
        assert result["priority"] == "high"


def test_intent_detection_spacy():
    """Test spaCy fallback intent detection."""
    from ai.inference.nlp_pipeline.intent_detector import detect_intent_spacy
    
    result = detect_intent_spacy("Remind me to buy groceries tomorrow")
    
    assert "intent" in result
    assert "scheduled_time" in result
    assert "location" in result


def test_reminder_creation():
    """Test reminder creation with intent detection."""
    from fastapi.testclient import TestClient
    from backend.main import app
    
    client = TestClient(app)
    
    with patch('backend.services.reminder_service.create_reminder', new_callable=AsyncMock) as mock_create:
        from datetime import datetime
        mock_create.return_value = {
            "id": 1,
            "title": "Call mom",
            "datetime": "2026-03-04T10:00:00",
            "user_id": "test_user",
            "intent": "reminder",
            "transcript": None,
            "location": None,
            "priority": "medium",
            "created_at": datetime.now().isoformat(),
            "status": "pending"
        }
        
        response = client.post(
            "/api/reminders/",
            json={
                "title": "Call mom",
                "datetime": "2024-01-15T10:00:00",
                "user_id": "test_user"
            }
        )
        
        assert response.status_code == 200
        assert response.json()["intent"] == "reminder"

