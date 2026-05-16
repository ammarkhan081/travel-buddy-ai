"""Pytest configuration and fixtures."""

import pytest
import os
import tempfile
import sqlite3

# Keep API auth enabled in app code while allowing tests to run deterministically.
os.environ.setdefault("AUTH_BYPASS", "true")
os.environ.setdefault("AUTH_BYPASS_UID", "test_user")


@pytest.fixture
def test_db():
    """Create a temporary test database."""
    db_fd, db_path = tempfile.mkstemp(suffix='.db')
    os.environ['DB_PATH'] = db_path
    
    # Initialize test database
    conn = sqlite3.connect(db_path)
    conn.execute("""
        CREATE TABLE IF NOT EXISTS reminders (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id TEXT NOT NULL,
            text TEXT NOT NULL,
            intent TEXT,
            scheduled_time DATETIME,
            location TEXT,
            priority TEXT DEFAULT 'medium',
            status TEXT DEFAULT 'pending',
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP
        )
    """)
    conn.commit()
    conn.close()
    
    yield db_path
    
    # Cleanup
    os.close(db_fd)
    os.unlink(db_path)
    if 'DB_PATH' in os.environ:
        del os.environ['DB_PATH']


@pytest.fixture
def mock_openai_key(monkeypatch):
    """Mock OpenAI API key."""
    monkeypatch.setenv("OPENAI_API_KEY", "test-key")


@pytest.fixture
def mock_firebase(monkeypatch):
    """Mock Firebase initialization."""
    monkeypatch.setenv("FIREBASE_CREDENTIALS_PATH", "")

