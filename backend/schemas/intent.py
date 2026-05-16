"""Schemas for intent classification API (proposal: automatic reminder creation from voice)."""

from typing import Optional, Dict, Any, Literal
from pydantic import BaseModel, Field


class IntentClassifyRequest(BaseModel):
    """Request body for intent classification."""
    text: str = Field(..., description="User speech transcript or text to classify")


class IntentClassifyResponse(BaseModel):
    """Response: intent only (reminder, expense, note, query, other)."""
    intent: str = Field(..., description="reminder | expense | note | query | other")


class DecisionReviewResolveRequest(BaseModel):
    """Resolve an auditable pending decision from voice flow."""
    action: Literal["accepted", "rejected", "edited"]
    resolution_payload: Optional[Dict[str, Any]] = None


class DecisionReviewResolveResponse(BaseModel):
    id: int
    status: str
    resolved_at: Optional[str] = None
