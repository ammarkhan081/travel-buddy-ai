"""End-to-end reliability tests for unified voice pipeline."""

import io
from datetime import datetime, timedelta
from unittest.mock import AsyncMock, patch

from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from backend.main import app
from backend.database import Base, get_db


# In-memory SQLite shared across sessions for deterministic tests.
TEST_ENGINE = create_engine(
    "sqlite://",
    connect_args={"check_same_thread": False},
    poolclass=StaticPool,
)
TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=TEST_ENGINE)
Base.metadata.create_all(bind=TEST_ENGINE)


def override_get_db():
    db = TestingSessionLocal()
    try:
        yield db
    finally:
        db.close()


app.dependency_overrides[get_db] = override_get_db
client = TestClient(app)


def _post_voice():
    files = {"file": ("voice.wav", b"fake-audio-bytes", "audio/wav")}
    return client.post("/api/intent/process-voice?user_id=test_user", files=files)


def test_pipeline_branch_reminder_create():
    with patch(
        "backend.services.intent_orchestrator_service.transcribe_audio",
        new=AsyncMock(return_value={"transcript": "Remind me tomorrow at 5 PM to call mom"}),
    ), patch(
        "backend.services.intent_orchestrator_service.detect_intent_gpt",
        new=AsyncMock(
            return_value={
                "intent": "reminder",
                "title": "Call mom",
                "scheduled_time": datetime.now() + timedelta(days=1),
                "location": None,
                "priority": "medium",
                "confidence": 0.92,
            }
        ),
    ):
        response = _post_voice()
        assert response.status_code == 200
        body = response.json()
        assert body["intent"] == "reminder"
        assert body["action"] == "reminder_created"
        assert body["record_id"] is not None
        assert body["requires_review"] is False


def test_pipeline_branch_expense_create():
    with patch(
        "backend.services.intent_orchestrator_service.transcribe_audio",
        new=AsyncMock(return_value={"transcript": "I spent 20 dollars on lunch and 10 on coffee"}),
    ), patch(
        "backend.services.intent_orchestrator_service.detect_intent_gpt",
        new=AsyncMock(
            return_value={
                "intent": "expense",
                "confidence": 0.9,
            }
        ),
    ), patch(
        "backend.services.intent_orchestrator_service.extract_expense_gpt",
        new=AsyncMock(
            return_value={
                "amount": 30.0,
                "currency": "USD",
                "category": "food",
                "description": "Lunch and coffee",
                "confidence": 0.88,
            }
        ),
    ):
        response = _post_voice()
        assert response.status_code == 200
        body = response.json()
        assert body["intent"] == "expense"
        assert body["action"] == "expense_created"
        assert body["record_id"] is not None
        assert body["requires_review"] is False


def test_pipeline_branch_knowledge_fallback_on_empty_transcript():
    with patch(
        "backend.services.intent_orchestrator_service.transcribe_audio",
        new=AsyncMock(return_value={"transcript": ""}),
    ):
        response = _post_voice()
        assert response.status_code == 200
        body = response.json()
        assert body["action"] == "none"
        assert body["requires_review"] is True
        assert body["details"]["error"] == "empty_transcript"
