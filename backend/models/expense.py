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
