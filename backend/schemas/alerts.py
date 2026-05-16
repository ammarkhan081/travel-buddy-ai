"""Schemas for alerts API."""

from pydantic import BaseModel, Field
from typing import Optional, List
from datetime import datetime


class AlertRequest(BaseModel):
    """Schema for alert request."""
    user_id: str = Field(..., description="User ID")
    location: Optional[str] = Field(
        None,
        description="General location (backward compatible). If origin/destination are provided, traffic uses them.",
    )
    origin: Optional[str] = Field(None, description="Traffic origin location")
    destination: Optional[str] = Field(None, description="Traffic destination location")
    alert_types: Optional[List[str]] = Field(
        ["weather", "traffic", "news"],
        description="Types of alerts to fetch"
    )


class WeatherAlert(BaseModel):
    """Weather alert information."""
    location: str
    temperature: float
    condition: str
    description: str
    humidity: Optional[int] = Field(None, description="Humidity percentage")
    wind_speed_kmh: Optional[float] = Field(None, description="Wind speed in km/h")
    visibility_km: Optional[float] = Field(None, description="Visibility in kilometers")
    hourly_forecast: List[dict] = Field(default_factory=list, description="Hourly weather forecast snapshots")
    risk_level: str = Field(..., description="Risk level: low, medium, high, critical")
    recommendations: List[str] = Field(default_factory=list)


class TrafficAlert(BaseModel):
    """Traffic alert information."""
    location: str
    route: Optional[str]
    current_traffic: str = Field(..., description="Current traffic status")
    estimated_delay: Optional[int] = Field(None, description="Estimated delay in minutes")
    distance_text: Optional[str] = Field(None, description="Route distance text")
    duration_text: Optional[str] = Field(None, description="Normal duration text")
    duration_in_traffic_text: Optional[str] = Field(None, description="Duration with traffic text")
    risk_level: str
    recommendations: List[str] = Field(default_factory=list)


class NewsAlert(BaseModel):
    """News alert information."""
    location: str
    headlines: List[str] = Field(default_factory=list)
    risk_level: str
    relevant_articles: List[dict] = Field(default_factory=list)
    recommendations: List[str] = Field(default_factory=list)


class AlertResponse(BaseModel):
    """Schema for alert response."""
    user_id: str
    location: str
    timestamp: datetime
    weather: Optional[WeatherAlert] = None
    traffic: Optional[TrafficAlert] = None
    news: Optional[NewsAlert] = None
    overall_risk_score: float = Field(..., description="Overall risk score (0-1)")
    recommendations: List[str] = Field(default_factory=list)

class AlertHistoryResponse(BaseModel):
    """Schema for a single cached alert in history."""
    id: int
    type: str
    message: str
    severity: str
    location: Optional[str]
    created_at: str

    class Config:
        from_attributes = True

