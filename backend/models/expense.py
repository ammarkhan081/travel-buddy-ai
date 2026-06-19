from sqlalchemy import Column, Integer, String, Float
try:
    from ..database import Base
except ImportError:
    from database import Base

class Expense(Base):
    __tablename__ = "expenses"

    id = Column(Integer, primary_key=True, autoincrement=True)
    amount = Column(Float, nullable=False)
    category = Column(String, nullable=False)
    description = Column(String, nullable=True)
    date = Column(String, nullable=False)
    intent = Column(String, nullable=True)
    # Additional columns required by ExpenseResponse schema
    user_id = Column(String, nullable=False, index=True)
    created_at = Column(String, nullable=True)
    # Per-trip scoping + place/merchant context so the chatbot can answer
    # "how much did I spend on food at <hotel>?" and "expenses on the <place> trip".
    trip_id = Column(Integer, nullable=True, index=True)
    location = Column(String, nullable=True)   # city/area where money was spent
    merchant = Column(String, nullable=True)   # hotel/restaurant/shop name
