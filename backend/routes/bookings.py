import logging
from typing import List

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

try:
    from ..auth import AuthenticatedUser, get_current_user
    from ..database import get_db
    from ..schemas.bookings import (
        BookingCreate,
        BookingResponse,
        BookingStatusUpdate,
    )
    from ..services import booking_service
except ImportError:
    from auth import AuthenticatedUser, get_current_user
    from database import get_db
    from schemas.bookings import BookingCreate, BookingResponse, BookingStatusUpdate
    from services import booking_service

router = APIRouter()
logger = logging.getLogger(__name__)


@router.get("/", response_model=List[BookingResponse])
async def get_my_bookings(
    db: Session = Depends(get_db),
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    return booking_service.get_bookings_for_user(db, current_user.uid)


@router.post("/", response_model=BookingResponse)
async def create_booking(
    data: BookingCreate,
    db: Session = Depends(get_db),
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    try:
        booking = booking_service.create_booking(db, data, current_user.uid)
        # Spawn a Trip for this booking so its records/diary are trip-scoped.
        try:
            try:
                from ..services.trip_service import create_trip_for_booking
            except ImportError:
                from services.trip_service import create_trip_for_booking
            create_trip_for_booking(db, current_user.uid, booking)
        except Exception as trip_err:
            logger.warning(f"Trip auto-create from booking failed: {trip_err}")
        # Auto-create a focused journey diary entry for this booking
        try:
            try:
                from ..services.diary_service import create_booking_journey_diary
            except ImportError:
                from services.diary_service import create_booking_journey_diary
            await create_booking_journey_diary(db, current_user.uid, booking)
        except Exception as diary_err:
            logger.warning(f"Journey diary auto-create failed: {diary_err}")
        return booking
    except Exception as e:
        logger.exception("booking_create_failed", exc_info=e)
        raise HTTPException(status_code=500, detail="Failed to create booking.")


@router.patch("/{booking_id}/cancel", response_model=BookingResponse)
async def cancel_booking(
    booking_id: int,
    db: Session = Depends(get_db),
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    booking = booking_service.cancel_booking(db, booking_id, current_user.uid)
    if not booking:
        raise HTTPException(status_code=404, detail="Booking not found.")
    return booking
