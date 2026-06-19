from datetime import datetime

from sqlalchemy.orm import Session

try:
    from ..models.booking import Booking
    from ..schemas.bookings import BookingCreate
except ImportError:
    from models.booking import Booking
    from schemas.bookings import BookingCreate


def get_bookings_for_user(db: Session, user_id: str):
    return (
        db.query(Booking)
        .filter(Booking.user_id == user_id)
        .order_by(Booking.id.desc())
        .all()
    )


def create_booking(db: Session, data: BookingCreate, user_id: str) -> Booking:
    booking = Booking(
        user_id=user_id,
        destination_name=data.destination_name,
        agency_id=data.agency_id,
        agency_name=data.agency_name,
        travel_date=data.travel_date,
        return_date=data.return_date,
        num_people=data.num_people,
        user_phone=data.user_phone,
        user_name=data.user_name,
        user_email=data.user_email,
        special_requests=data.special_requests,
        status="Completed",
        created_at=datetime.utcnow().isoformat(),
    )
    db.add(booking)
    db.commit()
    db.refresh(booking)
    return booking


def cancel_booking(db: Session, booking_id: int, user_id: str) -> Booking | None:
    booking = (
        db.query(Booking)
        .filter(Booking.id == booking_id, Booking.user_id == user_id)
        .first()
    )
    if booking:
        booking.status = "Cancelled"
        db.commit()
        db.refresh(booking)
    return booking


def get_booking_by_id(db: Session, booking_id: int, user_id: str) -> Booking | None:
    return (
        db.query(Booking)
        .filter(Booking.id == booking_id, Booking.user_id == user_id)
        .first()
    )
