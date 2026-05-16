"""Test script to verify RAG logic in backend."""

import sys
from pathlib import Path

# Add project root and backend to path
ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.append(str(ROOT))
sys.path.append(str(ROOT / "backend"))

from sqlalchemy.orm import Session
from backend.database import SessionLocal, engine, Base
from backend.models.expense import Expense
from backend.services import chat_service

def test_chat_rag():
    print("Starting RAG test...")
    
    # Create tables if they don't exist
    Base.metadata.create_all(bind=engine)
    
    db = SessionLocal()
    user_id = "test_user_123"
    
    try:
        # 1. Insert mock expense
        print(f"Inserting mock expense for user {user_id}...")
        new_expense = Expense(
            user_id=user_id,
            amount=50.0,
            category="Food & Dining",
            description="Steak Dinner",
            date="2026-03-02T20:00:00"
        )
        db.add(new_expense)
        db.commit()
        
        # 2. Test context retrieval
        print("Testing context retrieval...")
        context = chat_service.get_trip_context(db, user_id)
        print(f"Retrieved Context:\n{context}")
        assert "Steak Dinner" in context
        assert "50.0" in context
        
        # 3. Test chat response (Mocking OpenAI is complex, so we'll just check logic up to generate_chat_response)
        print("Logic check passed: Context contains expected trip data.")
        
    finally:
        # Clean up
        db.query(Expense).filter(Expense.user_id == user_id).delete()
        db.commit()
        db.close()
        print("Test cleanup complete.")

if __name__ == "__main__":
    test_chat_rag()
