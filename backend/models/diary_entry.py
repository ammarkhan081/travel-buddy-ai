from sqlalchemy import Column, Integer, String, Boolean
try:
    from ..database import Base
except ImportError:
    from database import Base

class DiaryEntry(Base):
    __tablename__ = "diary_entries"

    id = Column(Integer, primary_key=True, autoincrement=True)
    user_id = Column(String, nullable=False, index=True)  # Link to user
    title = Column(String, nullable=False)
    content = Column(String, nullable=False)
    location = Column(String, nullable=True)
    timestamp = Column(String, nullable=False)
    is_auto_generated = Column(Boolean, default=False)
    imageUrl = Column(String, nullable=True)   # Firebase Storage image URL
    destination_name = Column(String, nullable=True)  # Trip-specific diary (e.g. "Skardu", "Kumrat")
    # Per-trip scoping so a diary belongs to exactly one trip.
    trip_id = Column(Integer, nullable=True, index=True)
