"""
Ownership enforcement unit tests for reminder and diary service functions.

Tests the service layer directly (no HTTP stack, no startup event conflicts).
An isolated in-memory SQLAlchemy session is used per test class.

Ownership contract:
- delete_reminder(db, id, uid)  → True only if record.user_id == uid
- update_reminder(db, id, upd, uid) → record only if record.user_id == uid
- delete_entry(db, id, uid)     → True only if record.user_id == uid
- update_entry(db, id, upd, uid)→ record only if record.user_id == uid
"""

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, Session

from backend.database import Base
from backend.models.reminder import Reminder
from backend.models.diary_entry import DiaryEntry
from backend.schemas.reminders import ReminderUpdate
from backend.schemas.diary import DiaryUpdateRequest
from backend.services import reminder_service, diary_service
from backend.utils.time_utils import now_utc_iso


# ── shared fixture ────────────────────────────────────────────────────────────

@pytest.fixture()
def db() -> Session:
    """Fresh in-memory SQLite session per test."""
    engine = create_engine(
        "sqlite:///:memory:", connect_args={"check_same_thread": False}
    )
    Base.metadata.create_all(bind=engine)
    TestingSession = sessionmaker(autocommit=False, autoflush=False, bind=engine)
    session = TestingSession()
    try:
        yield session
    finally:
        session.close()
    Base.metadata.drop_all(bind=engine)


# ── seed helpers ──────────────────────────────────────────────────────────────

def _make_reminder(db: Session, owner_uid: str) -> int:
    r = Reminder(
        title="Test Reminder",
        text="Test Reminder",
        datetime=now_utc_iso(),
        user_id=owner_uid,
        intent="manual",
        status="pending",
        priority="medium",
        created_at=now_utc_iso(),
    )
    db.add(r)
    db.commit()
    db.refresh(r)
    return r.id


def _make_diary_entry(db: Session, owner_uid: str) -> int:
    e = DiaryEntry(
        user_id=owner_uid,
        title="Test Entry",
        content="Test content.",
        location=None,
        timestamp=now_utc_iso(),
        is_auto_generated=False,
    )
    db.add(e)
    db.commit()
    db.refresh(e)
    return e.id


# ── Reminder ownership ────────────────────────────────────────────────────────

class TestReminderServiceOwnership:
    """reminder_service.delete_reminder / update_reminder enforce user ownership."""

    # ── delete ──────────────────────────────────────────────────────────────

    def test_owner_can_delete_own_reminder(self, db):
        rid = _make_reminder(db, owner_uid="alice")
        result = reminder_service.delete_reminder(db, rid, user_id="alice")
        assert result is True

    def test_other_user_cannot_delete_reminder(self, db):
        rid = _make_reminder(db, owner_uid="alice")
        result = reminder_service.delete_reminder(db, rid, user_id="bob")
        assert result is False, "delete should be rejected for non-owner"

    def test_record_survives_cross_user_delete_attempt(self, db):
        """After a failed cross-user delete the record must still exist."""
        rid = _make_reminder(db, owner_uid="alice")
        reminder_service.delete_reminder(db, rid, user_id="bob")
        still_exists = db.query(Reminder).filter(Reminder.id == rid).first()
        assert still_exists is not None

    def test_nonexistent_reminder_delete_returns_false(self, db):
        result = reminder_service.delete_reminder(db, 99999, user_id="alice")
        assert result is False

    # ── update ──────────────────────────────────────────────────────────────

    def test_owner_can_update_own_reminder(self, db):
        rid = _make_reminder(db, owner_uid="alice")
        upd = ReminderUpdate(status="completed")
        result = reminder_service.update_reminder(db, rid, upd, user_id="alice")
        assert result is not None
        assert result.status == "completed"

    def test_other_user_cannot_update_reminder(self, db):
        rid = _make_reminder(db, owner_uid="alice")
        upd = ReminderUpdate(status="completed")
        result = reminder_service.update_reminder(db, rid, upd, user_id="bob")
        assert result is None, "update should return None for non-owner"

    def test_record_unchanged_after_cross_user_update_attempt(self, db):
        """Original status must remain 'pending' after failed cross-user update."""
        rid = _make_reminder(db, owner_uid="alice")
        reminder_service.update_reminder(
            db, rid, ReminderUpdate(status="completed"), user_id="bob"
        )
        reminder = db.query(Reminder).filter(Reminder.id == rid).first()
        assert reminder.status == "pending"

    def test_nonexistent_reminder_update_returns_none(self, db):
        result = reminder_service.update_reminder(
            db, 99999, ReminderUpdate(status="completed"), user_id="alice"
        )
        assert result is None


# ── Diary entry ownership ─────────────────────────────────────────────────────

class TestDiaryServiceOwnership:
    """diary_service.delete_entry / update_entry enforce user ownership."""

    # ── delete ──────────────────────────────────────────────────────────────

    def test_owner_can_delete_own_entry(self, db):
        eid = _make_diary_entry(db, owner_uid="alice")
        result = diary_service.delete_entry(db, eid, user_id="alice")
        assert result is True

    def test_other_user_cannot_delete_diary_entry(self, db):
        eid = _make_diary_entry(db, owner_uid="alice")
        result = diary_service.delete_entry(db, eid, user_id="bob")
        assert result is False, "delete should be rejected for non-owner"

    def test_record_survives_cross_user_delete_attempt(self, db):
        eid = _make_diary_entry(db, owner_uid="alice")
        diary_service.delete_entry(db, eid, user_id="bob")
        still_exists = db.query(DiaryEntry).filter(DiaryEntry.id == eid).first()
        assert still_exists is not None

    def test_nonexistent_diary_entry_delete_returns_false(self, db):
        result = diary_service.delete_entry(db, 99999, user_id="alice")
        assert result is False

    # ── update ──────────────────────────────────────────────────────────────

    def test_owner_can_update_own_entry(self, db):
        eid = _make_diary_entry(db, owner_uid="alice")
        upd = DiaryUpdateRequest(content="New content.", title=None, location=None)
        result = diary_service.update_entry(db, eid, upd, user_id="alice")
        assert result is not None
        assert result.content == "New content."

    def test_other_user_cannot_update_diary_entry(self, db):
        eid = _make_diary_entry(db, owner_uid="alice")
        upd = DiaryUpdateRequest(content="Hacked.", title=None, location=None)
        result = diary_service.update_entry(db, eid, upd, user_id="bob")
        assert result is None, "update should return None for non-owner"

    def test_record_unchanged_after_cross_user_update_attempt(self, db):
        eid = _make_diary_entry(db, owner_uid="alice")
        diary_service.update_entry(
            db, eid, DiaryUpdateRequest(content="Hacked.", title=None, location=None),
            user_id="bob",
        )
        entry = db.query(DiaryEntry).filter(DiaryEntry.id == eid).first()
        assert entry.content == "Test content."

    def test_nonexistent_diary_entry_update_returns_none(self, db):
        result = diary_service.update_entry(
            db, 99999,
            DiaryUpdateRequest(content="x", title=None, location=None),
            user_id="alice",
        )
        assert result is None
