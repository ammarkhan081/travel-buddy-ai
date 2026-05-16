"""Auth enforcement integration tests for protected API routes."""

from fastapi.testclient import TestClient

from backend.main import app


def test_health_public_without_auth(monkeypatch):
    """Public health endpoint should remain accessible."""
    monkeypatch.setenv("AUTH_BYPASS", "false")
    client = TestClient(app)
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json().get("status") == "healthy"


def test_protected_route_rejects_without_bearer_token(monkeypatch):
    """Protected endpoints must reject requests with no Authorization header."""
    monkeypatch.setenv("AUTH_BYPASS", "false")
    client = TestClient(app)
    r = client.get("/api/reminders/")
    assert r.status_code == 401
    assert "Authorization" in r.json().get("detail", "")


def test_protected_route_rejects_invalid_bearer_token(monkeypatch):
    """Protected endpoints must reject malformed/invalid bearer tokens."""
    monkeypatch.setenv("AUTH_BYPASS", "false")
    client = TestClient(app)
    r = client.get("/api/expenses/", headers={"Authorization": "Bearer invalid-token"})
    # 401 when Firebase is configured and token verification runs;
    # 503 when auth is enabled but Firebase Admin credentials are not configured in test env.
    assert r.status_code in (401, 503)


def test_protected_route_allows_bypass_mode_for_tests(monkeypatch):
    """Test-only bypass mode should keep existing test suite deterministic."""
    monkeypatch.setenv("AUTH_BYPASS", "true")
    client = TestClient(app)
    r = client.get("/api/voice-notes/")
    # Can be 200 with empty list or 500 only if unrelated runtime error.
    assert r.status_code == 200
    assert isinstance(r.json(), list)
