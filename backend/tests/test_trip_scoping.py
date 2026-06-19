"""Per-trip scoping + chatbot grounding tests.

Validates that:
  • starting a trip back-tags existing in-window records,
  • new records resolve to the active trip,
  • starting a new trip completes the previous one,
  • a future-dated trip is not treated as "currently active",
  • build_trip_facts() computes correct per-trip totals / food subtotal /
    per-merchant breakdown (powers "expenses on the Kalam trip", "food at the
    hotel"),
  • detect_trips_in_query() resolves a place name in a chat message.
"""

from datetime import datetime, timezone, timedelta

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, Session

from backend.database import Base
from backend.models import trip as _trip  # noqa: F401  (register table)
from backend.models.expense import Expense
from backend.models.reminder import Reminder
from backend.schemas.trips import TripCreate
from backend.services import trip_service as ts
from backend.services import trip_chat as tc


@pytest.fixture()
def db() -> Session:
    engine = create_engine("sqlite://", connect_args={"check_same_thread": False})
    Base.metadata.create_all(bind=engine)
    session = sessionmaker(bind=engine)()
    try:
        yield session
    finally:
        session.close()


def _iso(dt):
    return dt.astimezone(timezone.utc).isoformat()


def test_trip_scoping_and_facts(db):
    U = "u1"
    now = datetime.now(timezone.utc)

    # Pre-existing expense before any trip → should back-tag into Kalam.
    db.add(Expense(amount=1200, category="food", description="dinner",
                   date=_iso(now - timedelta(days=2)), user_id=U,
                   created_at=_iso(now - timedelta(days=2)), merchant="PTDC Motel"))
    db.commit()

    kalam = ts.create_trip(db, TripCreate(destination="Kalam",
                                          start_date=_iso(now - timedelta(days=3))), U)
    assert kalam.status == "active"
    assert db.query(Expense).filter(Expense.trip_id == kalam.id).count() == 1

    # New expenses while Kalam active resolve to Kalam.
    for amt, cat, merch in [(800, "food", "Cafe Kalam"),
                            (5000, "accommodation", "Kalam Resort"),
                            (1500, "transport", None)]:
        tid = ts.resolve_trip_id_for_new_record(db, U, _iso(now))
        db.add(Expense(amount=amt, category=cat, description=f"{cat} spend",
                       date=_iso(now), user_id=U, created_at=_iso(now),
                       merchant=merch, trip_id=tid))
    db.commit()
    assert all(e.trip_id == kalam.id for e in db.query(Expense).all())

    # Future-dated Skardu trip → Kalam auto-completes; Skardu not active "now".
    skardu = ts.create_trip(db, TripCreate(destination="Skardu",
                                           start_date=_iso(now + timedelta(days=10))), U)
    db.refresh(kalam)
    assert kalam.status == "completed"
    assert ts.get_active_trip(db, U) is None

    db.add(Reminder(title="Book Shangrila", text="Book Shangrila",
                    datetime=_iso(now + timedelta(days=11)), user_id=U,
                    status="pending", created_at=_iso(now + timedelta(days=10)),
                    trip_id=skardu.id))
    db.commit()

    # "all expenses of the Kalam trip"
    assert any(t.id == kalam.id for t in tc.detect_trips_in_query(db, U, "expenses of the Kalam trip"))
    facts = tc.build_trip_facts(db, U, [kalam], "how much on food at the hotel on Kalam trip")
    assert "PKR 8,500" in facts            # 1200+800+5000+1500
    assert "Food subtotal on this trip: PKR 2,000" in facts  # 1200+800
    assert "Cafe Kalam" in facts and "PTDC Motel" in facts

    # "reminders in Skardu"
    assert any(t.id == skardu.id for t in tc.detect_trips_in_query(db, U, "my reminders in Skardu"))
    sfacts = tc.build_trip_facts(db, U, [skardu], "reminders in Skardu")
    assert "Book Shangrila" in sfacts
