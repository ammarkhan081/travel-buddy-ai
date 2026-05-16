from sqlalchemy import Column, Integer, String

try:
    from ..database import Base
except ImportError:
    from database import Base


class DecisionReview(Base):
    __tablename__ = "decision_reviews"

    id = Column(Integer, primary_key=True, autoincrement=True)
    user_id = Column(String, nullable=False, index=True)
    transcript = Column(String, nullable=False)
    intent = Column(String, nullable=False)
    source_action = Column(String, nullable=False)
    suggested_payload = Column(String, nullable=True)
    status = Column(String, nullable=False, default="pending")
    resolution_payload = Column(String, nullable=True)
    created_at = Column(String, nullable=False)
    resolved_at = Column(String, nullable=True)
