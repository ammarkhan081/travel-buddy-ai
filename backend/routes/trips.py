"""Routes for the Trip API — per-trip scoping of all travel records."""

import logging
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

try:
    from ..auth import AuthenticatedUser, get_current_user
    from ..database import get_db
    from ..schemas.trips import TripCreate, TripResponse, TripStatusUpdate, TripUpdate
    from ..services import trip_service
except ImportError:
    from auth import AuthenticatedUser, get_current_user
    from database import get_db
    from schemas.trips import TripCreate, TripResponse, TripStatusUpdate, TripUpdate
    from services import trip_service

router = APIRouter()
logger = logging.getLogger(__name__)


@router.get("/", response_model=List[TripResponse])
async def list_trips(
    db: Session = Depends(get_db),
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    """List all of the user's trips, newest first."""
    return trip_service.get_trips_for_user(db, current_user.uid)


@router.get("/active", response_model=Optional[TripResponse])
async def get_active_trip(
    db: Session = Depends(get_db),
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    """Return the user's current active trip, or null."""
    return trip_service.get_active_trip(db, current_user.uid)


@router.post("/", response_model=TripResponse)
async def create_trip(
    data: TripCreate,
    db: Session = Depends(get_db),
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    """Start (or record) a trip. Back-tags matching existing records automatically."""
    try:
        return trip_service.create_trip(db, data, current_user.uid)
    except Exception as e:
        logger.exception("trip_create_failed", exc_info=e)
        raise HTTPException(status_code=500, detail="Failed to create trip.")


@router.patch("/{trip_id}", response_model=TripResponse)
async def update_trip(
    trip_id: int,
    data: TripUpdate,
    db: Session = Depends(get_db),
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    trip = trip_service.update_trip(db, trip_id, data, current_user.uid)
    if not trip:
        raise HTTPException(status_code=404, detail="Trip not found.")
    return trip


@router.patch("/{trip_id}/status", response_model=TripResponse)
async def set_trip_status(
    trip_id: int,
    payload: TripStatusUpdate,
    db: Session = Depends(get_db),
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    """Complete or cancel a trip (e.g. when the user marks arrival / ends the journey)."""
    status = (payload.status or "").strip().lower()
    if status not in {"active", "completed", "cancelled"}:
        raise HTTPException(status_code=422, detail="Invalid trip status.")
    trip = trip_service.set_trip_status(db, trip_id, current_user.uid, status, payload.end_date)
    if not trip:
        raise HTTPException(status_code=404, detail="Trip not found.")
    return trip


@router.delete("/{trip_id}")
async def delete_trip(
    trip_id: int,
    db: Session = Depends(get_db),
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    """Delete a trip but keep its records (records are simply untagged)."""
    if trip_service.delete_trip(db, trip_id, current_user.uid):
        return {"message": "Trip deleted."}
    raise HTTPException(status_code=404, detail="Trip not found.")
