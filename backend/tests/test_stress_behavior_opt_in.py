"""Opt-in stress/concurrency behavior tests.

These tests are skipped unless explicitly enabled.
Enable with:
  RUN_STRESS_TESTS=true
"""

import os
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timedelta
from unittest.mock import AsyncMock, patch

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from backend.main import app
from backend.database import Base, get_db


pytestmark = pytest.mark.skipif(
    os.getenv("RUN_STRESS_TESTS", "false").strip().lower() not in {"1", "true", "yes", "on"},
    reason="Set RUN_STRESS_TESTS=true to run stress tests.",
)


@pytest.fixture(scope="module")
def stress_client():
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
    Base.metadata.create_all(bind=engine)

    def override_get_db():
        db = TestingSessionLocal()
        try:
            yield db
        finally:
            db.close()

    app.dependency_overrides[get_db] = override_get_db
    client = TestClient(app)
    try:
        yield client
    finally:
        app.dependency_overrides.pop(get_db, None)


def _post_voice(client: TestClient):
    files = {"file": ("voice.wav", b"fake-audio-bytes", "audio/wav")}
    return client.post("/api/intent/process-voice?persist=false", files=files)


def test_voice_pipeline_concurrent_requests(stress_client: TestClient):
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
                "confidence": 0.95,
                "priority": "medium",
            }
        ),
    ):
        total_requests = 24
        futures = []
        with ThreadPoolExecutor(max_workers=6) as ex:
            for _ in range(total_requests):
                futures.append(ex.submit(_post_voice, stress_client))

        statuses = []
        for fut in as_completed(futures):
            r = fut.result()
            statuses.append(r.status_code)
            if r.status_code == 200:
                body = r.json()
                assert body["intent"] == "reminder"

        assert len(statuses) == total_requests
        assert all(code == 200 for code in statuses)
