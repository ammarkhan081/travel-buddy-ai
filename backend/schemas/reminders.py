"""Schemas for reminders API."""

from pydantic import BaseModel, Field
from typing import Optional, Literal
from datetime import datetime


class ReminderCreate(BaseModel):
    """Schema for creating a reminder."""
    title: str = Field(..., description="Reminder title")
    datetime: str = Field(..., description="Scheduled date and time (ISO format)")
    user_id: Optional[str] = Field("default", description="User ID")
    location: Optional[str] = Field(None, description="Location for the reminder")
    priority: Optional[str] = Field("medium", description="Priority: low, medium, high")
    trip_id: Optional[int] = Field(None, description="Trip id (auto-resolved if omitted)")


class ReminderResponse(BaseModel):
    """Schema for reminder response."""
    id: int
    title: str
    datetime: str
    user_id: str
    intent: Optional[str]
    transcript: Optional[str]
    location: Optional[str]
    priority: str
    created_at: str
    status: str
    trip_id: Optional[int] = None

    class Config:
        from_attributes = True


class ReminderIntent(BaseModel):
    """Detected intent from reminder text."""
    intent: str = Field(..., description="Detected intent: reminder, note, query, etc.")
    scheduled_time: Optional[datetime] = Field(None, description="Extracted scheduled time")
    location: Optional[str] = Field(None, description="Extracted location")
    priority: Optional[str] = Field("medium", description="Extracted priority: low, medium, high")
    entities: dict = Field(default_factory=dict, description="Additional extracted entities")
    confidence: float = Field(default=0.0, description="Extraction confidence (0-1)")
    title: Optional[str] = Field(None, description="Extracted title")
    transcript: Optional[str] = Field(None, description="Raw transcript text from STT")


class ReminderUpdate(BaseModel):
    """Schema for updating reminder status."""
    status: Literal["pending", "completed"] = Field(..., description="Updated status")
