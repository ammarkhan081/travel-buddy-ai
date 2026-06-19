from sqlalchemy import Column, Integer, String
try:
    from ..database import Base
except ImportError:
    from database import Base

class VoiceNote(Base):
    __tablename__ = "voice_notes"

    id = Column(Integer, primary_key=True, autoincrement=True)
    user_id = Column(String, nullable=False, index=True)  # Link to user
    transcript = Column(String, nullable=False)
    keywords = Column(String, nullable=True)
    timestamp = Column(String, nullable=True)
    created_at = Column(String, nullable=True)
    # Per-trip scoping so voice notes are grouped with their trip.
    trip_id = Column(Integer, nullable=True, index=True)
    location = Column(String, nullable=True)
