"""Schemas for expenses API."""

from pydantic import BaseModel, Field
from typing import Optional
from datetime import datetime


class ExpenseCreate(BaseModel):
    """Schema for creating an expense."""
    amount: float = Field(..., description="Amount spent")
    category: str = Field(..., description="Expense category")
    description: Optional[str] = Field(None, description="Expense description")
    date: str = Field(..., description="Date of expense (ISO format)")
    user_id: Optional[str] = Field("default", description="User ID")
    location: Optional[str] = Field(None, description="City/area where money was spent")
    merchant: Optional[str] = Field(None, description="Hotel/restaurant/shop name")
    trip_id: Optional[int] = Field(None, description="Trip id (auto-resolved if omitted)")


class ExpenseResponse(BaseModel):
    """Schema for expense response."""
    id: int
    amount: float
    category: str
    description: Optional[str]
    date: str
    intent: Optional[str]
    user_id: str
    created_at: str
    trip_id: Optional[int] = None
    location: Optional[str] = None
    merchant: Optional[str] = None

    class Config:
        from_attributes = True


class ExpenseExtraction(BaseModel):
    """Extracted expense information."""
    amount: float = Field(..., description="Extracted amount")
    currency: str = Field(..., description="Currency code (USD, EUR, etc.)")
    category: str = Field(..., description="Expense category")
    description: str = Field(..., description="Expense description")
    location: Optional[str] = Field(None, description="Location if mentioned")
    merchant: Optional[str] = Field(None, description="Merchant/hotel/shop name if mentioned")
    confidence: float = Field(..., description="Extraction confidence (0-1)")
