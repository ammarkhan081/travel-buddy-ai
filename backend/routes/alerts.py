"""Routes for context-aware alerts API."""

import asyncio
import logging
from fastapi import APIRouter, HTTPException, Depends, Query
from typing import List, Optional
from sqlalchemy.orm import Session
try:
    from ..auth import AuthenticatedUser, get_current_user
    from ..database import get_db
    from ..schemas.alerts import AlertRequest, AlertResponse, AlertHistoryResponse
    from ..services import alert_service
except ImportError:
    from auth import AuthenticatedUser, get_current_user
    from database import get_db
    from schemas.alerts import AlertRequest, AlertResponse, AlertHistoryResponse
    from services import alert_service

router = APIRouter()
logger = logging.getLogger(__name__)


@router.get("/")
async def get_alerts_by_location(
    lat: Optional[float] = Query(None, description="Latitude"),
    lon: Optional[float] = Query(None, description="Longitude"),
    location: Optional[str] = Query(None, description="Location name (city/address)"),
    db: Session = Depends(get_db)
):
    """
    GET /api/alerts?lat=&lon=: Fetch weather + news alerts by coordinates or location name.
    Returns a unified list of alert objects. Never returns 500 — empty list on all failures.
    """
    try:
        # Resolve location name from coordinates if needed
        loc_str = location or "Unknown"
        if lat is not None and lon is not None and not location:
            try:
                from geopy.geocoders import Nominatim
                geolocator = Nominatim(user_agent="travel_buddy")
                geo_result = await asyncio.to_thread(
                    geolocator.reverse, f"{lat},{lon}", timeout=5
                )
                loc_str = geo_result.address if geo_result else f"{lat},{lon}"
            except Exception:
                loc_str = f"{lat},{lon}"

        # Build a simple alert list
        alerts = []
        weather = await alert_service.fetch_weather(loc_str)
        if weather and weather.risk_level in ["high", "critical"]:
            alerts.append({
                "type": "weather",
                "message": f"⚠️ {weather.condition} expected in {loc_str}: {weather.description}",
                "severity": weather.risk_level
            })

        news = await alert_service.fetch_news(loc_str)
        if news:
            for headline in news.headlines[:3]:
                alerts.append({
                    "type": "news",
                    "message": headline,
                    "severity": "medium"
                })

        return alerts
    except Exception:
        return []


@router.post("/")
async def get_alerts(
    request: AlertRequest,
    db: Session = Depends(get_db),
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    """POST /api/alerts: Fetches real-time weather, traffic, and news based on context."""
    try:
        request.user_id = current_user.uid
        return await alert_service.get_alerts_and_cache(db, request)
    except Exception as e:
        logger.exception("alerts_fetch_failed", exc_info=e)
        raise HTTPException(status_code=500, detail="Failed to fetch alerts.")


@router.post("/trip-check")
async def check_trip_alerts(
    destination: str = Query(..., description="Destination city or address"),
    travel_datetime: Optional[str] = Query(None, description="Planned travel time (ISO)"),
    db: Session = Depends(get_db)
):
    """
    POST /api/alerts/trip-check: Check weather + news for destination before a trip.
    Returns smart alerts. Never crashes — returns empty list on all failures.
    """
    try:
        alerts = []

        weather = await alert_service.fetch_weather(destination)
        if weather:
            if weather.risk_level in ["high", "critical"]:
                alerts.append({
                    "type": "weather",
                    "message": f"⚠️ {weather.condition} expected at {destination}. "
                               f"Temperature: {weather.temperature}°C. Plan carefully.",
                    "severity": weather.risk_level
                })
            else:
                alerts.append({
                    "type": "weather",
                    "message": f"Weather at {destination}: {weather.condition}, {weather.temperature}°C.",
                    "severity": "low"
                })

        news = await alert_service.fetch_news(destination)
        if news:
            for headline in news.headlines[:2]:
                alerts.append({
                    "type": "news",
                    "message": headline,
                    "severity": "medium"
                })

        if not alerts:
            alerts.append({
                "type": "info",
                "message": f"No significant alerts for {destination}. Have a safe trip!",
                "severity": "low"
            })

        return {"destination": destination, "travel_datetime": travel_datetime, "alerts": alerts}
    except Exception:
        return {"destination": destination, "travel_datetime": travel_datetime, "alerts": []}


@router.get("/history", response_model=List[AlertHistoryResponse])
async def get_alert_history(
    limit: int = Query(10, ge=1, le=50),
    db: Session = Depends(get_db),
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    """GET /api/alerts/history: Returns last N cached alerts for the requesting user."""
    return alert_service.get_alert_history(db, user_id=current_user.uid, limit=limit)
