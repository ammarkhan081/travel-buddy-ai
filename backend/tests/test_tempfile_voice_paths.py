"""Regression tests for temp-file handling in voice processing services."""

import asyncio
import io
import sys
from types import SimpleNamespace

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from backend.database import Base


def _stub_deepgram_module(monkeypatch):
    """Provide minimal deepgram symbols expected by deepgram_service imports."""
    fake = SimpleNamespace(
        DeepgramClient=object,
        PrerecordedOptions=object,
        FileSource=dict,
    )
    monkeypatch.setitem(sys.modules, "deepgram", fake)


def test_extract_expense_from_voice_uses_open_tempfile(monkeypatch):
    """Whisper upload must receive an open temp file handle."""

    _stub_deepgram_module(monkeypatch)
    from backend.services import expense_service

    monkeypatch.setattr(expense_service.settings, "OPENAI_API_KEY", "sk-test")
    monkeypatch.setattr(expense_service.settings, "WHISPER_MODEL", "whisper-1")

    class _FakeTranscriptions:
        @staticmethod
        def create(*, model, file):
            # This read raises ValueError if file is already closed.
            file.seek(0)
            _ = file.read(1)
            return SimpleNamespace(text="spent 20 dollars on lunch")

    class _FakeClient:
        def __init__(self):
            self.audio = SimpleNamespace(transcriptions=_FakeTranscriptions())

    monkeypatch.setattr(expense_service, "OpenAI", lambda api_key, timeout: _FakeClient())
    monkeypatch.setattr(expense_service, "call_with_retries", lambda _label, fn: fn())

    async def _fake_extract(_text):
        return {
            "amount": 20.0,
            "currency": "USD",
            "category": "food",
            "description": "lunch",
            "location": None,
            "confidence": 0.9,
        }

    monkeypatch.setattr(expense_service, "extract_expense_gpt", _fake_extract)

    audio_file = io.BytesIO(b"fake-audio-bytes")
    out = asyncio.run(expense_service.extract_expense_from_voice(audio_file))
    assert out["amount"] == 20.0
    assert out["category"] == "food"


def test_transcribe_and_save_uses_open_tempfile(monkeypatch):
    """Voice-note transcribe path must call STT while temp file is open."""

    _stub_deepgram_module(monkeypatch)
    from backend.services import voice_notes_service

    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Session = sessionmaker(autocommit=False, autoflush=False, bind=engine)
    Base.metadata.create_all(bind=engine)
    db = Session()

    async def _fake_transcribe(file_obj, use_fallback=True):
        # This read raises ValueError if file is already closed.
        file_obj.seek(0)
        _ = file_obj.read(1)
        return {"transcript": "hello from stt"}

    try:
        monkeypatch.setattr(voice_notes_service, "transcribe_audio", _fake_transcribe)
        monkeypatch.setattr(voice_notes_service, "extract_keywords", lambda _t: "hello, stt")

        audio_file = io.BytesIO(b"fake-audio-bytes")
        note = asyncio.run(voice_notes_service.transcribe_and_save(db, audio_file, "user_test"))

        assert note.transcript == "hello from stt"
        assert note.user_id == "user_test"
    finally:
        db.close()
        Base.metadata.drop_all(bind=engine)
