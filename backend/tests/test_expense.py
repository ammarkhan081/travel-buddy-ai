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


# ── PKR (Pakistani Rupee) regex tests ─────────────────────────────────────────

def test_expense_regex_pkr_explicit():
    """'500 PKR' should resolve to PKR currency."""
    from ai.inference.expense_parser.expense_extractor import extract_with_regex

    amount, currency = extract_with_regex("I spent 500 PKR on biryani")

    assert amount == 500.0
    assert currency == "PKR"


def test_expense_regex_rs_notation():
    """'Rs 200' (common Pakistani shorthand) should resolve to PKR."""
    from ai.inference.expense_parser.expense_extractor import extract_with_regex

    amount, currency = extract_with_regex("paid Rs 200 for chai and samosa")

    assert amount == 200.0
    assert currency == "PKR"


def test_expense_regex_rs_dot_notation():
    """'Rs.' (with dot) should also be treated as PKR."""
    from ai.inference.expense_parser.expense_extractor import extract_with_regex

    amount, currency = extract_with_regex("hotel was Rs. 3500 per night")

    assert amount == 3500.0
    assert currency == "PKR"


def test_expense_multi_amount_pkr():
    """Multiple PKR amounts should be summed when joined by 'and'."""
    from ai.inference.expense_parser.expense_extractor import (
        extract_all_amounts_with_regex,
        _resolve_multi_amount_value,
    )

    amounts, currency = extract_all_amounts_with_regex(
        "spent 300 PKR on lunch and 150 PKR on tea"
    )

    assert currency == "PKR"
    assert 300.0 in amounts
    assert 150.0 in amounts
    total = _resolve_multi_amount_value(
        "spent 300 PKR on lunch and 150 PKR on tea", amounts
    )
    assert total == 450.0


def test_expense_regex_hybrid_pkr_fallback():
    """Regex hybrid fallback should detect PKR amounts correctly."""
    from ai.inference.expense_parser.expense_extractor import extract_with_regex_hybrid

    result = extract_with_regex_hybrid("bought a bus ticket for 250 PKR in Lahore")

    assert result["amount"] == 250.0
    assert result["currency"] == "PKR"
    assert result["category"] == "transport"


def test_expense_pkr_not_overridden_by_inr():
    """Ensure PKR is not mis-classified as INR (Indian vs Pakistani rupee)."""
    from ai.inference.expense_parser.expense_extractor import extract_with_regex

    amount, currency = extract_with_regex("total was 1200 PKR at the market")

    assert currency == "PKR"
    assert currency != "INR"


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

