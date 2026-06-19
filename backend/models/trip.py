"""Trip entity — the first-class container that scopes all travel records.

A Trip represents one journey to a destination (any place: Skardu, Lahore,
Karachi, Quetta, Abbottabad, ...). Expenses, reminders, voice notes, diary
entries and bookings can be linked to a Trip via their nullable ``trip_id``
column so the app can answer per-trip questions like:

  • "How much did I spend on the Kalam trip?"
  • "What were my reminders in Skardu?"
  • "How much went on food at that hotel?"  (combined with Expense.merchant)

Design notes
------------
* ``destination`` is free text — there is no hardcoded list of places.
* A user has at most ONE ``active`` trip at a time. New records created while a
  trip is active are auto-stamped with that trip server-side, so tagging works
  even before the client sends ``trip_id`` explicitly.
* All timestamps are stored as ISO-8601 UTC strings to stay consistent with the
  rest of the schema (reminders/expenses already use string ISO timestamps).
"""

from sqlalchemy import Column, Integer, String, Text

try:
    from ..database import Base
except ImportError:
    from database import Base


class Trip(Base):
    __tablename__ = "trips"

    id = Column(Integer, primary_key=True, autoincrement=True)
    user_id = Column(String, nullable=False, index=True)

    # Free-text place name(s). No hardcoded destination list.
    destination = Column(String, nullable=False)
    origin = Column(String, nullable=True)

    # Trip window. start_date is required; end_date is null while the trip is
    # ongoing (status == "active"). Stored as ISO-8601 UTC strings.
    start_date = Column(String, nullable=False, index=True)
    end_date = Column(String, nullable=True)

    # active | completed | cancelled
    status = Column(String, nullable=False, default="active", index=True)

    transport = Column(String, nullable=True)
    notes = Column(Text, nullable=True)

    # Optional linkage to a booking that spawned this trip.
    booking_id = Column(Integer, nullable=True)

    created_at = Column(String, nullable=False)
    updated_at = Column(String, nullable=False)
