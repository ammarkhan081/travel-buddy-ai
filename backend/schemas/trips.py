"""Schemas for the Trip API (per-trip scoping of travel records)."""

from typing import Optional

from pydantic import BaseModel, Field


class TripCreate(BaseModel):
    """Start/record a trip. Only ``destination`` is required.

    ``start_date`` defaults to "now" server-side when omitted, so the Start
    Journey screen can create a trip with a single field.
    """
    destination: str = Field(..., description="Destination place name (any city/area)")
    origin: Optional[str] = Field(None, description="Origin place name")
    start_date: Optional[str] = Field(None, description="ISO start datetime (defaults to now)")
    end_date: Optional[str] = Field(None, description="ISO end datetime (null = ongoing)")
    transport: Optional[str] = Field(None, description="car | bike | train | flight | bus")
    notes: Optional[str] = Field(None, description="Free-text notes")
    booking_id: Optional[int] = Field(None, description="Related booking id if booked")


class TripUpdate(BaseModel):
    """Patch a trip (rename, edit window, add notes)."""
    destination: Optional[str] = None
    origin: Optional[str] = None
    start_date: Optional[str] = None
    end_date: Optional[str] = None
    transport: Optional[str] = None
    notes: Optional[str] = None


class TripStatusUpdate(BaseModel):
    """Complete or cancel a trip."""
    status: str = Field(..., description="active | completed | cancelled")
    end_date: Optional[str] = Field(None, description="ISO end datetime (defaults to now on completion)")


class TripResponse(BaseModel):
    id: int
    user_id: str
    destination: str
    origin: Optional[str]
    start_date: str
    end_date: Optional[str]
    status: str
    transport: Optional[str]
    notes: Optional[str]
    booking_id: Optional[int]
    created_at: str
    updated_at: str

    class Config:
        from_attributes = True
