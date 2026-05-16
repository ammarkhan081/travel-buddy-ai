from sqlalchemy import Column, Integer, String
from sqlalchemy.orm import declarative_base as _Base
try:
    from ..database import Base
except ImportError:
    from database import Base

class Reminder(Base):
    __tablename__ = "reminders"

    id = Column(Integer, primary_key=True, autoincrement=True)
    title = Column(String, nullable=False)
    datetime = Column(String, nullable=False)
    transcript = Column(String, nullable=True)
    text = Column(String, nullable=False)
    intent = Column(String, nullable=True)
    # Additional columns required by ReminderResponse schema
    user_id = Column(String, nullable=False, index=True)
    location = Column(String, nullable=True)
    priority = Column(String, default="medium")
    status = Column(String, default="pending")
    created_at = Column(String, nullable=True)
