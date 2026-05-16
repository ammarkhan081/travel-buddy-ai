"""Tests for expense extraction functionality."""

import pytest
from unittest.mock import patch, Mock, AsyncMock, MagicMock


@pytest.mark.asyncio
async def test_expense_extraction_gpt():
    """Test GPT-based expense extraction."""
    from ai.inference.expense_parser.expense_extractor import extract_expense_gpt
    
    mock_response = MagicMock()
    mock_response.choices = [MagicMock(message=MagicMock(
        content='{"amount": 50.0, "currency": "USD", "category": "food", "description": "Lunch at restaurant", "location": "New York", "confidence": 0.9}'
    ))]
    
    with patch('openai.OpenAI') as mock_openai:
        mock_client = Mock()
        mock_client.chat.completions.create.return_value = mock_response
        mock_openai.return_value = mock_client
        
        result = await extract_expense_gpt("Spent $50 on lunch at a restaurant in New York")
        
        assert result["amount"] == 50.0
        assert result["currency"] == "USD"
        assert result["category"] == "food"
        assert result["location"] == "New York"


def test_expense_extraction_regex():
    """Test regex-based expense extraction (fallback)."""
    from ai.inference.expense_parser.expense_extractor import extract_with_regex
    
    amount, currency = extract_with_regex("Spent $50.99 on lunch")
    
    assert amount == 50.99
    assert currency == "USD"


def test_expense_creation():
    """Test expense creation endpoint."""
    from fastapi.testclient import TestClient
    from backend.main import app
    
    client = TestClient(app)
    
    with patch('backend.services.expense_service.create_expense', new_callable=AsyncMock) as mock_create:
        from datetime import datetime
        mock_create.return_value = {
            "id": 1,
            "user_id": "test_user",
            "amount": 50.0,
            "category": "food",
            "description": "Lunch",
            "date": datetime.now().isoformat(),
            "intent": "manual",
            "created_at": datetime.now().isoformat()
        }
        
        response = client.post(
            "/api/expenses/",
            json={
                "amount": 50.0,
                "category": "food",
                "description": "Lunch",
                "date": "2024-01-15",
                "user_id": "test_user"
            }
        )
        
        assert response.status_code == 200
        assert response.json()["amount"] == 50.0

