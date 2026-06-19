from datetime import datetime

from sqlalchemy import Column, Integer, String

try:
    from ..database import Base
except ImportError:
    from database import Base


class Booking(Base):
    __tablename__ = "bookings"

    id = Column(Integer, primary_key=True, autoincrement=True)
    user_id = Column(String, nullable=False, index=True)
    destination_name = Column(String, nullable=False)
    agency_id = Column(String, nullable=False)
    agency_name = Column(String, nullable=False)
    travel_date = Column(String, nullable=False)
    return_date = Column(String, nullable=True)
    num_people = Column(Integer, nullable=False, default=1)
    user_phone = Column(String, nullable=False)
    user_name = Column(String, nullable=False)
    user_email = Column(String, nullable=True)
    special_requests = Column(String, nullable=True)
    status = Column(String, nullable=False, default="Completed")
    trip_id = Column(Integer, nullable=True, index=True)
    created_at = Column(
        String,
        nullable=False,
        default=lambda: datetime.utcnow().isoformat(),
    )
