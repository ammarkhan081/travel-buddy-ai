"""Schemas for travel diary API."""

from pydantic import BaseModel, Field
from typing import Optional


class DiaryCreateManual(BaseModel):
    """Schema for creating a manual diary entry."""
    title: str = Field(..., description="Entry title")
    content: str = Field(..., description="Entry content")
    location: Optional[str] = Field(None, description="Location of entry")
    imageUrl: Optional[str] = Field(None, description="Firebase Storage image URL")
    destination_name: Optional[str] = Field(None, description="Destination name for trip diaries")


class DiaryEntryResponse(BaseModel):
    """Schema for diary entry response."""
    id: int
    title: str
    content: str
    location: Optional[str]
    timestamp: str
    is_auto_generated: bool
    imageUrl: Optional[str] = None
    destination_name: Optional[str] = None

    class Config:
        from_attributes = True


class DiaryGenerateRequest(BaseModel):
    """Schema for AI diary generation — pulls reminders, expenses, voice notes, alerts,
    bookings and journey context to produce a rich English diary entry."""
    user_id: Optional[str] = Field("default", description="User ID")
    days: Optional[int] = Field(7, description="Number of days to summarize")
    # Trip / explicit date-range scoping (preferred over `days` when provided).
    trip_id: Optional[int] = Field(None, description="Generate a diary scoped to this trip's tagged records")
    from_date: Optional[str] = Field(None, description="ISO start date for an explicit date-range diary")
    to_date: Optional[str] = Field(None, description="ISO end date for an explicit date-range diary")
    latitude: Optional[float] = Field(None, description="Current latitude for GPS tagging")
    longitude: Optional[float] = Field(None, description="Current longitude for GPS tagging")
    # Active journey context (sent from client SharedPreferences)
    journey_from: Optional[str] = Field(None, description="Journey origin place name")
    journey_to: Optional[str] = Field(None, description="Journey destination place name")
    journey_transport: Optional[str] = Field(None, description="Transport mode: car/bike/train/flight")
    journey_departure_time: Optional[str] = Field(None, description="Departure datetime ISO string")
    journey_distance_km: Optional[float] = Field(None, description="Route distance in km")
    journey_duration_min: Optional[int] = Field(None, description="Estimated travel time in minutes")


class TripDiaryGenerateRequest(BaseModel):
    """Schema for generating a trip-specific diary entry (booked or friend trip)."""
    destination_name: str = Field(..., description="Name of the destination e.g. 'Skardu', 'Kumrat'")
    from_date: str = Field(..., description="Trip start date (YYYY-MM-DD)")
    return_date: Optional[str] = Field(None, description="Trip end date (YYYY-MM-DD)")
    notes: Optional[str] = Field(None, description="Personal notes or memories to include in the diary")
    booking_id: Optional[int] = Field(None, description="Related booking ID if this is a booked trip")


class DiaryUpdateRequest(BaseModel):
    """Schema for updating a diary entry."""
    content: Optional[str] = Field(None, description="Updated content")
    title: Optional[str] = Field(None, description="Updated title")
    location: Optional[str] = Field(None, description="Updated location")
    imageUrl: Optional[str] = Field(None, description="Firebase Storage image URL")
    destination_name: Optional[str] = Field(None, description="Destination name")
