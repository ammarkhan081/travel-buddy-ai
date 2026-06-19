"""Trip service: lifecycle, active-trip resolution, and auto tagging.

This is the engine that makes per-trip questions possible. It:

* creates/updates/completes trips (any destination, free text),
* keeps the "one active trip per user" invariant,
* resolves which trip a new record (expense/reminder/note/diary) belongs to,
* back-tags existing untagged records into a trip by date window, so historical
  data is grouped without the client having to do anything,
* resolves a place name mentioned in chat ("Kalam") to the matching trip(s).

All datetimes are compared as real UTC datetimes (not strings) for correctness.
"""

import logging
from datetime import datetime, timezone
from typing import List, Optional

from sqlalchemy.orm import Session

try:
    from ..models.trip import Trip
    from ..models.expense import Expense
    from ..models.reminder import Reminder
    from ..models.voice_note import VoiceNote
    from ..models.diary_entry import DiaryEntry
    from ..schemas.trips import TripCreate, TripUpdate
    from ..utils.time_utils import now_utc_iso, parse_utc_datetime
except ImportError:
    from models.trip import Trip
    from models.expense import Expense
    from models.reminder import Reminder
    from models.voice_note import VoiceNote
    from models.diary_entry import DiaryEntry
    from schemas.trips import TripCreate, TripUpdate
    from utils.time_utils import now_utc_iso, parse_utc_datetime

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def _dt(value) -> Optional[datetime]:
    """Best-effort parse of any stored ISO string / datetime to UTC datetime."""
    try:
        return parse_utc_datetime(value)
    except Exception:
        return None


def _within(record_dt: Optional[datetime], start: Optional[datetime], end: Optional[datetime]) -> bool:
    """True if record_dt falls inside [start, end]. end=None means "ongoing"."""
    if record_dt is None or start is None:
        return False
    if record_dt < start:
        return False
    if end is not None and record_dt > end:
        return False
    return True


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------
def get_trips_for_user(db: Session, user_id: str) -> List[Trip]:
    return (
        db.query(Trip)
        .filter(Trip.user_id == user_id)
        .order_by(Trip.start_date.desc())
        .all()
    )


def get_trip(db: Session, trip_id: int, user_id: str) -> Optional[Trip]:
    return (
        db.query(Trip)
        .filter(Trip.id == trip_id, Trip.user_id == user_id)
        .first()
    )


def get_active_trip(db: Session, user_id: str) -> Optional[Trip]:
    """The user's currently active trip — started but not yet ended.

    A future-dated booked trip (start_date in the future) is *not* returned as
    "active now"; it only becomes active once its start date arrives.
    """
    now = datetime.now(timezone.utc)
    candidates = (
        db.query(Trip)
        .filter(Trip.user_id == user_id, Trip.status == "active")
        .order_by(Trip.start_date.desc())
        .all()
    )
    started = [t for t in candidates if (_dt(t.start_date) or now) <= now]
    if started:
        # Most recently started trip that is currently underway.
        return started[0]
    return None


def create_trip_for_booking(db: Session, user_id: str, booking) -> Trip:
    """Create (or reuse) a Trip for a booking and link them.

    Does NOT close other active trips — a booking is often for a future trip and
    should not disturb a journey that is currently underway.
    """
    now = now_utc_iso()
    end = getattr(booking, "return_date", None) or None
    start = getattr(booking, "travel_date", None) or now

    # Decide status from the booking window.
    end_dt = _dt(end)
    status = "completed" if (end_dt is not None and end_dt < datetime.now(timezone.utc)) else "active"

    trip = Trip(
        user_id=user_id,
        destination=(getattr(booking, "destination_name", None) or "Trip").strip(),
        origin=None,
        start_date=start,
        end_date=end,
        status=status,
        transport=None,
        notes=f"Booked with {getattr(booking, 'agency_name', '')}".strip(),
        booking_id=getattr(booking, "id", None),
        created_at=now,
        updated_at=now,
    )
    db.add(trip)
    db.commit()
    db.refresh(trip)
    try:
        booking.trip_id = trip.id
        db.commit()
    except Exception:
        db.rollback()
    try:
        backfill_trip_records(db, trip)
    except Exception:
        pass
    return trip


def create_trip(db: Session, data: TripCreate, user_id: str) -> Trip:
    """Start (or record) a trip.

    Starting a new *active* trip completes any previously-active trip so the
    "one active trip" invariant holds. After creation, existing untagged records
    inside the trip window are back-tagged to this trip.
    """
    now = now_utc_iso()
    start = data.start_date or now
    is_active = data.end_date is None

    if is_active:
        # Close any prior active trips so only one trip is active at a time.
        prior = (
            db.query(Trip)
            .filter(Trip.user_id == user_id, Trip.status == "active")
            .all()
        )
        for t in prior:
            t.status = "completed"
            if not t.end_date:
                t.end_date = now
            t.updated_at = now

    trip = Trip(
        user_id=user_id,
        destination=data.destination.strip(),
        origin=(data.origin or None),
        start_date=start,
        end_date=data.end_date,
        status="completed" if data.end_date else "active",
        transport=data.transport,
        notes=data.notes,
        booking_id=data.booking_id,
        created_at=now,
        updated_at=now,
    )
    db.add(trip)
    db.commit()
    db.refresh(trip)

    # Group any matching existing records into this trip.
    try:
        backfill_trip_records(db, trip)
    except Exception as e:
        logger.warning("trip_backfill_failed", extra={"error": str(e)})
    return trip


def update_trip(db: Session, trip_id: int, data: TripUpdate, user_id: str) -> Optional[Trip]:
    trip = get_trip(db, trip_id, user_id)
    if not trip:
        return None
    for field in ("destination", "origin", "start_date", "end_date", "transport", "notes"):
        value = getattr(data, field, None)
        if value is not None:
            setattr(trip, field, value)
    trip.updated_at = now_utc_iso()
    db.commit()
    db.refresh(trip)
    try:
        backfill_trip_records(db, trip)
    except Exception:
        pass
    return trip


def set_trip_status(db: Session, trip_id: int, user_id: str, status: str, end_date: Optional[str] = None) -> Optional[Trip]:
    trip = get_trip(db, trip_id, user_id)
    if not trip:
        return None
    now = now_utc_iso()
    trip.status = status
    if status in {"completed", "cancelled"} and not trip.end_date:
        trip.end_date = end_date or now
    trip.updated_at = now
    db.commit()
    db.refresh(trip)
    if status == "completed":
        try:
            backfill_trip_records(db, trip)
        except Exception:
            pass
    return trip


def delete_trip(db: Session, trip_id: int, user_id: str) -> bool:
    """Delete the trip but keep its records (just untag them)."""
    trip = get_trip(db, trip_id, user_id)
    if not trip:
        return False
    for model in (Expense, Reminder, VoiceNote, DiaryEntry):
        db.query(model).filter(model.user_id == user_id, model.trip_id == trip.id).update(
            {"trip_id": None}, synchronize_session=False
        )
    db.delete(trip)
    db.commit()
    return True


# ---------------------------------------------------------------------------
# Tagging
# ---------------------------------------------------------------------------
def resolve_trip_id_for_new_record(db: Session, user_id: str, record_dt_iso: Optional[str] = None) -> Optional[int]:
    """Return the trip_id a newly created record should be stamped with.

    Strategy:
      1. If the user has an active trip whose window covers the record time
         (or the active trip is open-ended), use it.
      2. Otherwise find any trip whose [start, end] window contains the record
         time and use the most recent one.
      3. Otherwise return None (record is unscoped).
    """
    rec_dt = _dt(record_dt_iso) or datetime.now(timezone.utc)

    active = get_active_trip(db, user_id)
    if active:
        start = _dt(active.start_date)
        end = _dt(active.end_date)  # None while ongoing
        if _within(rec_dt, start, end) or (end is None and start is not None and rec_dt >= start):
            return active.id

    # Fall back to any historical trip window that contains the record time.
    for trip in get_trips_for_user(db, user_id):
        if _within(rec_dt, _dt(trip.start_date), _dt(trip.end_date)):
            return trip.id
    return None


def backfill_trip_records(db: Session, trip: Trip) -> int:
    """Tag untagged records that fall within this trip's window.

    Records that are already tagged to another trip are left untouched.
    Returns the number of records newly tagged.
    """
    start = _dt(trip.start_date)
    end = _dt(trip.end_date)
    if start is None:
        return 0

    tagged = 0
    user_id = trip.user_id

    # Expenses — use the spend date.
    for e in db.query(Expense).filter(Expense.user_id == user_id, Expense.trip_id.is_(None)).all():
        if _within(_dt(e.date) or _dt(e.created_at), start, end):
            e.trip_id = trip.id
            tagged += 1

    # Reminders — use creation time (when it was recorded during the trip).
    for r in db.query(Reminder).filter(Reminder.user_id == user_id, Reminder.trip_id.is_(None)).all():
        if _within(_dt(r.created_at) or _dt(r.datetime), start, end):
            r.trip_id = trip.id
            tagged += 1

    # Voice notes — creation/timestamp.
    for v in db.query(VoiceNote).filter(VoiceNote.user_id == user_id, VoiceNote.trip_id.is_(None)).all():
        if _within(_dt(v.created_at) or _dt(v.timestamp), start, end):
            v.trip_id = trip.id
            tagged += 1

    # Diary entries — timestamp.
    for d in db.query(DiaryEntry).filter(DiaryEntry.user_id == user_id, DiaryEntry.trip_id.is_(None)).all():
        if _within(_dt(d.timestamp), start, end):
            d.trip_id = trip.id
            tagged += 1

    if tagged:
        db.commit()
    return tagged


# ---------------------------------------------------------------------------
# Name resolution (for chat: "expenses on the Kalam trip")
# ---------------------------------------------------------------------------
def find_trips_by_name(db: Session, user_id: str, name: str) -> List[Trip]:
    """Return trips whose destination matches the given place name (case-insensitive substring)."""
    if not name:
        return []
    needle = name.strip().lower()
    out = []
    for trip in get_trips_for_user(db, user_id):
        dest = (trip.destination or "").lower()
        if needle in dest or dest in needle:
            out.append(trip)
    return out
