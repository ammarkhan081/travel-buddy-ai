"""Opt-in live integration tests for external provider behavior.

These tests are skipped unless explicitly enabled to avoid API cost and flakiness in CI.
Enable with:
  RUN_LIVE_INTEGRATION_TESTS=true
and ensure OPENAI_API_KEY is configured.
"""

import os

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from backend.main import app
from backend.database import Base, get_db


pytestmark = pytest.mark.skipif(
    os.getenv("RUN_LIVE_INTEGRATION_TESTS", "false").strip().lower() not in {"1", "true", "yes", "on"},
    reason="Set RUN_LIVE_INTEGRATION_TESTS=true to run live integration tests.",
)


@pytest.fixture(scope="module")
def live_client():
    if not os.getenv("OPENAI_API_KEY", "").startswith("sk-"):
        pytest.skip("OPENAI_API_KEY is required for live integration tests")

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


def test_live_intent_classification_endpoint(live_client: TestClient):
    r = live_client.post("/api/intent/classify", json={"text": "Remind me tomorrow at 5 PM to call mom"})
    assert r.status_code == 200
    body = r.json()
    assert body["intent"] in {"reminder", "expense", "note", "query", "other"}


def test_live_chat_reply_endpoint(live_client: TestClient):
    payload = {
        "messages": [
            {"role": "user", "content": "Hello Travel Buddy, can you help me plan today?"}
        ]
    }
    r = live_client.post("/api/chat/reply", json=payload)
    assert r.status_code == 200
    body = r.json()
    assert isinstance(body.get("reply"), str)
    assert body["reply"].strip() != ""
