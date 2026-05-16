"""Schemas for travel diary API."""

from pydantic import BaseModel, Field
from typing import Optional


class DiaryCreateManual(BaseModel):
    """Schema for creating a manual diary entry."""
    title: str = Field(..., description="Entry title")
    content: str = Field(..., description="Entry content")
    location: Optional[str] = Field(None, description="Location of entry")
    imageUrl: Optional[str] = Field(None, description="Firebase Storage image URL")


class DiaryEntryResponse(BaseModel):
    """Schema for diary entry response."""
    id: int
    title: str
    content: str
    location: Optional[str]
    timestamp: str
    is_auto_generated: bool
    imageUrl: Optional[str] = None

    class Config:
        from_attributes = True


class DiaryGenerateRequest(BaseModel):
    """Schema for diary generation request."""
    user_id: Optional[str] = Field("default", description="User ID")
    days: Optional[int] = Field(7, description="Number of days to summarize")
    latitude: Optional[float] = Field(None, description="Current latitude for GPS tagging")
    longitude: Optional[float] = Field(None, description="Current longitude for GPS tagging")


class DiaryUpdateRequest(BaseModel):
    """Schema for updating a diary entry."""
    content: Optional[str] = Field(None, description="Updated content")
    title: Optional[str] = Field(None, description="Updated title")
    location: Optional[str] = Field(None, description="Updated location")
    imageUrl: Optional[str] = Field(None, description="Firebase Storage image URL")
