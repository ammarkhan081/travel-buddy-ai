from typing import Optional

from pydantic import BaseModel


class BookingCreate(BaseModel):
    destination_name: str
    agency_id: str
    agency_name: str
    travel_date: str
    return_date: Optional[str] = None
    num_people: int = 1
    user_phone: str
    user_name: str
    user_email: Optional[str] = None
    special_requests: Optional[str] = None
    user_id: Optional[str] = None


class BookingResponse(BaseModel):
    id: int
    user_id: str
    destination_name: str
    agency_id: str
    agency_name: str
    travel_date: str
    return_date: Optional[str]
    num_people: int
    user_phone: str
    user_name: str
    user_email: Optional[str]
    special_requests: Optional[str]
    status: str
    created_at: str

    class Config:
        from_attributes = True


class BookingStatusUpdate(BaseModel):
    status: str
