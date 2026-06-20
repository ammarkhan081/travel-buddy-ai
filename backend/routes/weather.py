"""Weather route used by the Flutter Weather module."""

import logging
from typing import Optional

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

try:
    from ..services import alert_service
except ImportError:
    from services import alert_service

router = APIRouter()
logger = logging.getLogger(__name__)


class WeatherRequest(BaseModel):
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    location: Optional[str] = None


@router.post("/")
async def get_weather(request: WeatherRequest):
    """Return detailed weather data in the shape expected by Flutter."""
    location = (request.location or "").strip()
    if not location:
        if request.latitude is not None and request.longitude is not None:
            location = f"{request.latitude},{request.longitude}"
        else:
            raise HTTPException(status_code=422, detail="Location or coordinates are required.")

    weather = await alert_service.fetch_weather(location)
    if weather is None:
        logger.warning("weather_fetch_unavailable", extra={"location": location})
        raise HTTPException(status_code=503, detail="Weather data is unavailable.")

    if hasattr(weather, "model_dump"):
        return weather.model_dump()
    return weather.dict()
