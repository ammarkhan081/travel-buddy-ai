from sqlalchemy import Column, Integer, String, Index
try:
    from ..database import Base
except ImportError:
    from database import Base

class AlertCache(Base):
    __tablename__ = "alert_cache"

    id = Column(Integer, primary_key=True, autoincrement=True)
    user_id = Column(String, nullable=True, index=True)  # M-4: per-user isolation
    type = Column(String, nullable=False)
    message = Column(String, nullable=False)
    severity = Column(String, nullable=False)
    location = Column(String, nullable=True)
    created_at = Column(String, nullable=False, index=True)
