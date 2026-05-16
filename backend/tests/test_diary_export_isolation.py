from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from backend.database import Base
from backend.models.diary_entry import DiaryEntry
from backend.services import diary_service


def test_export_diary_scopes_entries_to_user(monkeypatch):
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(bind=engine)
    Session = sessionmaker(autocommit=False, autoflush=False, bind=engine)
    db = Session()
    try:
        db.add_all(
            [
                DiaryEntry(
                    user_id="user_a",
                    title="A1",
                    content="alpha",
                    location=None,
                    timestamp="2026-03-09T01:00:00+00:00",
                    is_auto_generated=False,
                ),
                DiaryEntry(
                    user_id="user_b",
                    title="B1",
                    content="beta",
                    location=None,
                    timestamp="2026-03-09T02:00:00+00:00",
                    is_auto_generated=False,
                ),
            ]
        )
        db.commit()

        seen = {"titles": []}

        def _fake_export_pdf(entries, user_id=None):
            seen["titles"] = [e.title for e in entries]
            return "dummy.pdf"

        monkeypatch.setattr(diary_service, "_export_pdf", _fake_export_pdf)
        path = diary_service.export_diary(db, "pdf", user_id="user_a")

        assert path == "dummy.pdf"
        assert seen["titles"] == ["A1"]
    finally:
        db.close()
        Base.metadata.drop_all(bind=engine)

