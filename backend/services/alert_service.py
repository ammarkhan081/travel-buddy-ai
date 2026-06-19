"""Service for context-aware alerts with SQLAlchemy caching."""

import asyncio
import logging
import re

import httpx
from urllib.parse import urlencode
from datetime import datetime, timezone
from typing import Optional, List, Dict
from sqlalchemy.orm import Session
try:
    from ..models.alert_cache import AlertCache
    from ..schemas.alerts import AlertRequest, AlertResponse, WeatherAlert, TrafficAlert, NewsAlert
    from ..config import settings
except ImportError:
    from models.alert_cache import AlertCache
    from schemas.alerts import AlertRequest, AlertResponse, WeatherAlert, TrafficAlert, NewsAlert
    from config import settings

logger = logging.getLogger(__name__)


# Admin-area suffixes stripped when simplifying a reverse-geocoded address to a
# city name that OpenWeather can resolve.
_ADMIN_SUFFIXES = {"district", "division", "tehsil", "city", "region", "province", "valley", "town"}
# Placeholder origins the app may send that cannot be geocoded for traffic.
_UNRESOLVABLE_PLACES = {"current location", "my location", "unknown", ""}


def _weather_location_candidates(location: str) -> List[str]:
    """Return progressively simpler location strings to try for geocoding.

    OpenWeather needs a city-like name, but the client may pass a full reverse-
    geocoded address such as 'Skardu District, Baltistan Division, Gilgit-Baltistan'.
    Yields, in order: the full string, the first comma-segment, that segment with a
    trailing admin word removed, and finally the first word — e.g.
    ['Skardu District, Baltistan Division, Gilgit-Baltistan', 'Skardu District', 'Skardu'].
    """
    raw = (location or "").strip()
    if not raw:
        return []
    candidates = [raw]
    first_segment = raw.split(",")[0].strip()
    if first_segment and first_segment not in candidates:
        candidates.append(first_segment)
    words = first_segment.split()
    if len(words) >= 2 and words[-1].lower() in _ADMIN_SUFFIXES:
        stripped = " ".join(words[:-1]).strip()
        if stripped and stripped not in candidates:
            candidates.append(stripped)
    if words and len(words[0]) >= 4 and words[0] not in candidates:
        candidates.append(words[0])
    return candidates


def _is_coords(value: Optional[str]) -> bool:
    """True if the string is a 'lat,lon' pair (which Google can use directly)."""
    return bool(re.match(r"^\s*-?\d{1,3}(\.\d+)?\s*,\s*-?\d{1,3}(\.\d+)?\s*$", value or ""))


def _is_unresolvable_place(value: Optional[str]) -> bool:
    """True when the value is a placeholder that can't be geocoded (and isn't coords)."""
    if _is_coords(value):
        return False
    return (value or "").strip().lower() in _UNRESOLVABLE_PLACES


async def get_alerts_and_cache(db: Session, request: AlertRequest) -> AlertResponse:
    """Audit Step 10: Fetch real-time alerts and cache high-risk ones."""
    weather = None
    traffic = None
    news = None
    recommendations = []
    risk_score = 0.0
    requested_types = set(request.alert_types or ["weather", "traffic", "news"])
    
    # Normalize location inputs with backward compatibility.
    # - weather/news use a single location hint
    # - traffic prefers origin+destination
    location_hint = request.location or request.destination or request.origin or "Unknown"
    traffic_origin = request.origin or request.location or request.destination
    traffic_destination = request.destination or request.location or request.origin

    # Fetch weather, traffic and news CONCURRENTLY. They are independent external
    # API calls, so running them in parallel keeps total latency at ~the slowest
    # call instead of the sum — the client no longer times out waiting for alerts.
    async def _skip():
        return None

    weather, traffic, news = await asyncio.gather(
        fetch_weather(location_hint) if "weather" in requested_types else _skip(),
        fetch_traffic(traffic_origin, traffic_destination) if "traffic" in requested_types else _skip(),
        fetch_news(location_hint) if "news" in requested_types else _skip(),
    )

    # 1. Weather
    if weather:
        risk_score += 0.3 if weather.risk_level in ["high", "critical"] else 0.1
        recommendations.extend(weather.recommendations)
        if weather.risk_level in ["high", "critical"]:
            _cache_alert(
                db,
                "weather",
                weather.description,
                weather.risk_level,
                location_hint,
                request.user_id,
            )

    # 2. Traffic
    if traffic:
        risk_score += 0.3 if traffic.risk_level in ["high", "critical"] else 0.1
        recommendations.extend(traffic.recommendations)
        if traffic.risk_level in ["high", "critical"]:
            _cache_alert(
                db,
                "traffic",
                f"Delay: {traffic.estimated_delay}",
                traffic.risk_level,
                f"{traffic_origin or 'Unknown'} -> {traffic_destination or 'Unknown'}",
                request.user_id,
            )

    # 3. News
    if news:
        risk_score += 0.2 if news.risk_level in ["high", "critical"] else 0.05
        news_recommendations = getattr(news, "recommendations", None) or []
        if news_recommendations:
            recommendations.extend(news_recommendations)
        elif news.headlines:
            recommendations.append("Review local news updates before departure.")
        if news.risk_level in ["high", "critical"]:
            _cache_alert(
                db,
                "news",
                news.headlines[0] if news.headlines else "News Alert",
                news.risk_level,
                location_hint,
                request.user_id,
            )
    
    risk_score = min(1.0, risk_score)

    return AlertResponse(
        user_id=request.user_id,
        location=location_hint,
        timestamp=datetime.now(),
        weather=weather,
        traffic=traffic,
        news=news,
        overall_risk_score=risk_score,
        recommendations=list(set(recommendations))
    )

def _cache_alert(db: Session, alert_type: str, message: str, severity: str, location: str, user_id: str = "anonymous"):
    """Helper to save alert to SQLite, scoped to user."""
    try:
        cache_entry = AlertCache(
            user_id=user_id,
            type=alert_type,
            message=message,
            severity=severity,
            location=location,
            created_at=datetime.now(timezone.utc).isoformat()
        )
        db.add(cache_entry)
        db.commit()
    except Exception as e:
        logger.error(f"Failed to cache alert: {e}")
        db.rollback()

def get_alert_history(db: Session, user_id: str, limit: int = 10) -> list:
    """Returns last N cached alerts for the requesting user."""
    return (
        db.query(AlertCache)
        .filter(AlertCache.user_id == user_id)
        .order_by(AlertCache.created_at.desc())
        .limit(limit)
        .all()
    )

# --- External API Fetchers ---

async def fetch_weather(location: str) -> Optional[WeatherAlert]:
    api_key = settings.OPENWEATHERMAP_API_KEY
    if not api_key:
        return None
    candidates = _weather_location_candidates(location)
    if not candidates:
        return None
    try:
        weather_url = "http://api.openweathermap.org/data/2.5/weather"
        forecast_url = "http://api.openweathermap.org/data/2.5/forecast"

        async with httpx.AsyncClient(timeout=5.0) as client:
            # Try progressively simpler location names until one resolves, so a
            # full reverse-geocoded address still yields weather for its city.
            data = None
            resolved_q = candidates[0]
            resp = None
            for _cand in candidates:
                resp = await client.get(
                    weather_url,
                    params={"q": _cand, "appid": api_key, "units": "metric"},
                )
                if resp.status_code == 200:
                    data = resp.json()
                    resolved_q = _cand
                    break
            if data is not None:
                forecast_params = {"q": resolved_q, "appid": api_key, "units": "metric", "cnt": 8}
                main_data = data.get("main", {})
                temp_raw = main_data.get("temp", main_data.get("feels_like"))

                try:
                    temp_value = float(temp_raw)
                except (TypeError, ValueError):
                    logger.warning(
                        "fetch_weather_missing_temp",
                        extra={"event": "fetch_weather_missing_temp", "location": location},
                    )
                    return None

                weather_items = data.get("weather", [])
                cond = weather_items[0].get("main") if weather_items else "Unknown"
                desc = weather_items[0].get("description") if weather_items else "No description"
                humidity_raw = main_data.get("humidity")
                try:
                    humidity = int(float(humidity_raw)) if humidity_raw is not None else None
                except (TypeError, ValueError):
                    humidity = None

                wind_speed = data.get("wind", {}).get("speed")
                try:
                    wind_speed_kmh = round(float(wind_speed) * 3.6, 1) if wind_speed is not None else None
                except (TypeError, ValueError):
                    wind_speed_kmh = None

                visibility_m = data.get("visibility")
                try:
                    visibility_km = round(float(visibility_m) / 1000.0, 1) if visibility_m is not None else None
                except (TypeError, ValueError):
                    visibility_km = None

                cond_text = str(cond or "Unknown")
                risk = (
                    "high"
                    if temp_value > 35 or temp_value < 0
                    else "medium"
                    if "storm" in cond_text.lower()
                    else "low"
                )

                hourly_forecast = []
                try:
                    forecast_resp = await client.get(forecast_url, params=forecast_params)
                    if forecast_resp.status_code == 200:
                        forecast_data = forecast_resp.json()
                        for item in (forecast_data.get("list", []) or [])[:8]:
                            main_data = item.get("main", {}) or {}
                            weather_data = (item.get("weather", []) or [{}])[0]
                            hourly_forecast.append(
                                {
                                    "time": item.get("dt_txt") or "",
                                    "temperature": main_data.get("temp"),
                                    "condition": weather_data.get("main") or "Unknown",
                                }
                            )
                except Exception as e:
                    logger.warning(
                        "fetch_weather_forecast_failed",
                        extra={"event": "fetch_weather_forecast_failed", "error": str(e), "location": location},
                    )

                return WeatherAlert(
                    location=location,
                    temperature=temp_value,
                    condition=cond_text,
                    description=desc,
                    humidity=humidity,
                    wind_speed_kmh=wind_speed_kmh,
                    visibility_km=visibility_km,
                    hourly_forecast=hourly_forecast,
                    risk_level=risk,
                    recommendations=[f"Check for {cond_text}"] if risk != "low" else [],
                )
        logger.warning("fetch_weather_non_200", extra={"event": "fetch_weather_non_200", "status": resp.status_code, "location": location})
    except Exception as e:
        logger.error("fetch_weather_error", extra={"event": "fetch_weather_error", "error": str(e), "location": location})
    return None

async def fetch_traffic(origin: Optional[str], destination: Optional[str]) -> Optional[TrafficAlert]:
    """
    Real traffic estimation using Google Distance Matrix API when configured.
    Backward-compatible fallback if API key or route inputs are unavailable.
    """
    if not origin or not destination:
        return None

    # The origin may be the placeholder "Current Location" (the app's default when
    # the user hasn't typed an origin). Google can't geocode that, so skip the call
    # gracefully — no error, no wasted latency — unless we were given real coords.
    if _is_unresolvable_place(origin) or _is_unresolvable_place(destination):
        return TrafficAlert(
            location=f"{origin} -> {destination}",
            route=f"{origin} -> {destination}",
            current_traffic="unknown",
            estimated_delay=None,
            distance_text=None,
            duration_text=None,
            duration_in_traffic_text=None,
            risk_level="low",
            recommendations=[],
        )

    api_key = settings.GOOGLE_MAPS_API_KEY
    if not api_key:
        # Safe fallback for dev mode: no key, but deterministic structure.
        return TrafficAlert(
            location=f"{origin} -> {destination}",
            route=f"{origin} -> {destination}",
            current_traffic="unknown",
            estimated_delay=None,
            distance_text=None,
            duration_text=None,
            duration_in_traffic_text=None,
            risk_level="low",
            recommendations=["Add GOOGLE_MAPS_API_KEY to enable live traffic estimates."],
        )

    try:
        base = "https://maps.googleapis.com/maps/api/distancematrix/json"
        query = urlencode(
            {
                "origins": origin,
                "destinations": destination,
                "departure_time": "now",
                "traffic_model": "best_guess",
                "mode": "driving",
                "key": api_key,
            }
        )
        async with httpx.AsyncClient(timeout=6.0) as client:
            resp = await client.get(f"{base}?{query}")
        if resp.status_code != 200:
            logger.warning(
                "fetch_traffic_non_200",
                extra={"event": "fetch_traffic_non_200", "status": resp.status_code},
            )
            return None

        data = resp.json()
        if data.get("status") != "OK":
            logger.warning(
                "fetch_traffic_api_status",
                extra={"event": "fetch_traffic_api_status", "status": data.get("status")},
            )
            return None

        rows = data.get("rows", [])
        if not rows or not rows[0].get("elements"):
            return None
        element = rows[0]["elements"][0]
        if element.get("status") != "OK":
            return None

        duration = (element.get("duration", {}) or {}).get("value")
        duration_traffic = (element.get("duration_in_traffic", {}) or {}).get("value")
        distance_text = (element.get("distance", {}) or {}).get("text")
        duration_text = (element.get("duration", {}) or {}).get("text")
        duration_in_traffic_text = (element.get("duration_in_traffic", {}) or {}).get("text")
        if not duration or not duration_traffic:
            return None

        delay_minutes = max(0, int((duration_traffic - duration) / 60))
        if delay_minutes >= 30:
            risk = "high"
            current = "heavy"
            recs = ["Heavy traffic expected. Leave early or choose an alternate route."]
        elif delay_minutes >= 10:
            risk = "medium"
            current = "moderate"
            recs = ["Moderate delay expected. Add extra travel buffer time."]
        else:
            risk = "low"
            current = "normal"
            recs = []

        return TrafficAlert(
            location=f"{origin} -> {destination}",
            route=f"{origin} -> {destination}",
            current_traffic=current,
            estimated_delay=delay_minutes,
            distance_text=distance_text,
            duration_text=duration_text,
            duration_in_traffic_text=duration_in_traffic_text,
            risk_level=risk,
            recommendations=recs,
        )
    except Exception as e:
        logger.error("fetch_traffic_error", extra={"event": "fetch_traffic_error", "error": str(e)})
        return None

async def fetch_news(location: str) -> Optional[NewsAlert]:
    api_key = settings.NEWS_API_KEY
    if not api_key:
        return None
    try:
        url = "https://newsapi.org/v2/everything"
        params = {"q": location, "apiKey": api_key, "pageSize": 3}
        async with httpx.AsyncClient(timeout=5.0) as client:
            resp = await client.get(url, params=params)
        if resp.status_code == 200:
            data = resp.json()
            articles = data.get("articles", [])
            headlines = [
                (article.get("title") or "").strip()
                for article in articles
                if isinstance(article, dict)
            ]
            headlines = [headline for headline in headlines if headline]

            recommendations = ["Review local news updates before departure."] if headlines else []
            return NewsAlert(
                location=location,
                headlines=headlines,
                risk_level="low",
                relevant_articles=[],
                recommendations=recommendations,
            )
        logger.warning("fetch_news_non_200", extra={"event": "fetch_news_non_200", "status": resp.status_code, "location": location})
    except Exception as e:
        logger.error("fetch_news_error", extra={"event": "fetch_news_error", "error": str(e), "location": location})
    return None
