"""Service for diary management using SQLAlchemy."""

import asyncio
import logging
import os
from datetime import datetime, timedelta
from pathlib import Path
from typing import List, Optional, Dict
from sqlalchemy.orm import Session
try:
    from ..models.diary_entry import DiaryEntry
    from ..models.reminder import Reminder
    from ..models.expense import Expense
    from ..models.voice_note import VoiceNote
    from ..schemas.diary import DiaryCreateManual, DiaryGenerateRequest, DiaryUpdateRequest, TripDiaryGenerateRequest
except ImportError:
    from models.diary_entry import DiaryEntry
    from models.reminder import Reminder
    from models.expense import Expense
    from models.voice_note import VoiceNote
    from schemas.diary import DiaryCreateManual, DiaryGenerateRequest, DiaryUpdateRequest, TripDiaryGenerateRequest
from ai.inference.summarizer.diary_summarizer import summarize_diary, _get_openai_api_key
from backend.utils.time_utils import now_utc_iso

logger = logging.getLogger(__name__)

# Directory where exported files are saved
EXPORT_DIR = os.getenv("DIARY_FILES_DIR", "diary_files")


async def create_manual_entry(db: Session, entry_data: DiaryCreateManual, user_id: str) -> DiaryEntry:
    """POST /api/diary/manual."""
    try:
        db_entry = DiaryEntry(
            user_id=user_id,
            title=entry_data.title,
            content=entry_data.content,
            location=entry_data.location,
            imageUrl=entry_data.imageUrl,
            destination_name=entry_data.destination_name,
            timestamp=now_utc_iso(),
            is_auto_generated=False,
        )
        db.add(db_entry)
        db.commit()
        db.refresh(db_entry)
        return db_entry
    except Exception as e:
        logger.error(f"Error creating manual diary entry: {e}")
        db.rollback()
        raise


async def generate_diary_ai(db: Session, request: DiaryGenerateRequest) -> DiaryEntry:
    """POST /api/diary/auto-generate: Comprehensive AI diary entry in English.

    Gathers ALL available user data within the requested window:
      • Reminders (tour events / voice reminders)
      • Voice notes (transcripts)
      • Expenses
      • Bookings / travel packages
      • Cached weather & news alerts
      • Active journey info (from / to / transport / distance / ETA)

    Generates a rich narrative English diary entry using GPT (falls back to
    a well-structured local template when AI is unavailable).
    """
    user_id = request.user_id or "default"
    now_dt = datetime.now()
    date_str = now_dt.strftime("%B %d, %Y")
    now_iso = now_utc_iso()
    days = max(1, int(request.days or 7))
    window_start = now_dt - timedelta(days=days)
    window_start_iso = window_start.isoformat()
    window_start_date = window_start.strftime("%Y-%m-%d")

    trip_id = getattr(request, "trip_id", None)
    from_date = getattr(request, "from_date", None)
    to_date = getattr(request, "to_date", None)

    # If the client didn't specify a trip/date range but there IS an active
    # journey, scope the diary to the user's active trip so a multi-day journey
    # is summarised IN FULL (every day of the trip), not just the last 24 hours.
    # Using the trip id pulls exactly that trip's tagged records — no leakage and
    # no arbitrary cutoff. Falls back silently to the rolling window if there is
    # no active trip on the backend.
    if trip_id is None and from_date is None and (request.journey_from or request.journey_to):
        try:
            try:
                from .trip_service import get_active_trip
            except ImportError:
                from services.trip_service import get_active_trip
            _active_trip = get_active_trip(db, user_id)
            if _active_trip is not None:
                trip_id = _active_trip.id
        except Exception as e:
            logger.warning(f"active-trip resolve for diary failed: {e}")

    # Resolve trip destination (used for title/location when trip-scoped).
    trip_destination = None
    if trip_id is not None:
        try:
            try:
                from .trip_service import get_trip
            except ImportError:
                from services.trip_service import get_trip
            _t = get_trip(db, trip_id, user_id)
            if _t:
                trip_destination = _t.destination
        except Exception:
            pass

    # ── 1. Collect data from all sources ─────────────────────────────────────
    try:
        try:
            from ..models.booking import Booking
        except ImportError:
            from models.booking import Booking
        try:
            from ..models.alert_cache import AlertCache
        except ImportError:
            from models.alert_cache import AlertCache

        if trip_id is not None:
            # Trip-scoped: ONLY records tagged to this trip (e.g. Skardu-only).
            reminders = (db.query(Reminder)
                .filter(Reminder.user_id == user_id, Reminder.trip_id == trip_id)
                .order_by(Reminder.datetime.asc()).all())
            expenses = (db.query(Expense)
                .filter(Expense.user_id == user_id, Expense.trip_id == trip_id)
                .order_by(Expense.date.asc()).all())
            voice_notes = (db.query(VoiceNote)
                .filter(VoiceNote.user_id == user_id, VoiceNote.trip_id == trip_id)
                .order_by(VoiceNote.created_at.asc()).limit(30).all())
            bookings = (db.query(Booking)
                .filter(Booking.user_id == user_id, Booking.trip_id == trip_id).all())
            alerts = []
        elif from_date:
            # Explicit date-range (e.g. a past trip the user returned from).
            start_iso, end_iso = from_date, (to_date or now_iso)
            reminders = (db.query(Reminder)
                .filter(Reminder.user_id == user_id, Reminder.datetime >= start_iso, Reminder.datetime <= end_iso)
                .order_by(Reminder.datetime.asc()).all())
            expenses = (db.query(Expense)
                .filter(Expense.user_id == user_id, Expense.date >= start_iso, Expense.date <= end_iso)
                .order_by(Expense.date.asc()).all())
            voice_notes = (db.query(VoiceNote)
                .filter(VoiceNote.user_id == user_id, VoiceNote.created_at >= start_iso, VoiceNote.created_at <= end_iso)
                .order_by(VoiceNote.created_at.asc()).limit(30).all())
            bookings = (db.query(Booking).filter(Booking.user_id == user_id)
                .order_by(Booking.travel_date.desc()).limit(5).all())
            alerts = (db.query(AlertCache)
                .filter(AlertCache.user_id == user_id, AlertCache.created_at >= start_iso, AlertCache.created_at <= end_iso)
                .order_by(AlertCache.created_at.desc()).limit(10).all())
        else:
            # Default: rolling N-day window (daily journal behaviour).
            reminders = (db.query(Reminder)
                .filter(Reminder.user_id == user_id, Reminder.datetime >= window_start_iso)
                .order_by(Reminder.datetime.asc()).all())
            expenses = (db.query(Expense)
                .filter(Expense.user_id == user_id, Expense.date >= window_start_iso)
                .order_by(Expense.date.asc()).all())
            voice_notes = (db.query(VoiceNote)
                .filter(VoiceNote.user_id == user_id, VoiceNote.created_at >= window_start_iso)
                .order_by(VoiceNote.created_at.asc()).limit(30).all())
            # Only recent/upcoming bookings — exclude past trips so an old booking
            # (e.g. a previous city) doesn't hijack today's summary narrative.
            bookings = (db.query(Booking)
                .filter(Booking.user_id == user_id, Booking.travel_date >= window_start_date)
                .order_by(Booking.travel_date.desc()).limit(5).all())
            alerts = (db.query(AlertCache)
                .filter(AlertCache.user_id == user_id, AlertCache.created_at >= window_start_iso)
                .order_by(AlertCache.created_at.desc()).limit(10).all())
    except Exception as e:
        logger.error(f"Error fetching diary data: {e}")
        reminders, expenses, voice_notes, bookings, alerts = [], [], [], [], []

    # ── 2. Resolve the diary's place ──────────────────────────────────────────
    # Prefer the journey/trip destination — that is what the entry is "about".
    # Only reverse-geocode the GPS position when there is no journey destination,
    # and request English names so local-language place names (e.g. Urdu) do not
    # leak into the English diary or its title.
    location = request.journey_to or trip_destination
    if not location and request.latitude and request.longitude:
        try:
            from geopy.geocoders import Nominatim
            geolocator = Nominatim(user_agent="travel_buddy_app")
            geo_result = await asyncio.to_thread(
                geolocator.reverse,
                f"{request.latitude},{request.longitude}",
                timeout=5,
                language="en",
            )
            location = geo_result.address if geo_result else location
        except Exception as geo_err:
            logger.warning(f"Geocoding failed: {geo_err}")
    if not location:
        location = "your destination"

    # ── 3. Build structured context sections ─────────────────────────────────
    sections: list[str] = []

    # Journey
    if request.journey_from or request.journey_to:
        j_line = "ACTIVE JOURNEY:"
        if request.journey_from and request.journey_to:
            j_line += f" {request.journey_from} → {request.journey_to}"
        elif request.journey_to:
            j_line += f" To {request.journey_to}"
        if request.journey_transport:
            j_line += f" | Mode: {request.journey_transport}"
        if request.journey_departure_time:
            j_line += f" | Departed: {request.journey_departure_time[:16]}"
        if request.journey_distance_km:
            j_line += f" | Distance: {request.journey_distance_km:.1f} km"
        if request.journey_duration_min:
            h, m = divmod(request.journey_duration_min, 60)
            j_line += f" | Travel time: {h}h {m}min" if h else f" | Travel time: {m} min"
        sections.append(j_line)

    # Bookings / packages
    if bookings:
        lines = ["TRAVEL PACKAGES / BOOKINGS:"]
        for b in bookings:
            line = f"  • {b.destination_name} with {b.agency_name}"
            line += f" — travel date: {b.travel_date}"
            if b.return_date:
                line += f" → {b.return_date}"
            line += f" | {b.num_people} person(s)"
            if b.status:
                line += f" | Status: {b.status}"
            lines.append(line)
        sections.append("\n".join(lines))

    # Tour reminders / voice reminders
    if reminders:
        lines = ["TOUR REMINDERS:"]
        for r in reminders:
            lines.append(f"  • {r.title} (scheduled: {(r.datetime or '')[:16]})")
        sections.append("\n".join(lines))

    # Voice notes (key travel observations spoken by the user)
    vn_texts = [v.transcript for v in voice_notes if v.transcript]
    if vn_texts:
        lines = ["VOICE NOTES (traveller's own words):"]
        for t in vn_texts[:10]:
            lines.append(f'  • "{t[:150]}"')
        sections.append("\n".join(lines))

    # Expenses
    if expenses:
        total = sum(e.amount for e in expenses)
        lines = [f"EXPENSES (total: PKR {total:,.0f}):"]
        for e in expenses:
            desc = f" — {e.description}" if e.description else ""
            lines.append(f"  • {e.category}: PKR {e.amount:,.0f}{desc}")
        sections.append("\n".join(lines))

    # Weather & news alerts
    if alerts:
        lines = ["WEATHER & TRAVEL ALERTS:"]
        for a in alerts:
            lines.append(f"  • [{a.type.upper()}] {a.message} (severity: {a.severity})")
        sections.append("\n".join(lines))

    full_context = "\n\n".join(sections) if sections else "No activities recorded."
    title_destination = request.journey_to or location.split(",")[0].strip() if location else date_str
    diary_title = f"Travel Diary — {title_destination}, {date_str}"

    # ── 4. AI compose comprehensive English diary ─────────────────────────────
    api_key = _get_openai_api_key()
    content: str = ""

    if api_key and api_key.startswith("sk-"):
        try:
            import openai
            client = openai.OpenAI(api_key=api_key, timeout=45.0)
            response = await asyncio.to_thread(
                client.chat.completions.create,
                model="gpt-4o-mini",
                messages=[
                    {
                        "role": "system",
                        "content": (
                            "You are a travel diary writer for a Pakistani travel companion app. "
                            "ALWAYS write in English. Create a vivid, personal, narrative diary entry "
                            "that reads like a real travel journal. Use first-person voice. Weave "
                            "ALL provided context naturally into the narrative — journey details, "
                            "reminders about tour events, expenses, voice note observations, "
                            "weather/alert conditions and travel package info. "
                            "Do NOT bullet-point data — write flowing paragraphs."
                        ),
                    },
                    {
                        "role": "user",
                        "content": (
                            f"Date: {date_str}\n"
                            f"Location: {location}\n\n"
                            f"{full_context}\n\n"
                            "Write a comprehensive travel diary entry in English (300-500 words). "
                            "Include: journey progress, tour highlights from reminders, "
                            "money spent and what it was for, observations from voice notes, "
                            "how the weather/alerts affected the journey, and travel package details. "
                            "Make it warm, descriptive and personal — as if the traveller wrote it themselves. "
                            "Do NOT include a title line, only the body paragraphs."
                        ),
                    },
                ],
                temperature=0.75,
                max_tokens=900,
            )
            content = response.choices[0].message.content.strip()
        except Exception as e:
            logger.warning(f"GPT diary generation failed: {e}")

    # Fallback to summarize_diary (which handles mock-mode / missing key gracefully)
    if not content:
        try:
            activity_lines = []
            if sections:
                activity_lines = [line for section in sections for line in section.split("\n") if line.strip()]
            summary_result = await summarize_diary([{
                "date": f"last_{days}_days",
                "activities": activity_lines or ["No activities recorded recently."],
            }])
            content = summary_result.get("total_summary", "")
        except Exception:
            pass

    # Last-resort template
    if not content or len(content.strip()) < 40:
        dest = request.journey_to or location.split(",")[0].strip() or "your destination"
        from_place = request.journey_from or "your starting point"
        transport_text = {
            "car": "by road", "bike": "by motorbike",
            "train": "by train", "flight": "by air",
        }.get(request.journey_transport or "", "")

        content_lines = [f"Today, {date_str}, marks another chapter in this travel story."]
        if request.journey_from and request.journey_to:
            content_lines.append(
                f"The journey from {from_place} to {dest} {transport_text} is underway."
            )
            if request.journey_distance_km:
                content_lines.append(
                    f"A distance of {request.journey_distance_km:.1f} km lies between the two points."
                )
        if bookings:
            b = bookings[0]
            content_lines.append(
                f"This trip to {b.destination_name} was arranged through {b.agency_name}, "
                f"with travel dates {b.travel_date}"
                + (f" to {b.return_date}" if b.return_date else "") + "."
            )
        if reminders:
            items = ", ".join(r.title for r in reminders[:3])
            content_lines.append(f"Key tour events noted: {items}.")
        if expenses:
            total = sum(e.amount for e in expenses)
            content_lines.append(f"Total spending recorded: PKR {total:,.0f}.")
        if vn_texts:
            content_lines.append(f'A voice note reads: "{vn_texts[0][:100]}".')
        if alerts:
            content_lines.append(
                f"Travel alert: {alerts[0].message[:120]}."
            )
        content_lines.append(
            "Add reminders, voice notes and expenses to enrich future AI diary entries."
        )
        content = " ".join(content_lines)

    # ── 5. Persist ────────────────────────────────────────────────────────────
    try:
        db_entry = DiaryEntry(
            user_id=user_id,
            title=diary_title,
            content=content,
            location=location,
            destination_name=request.journey_to or trip_destination or None,
            timestamp=now_iso,
            is_auto_generated=True,
            trip_id=trip_id,
        )
        db.add(db_entry)
        db.commit()
        db.refresh(db_entry)
        return db_entry
    except Exception as e:
        logger.error(f"Error saving AI diary entry: {e}")
        try:
            db.rollback()
        except Exception:
            pass
        try:
            try:
                from ..database import SessionLocal
            except ImportError:
                from database import SessionLocal
            fallback_db = SessionLocal()
            db_entry = DiaryEntry(
                user_id=user_id,
                title=diary_title,
                content=content or "Diary could not be saved — please try again.",
                location=location,
                timestamp=now_iso,
                is_auto_generated=True,
            )
            fallback_db.add(db_entry)
            fallback_db.commit()
            fallback_db.refresh(db_entry)
            fallback_db.close()
            return db_entry
        except Exception as fallback_err:
            logger.error(f"Fallback diary save also failed: {fallback_err}")
            raise RuntimeError(f"Could not save diary entry: {fallback_err}") from fallback_err


def get_diary_entries(db: Session, user_id: str = "default") -> List[DiaryEntry]:
    """GET /api/diary."""
    return db.query(DiaryEntry).filter(DiaryEntry.user_id == user_id).order_by(DiaryEntry.timestamp.desc()).all()


def get_diary_summary(db: Session, user_id: str = "default") -> Dict:
    """GET /api/diary/summary."""
    entries = (
        db.query(DiaryEntry)
        .filter(DiaryEntry.user_id == user_id)
        .order_by(DiaryEntry.timestamp.desc())
        .all()
    )
    total_entries = len(entries)
    auto_gen_count = sum(1 for e in entries if e.is_auto_generated)
    manual_count = total_entries - auto_gen_count
    return {
        "total_entries": total_entries,
        "auto_generated": auto_gen_count,
        "manual_entries": manual_count,
        "last_entry_at": entries[0].timestamp if entries else None
    }


def update_entry(db: Session, entry_id: int, update: DiaryUpdateRequest, user_id: str) -> Optional[DiaryEntry]:
    """PUT /api/diary/{id}: Update diary entry only if it belongs to user_id."""
    entry = (
        db.query(DiaryEntry)
        .filter(DiaryEntry.id == entry_id, DiaryEntry.user_id == user_id)
        .first()
    )
    if not entry:
        return None
    if update.content is not None:
        entry.content = update.content
    if update.title is not None:
        entry.title = update.title
    if update.location is not None:
        entry.location = update.location
    if update.imageUrl is not None:
        entry.imageUrl = update.imageUrl
    if update.destination_name is not None:
        entry.destination_name = update.destination_name
    db.commit()
    db.refresh(entry)
    return entry


def delete_entry(db: Session, entry_id: int, user_id: str) -> bool:
    """DELETE /api/diary/{id}: Delete only if it belongs to user_id."""
    entry = (
        db.query(DiaryEntry)
        .filter(DiaryEntry.id == entry_id, DiaryEntry.user_id == user_id)
        .first()
    )
    if entry:
        db.delete(entry)
        db.commit()
        return True
    return False


async def generate_trip_diary(
    db: Session,
    user_id: str,
    destination_name: str,
    from_date: str,
    return_date: Optional[str],
    notes: Optional[str],
    booking_id: Optional[int] = None,
) -> DiaryEntry:
    """POST /api/diary/trip-diary: Generate a trip-specific diary for a destination."""
    now_iso = now_utc_iso()

    # Calculate trip duration from dates
    trip_days = 1
    try:
        from_dt = datetime.fromisoformat(from_date)
        if return_date:
            to_dt = datetime.fromisoformat(return_date)
            trip_days = max(1, (to_dt - from_dt).days + 1)
    except Exception:
        pass

    duration_text = f"{trip_days} day{'s' if trip_days != 1 else ''}"
    title = f"{destination_name} Trip Diary"

    # Resolve the trip this diary belongs to so real records can be woven in.
    resolved_trip_id = None
    try:
        try:
            from .trip_service import get_trips_for_user, find_trips_by_name
        except ImportError:
            from services.trip_service import get_trips_for_user, find_trips_by_name
        if booking_id is not None:
            for _t in get_trips_for_user(db, user_id):
                if getattr(_t, "booking_id", None) == booking_id:
                    resolved_trip_id = _t.id
                    break
        if resolved_trip_id is None:
            _named = find_trips_by_name(db, user_id, destination_name)
            if _named:
                resolved_trip_id = _named[0].id
    except Exception:
        pass

    # Gather REAL records for this trip (by trip_id when known, else by date range).
    trip_expenses, trip_reminders, trip_notes = [], [], []
    try:
        if resolved_trip_id is not None:
            trip_expenses = db.query(Expense).filter(Expense.user_id == user_id, Expense.trip_id == resolved_trip_id).all()
            trip_reminders = db.query(Reminder).filter(Reminder.user_id == user_id, Reminder.trip_id == resolved_trip_id).all()
            trip_notes = db.query(VoiceNote).filter(VoiceNote.user_id == user_id, VoiceNote.trip_id == resolved_trip_id).all()
        elif from_date:
            end_iso = return_date or now_iso
            trip_expenses = db.query(Expense).filter(Expense.user_id == user_id, Expense.date >= from_date, Expense.date <= end_iso).all()
            trip_reminders = db.query(Reminder).filter(Reminder.user_id == user_id, Reminder.datetime >= from_date, Reminder.datetime <= end_iso).all()
            trip_notes = db.query(VoiceNote).filter(VoiceNote.user_id == user_id, VoiceNote.created_at >= from_date, VoiceNote.created_at <= end_iso).all()
    except Exception as _rec_err:
        logger.warning(f"trip diary record fetch failed: {_rec_err}")

    # Try AI summarizer with destination context
    summary_text = ""
    try:
        activities_context = [
            f"Trip destination: {destination_name}, Pakistan",
            f"Duration: {duration_text}",
            f"Travel dates: {from_date}" + (f" to {return_date}" if return_date else ""),
        ]
        if trip_expenses:
            _tot = sum(float(e.amount or 0) for e in trip_expenses)
            activities_context.append(f"Total spent: PKR {_tot:,.0f} across {len(trip_expenses)} expense(s)")
            for e in trip_expenses[:12]:
                _where = f" at {e.merchant}" if getattr(e, 'merchant', None) else ""
                activities_context.append(f"Spent PKR {float(e.amount or 0):,.0f} on {e.category}{_where}: {e.description or ''}")
        if trip_reminders:
            activities_context.append("Tour reminders: " + ", ".join(r.title for r in trip_reminders[:8]))
        if trip_notes:
            for n in trip_notes[:6]:
                if n.transcript:
                    activities_context.append(f"Voice note: {n.transcript[:160]}")
        if notes:
            activities_context.append(f"Traveller notes: {notes}")

        summary_result = await summarize_diary([{
            "date": from_date,
            "activities": activities_context,
        }])
        summary_text = summary_result.get("total_summary", "")
    except Exception as ai_err:
        logger.warning(f"AI summarizer unavailable for trip diary: {ai_err}")

    # Use AI content if substantial, otherwise fall back to rich template
    if summary_text and len(summary_text.strip()) > 80:
        content = summary_text
    else:
        content = _build_trip_diary_template(
            destination=destination_name,
            from_date=from_date,
            return_date=return_date,
            trip_days=trip_days,
            notes=notes,
        )

    try:
        db_entry = DiaryEntry(
            user_id=user_id,
            title=title,
            content=content,
            location=destination_name,
            destination_name=destination_name,
            timestamp=now_iso,
            is_auto_generated=True,
            imageUrl=None,
            trip_id=resolved_trip_id,
        )
        db.add(db_entry)
        db.commit()
        db.refresh(db_entry)
        return db_entry
    except Exception as e:
        logger.error(f"Error saving trip diary entry: {e}")
        db.rollback()
        raise


def _build_trip_diary_template(
    destination: str,
    from_date: str,
    return_date: Optional[str],
    trip_days: int,
    notes: Optional[str],
) -> str:
    """Build a rich structured template for a trip diary when AI is unavailable."""
    duration_text = f"{trip_days} day{'s' if trip_days != 1 else ''}"
    date_line = from_date
    if return_date:
        date_line = f"{from_date} → {return_date}"

    personal_reflection = (
        notes.strip()
        if notes and notes.strip()
        else f"Update this section with your personal memories from {destination} — the moments that made this trip unforgettable."
    )

    return f"""A {duration_text} adventure to {destination}, Pakistan.

📅 Travel Dates: {date_line}

✈️ Getting There
The journey to {destination} began with excitement and anticipation. Pakistan's landscapes never fail to amaze, and {destination} is one of those destinations that stays with you long after you return home.

🏔️ The Experience
{destination} offered everything a traveller could hope for — breathtaking scenery, warm hospitality, and moments of genuine wonder. Every corner of {destination} has a story to tell, from its natural landscapes to its rich culture and history.

📸 Highlights
• Exploring the most iconic spots in {destination}
• Connecting with local people and experiencing the authentic culture
• Capturing memories through photos
• Tasting the local cuisine and street food
• Taking in the views that {destination} is famous for

💭 Personal Reflections
{personal_reflection}

⭐ Final Thoughts
{destination} is a destination that deserves a place on every Pakistani traveller's list. The memories from this trip will last a lifetime. Edit this diary to add your own photos and personal moments to make it truly yours."""


async def create_booking_journey_diary(db: Session, user_id: str, booking) -> DiaryEntry:
    """Auto-create a focused journey diary when a booking is confirmed.

    Records only the journey essentials (from/to, travel dates, location) and
    summarises reminders, voice notes and expenses from the exact travel date.
    """
    now_iso = now_utc_iso()
    travel_date = booking.travel_date  # e.g. "2026-06-15"
    return_date = booking.return_date

    # Build date window for the travel date (midnight-to-midnight)
    date_window_start = f"{travel_date}T00:00:00"
    date_window_end = f"{travel_date}T23:59:59"

    # Collect reminders, voice notes, and expenses on the exact travel date
    try:
        reminders_on_date = (
            db.query(Reminder)
            .filter(
                Reminder.user_id == user_id,
                Reminder.datetime >= date_window_start,
                Reminder.datetime <= date_window_end,
            )
            .order_by(Reminder.datetime.asc())
            .all()
        )
        expenses_on_date = (
            db.query(Expense)
            .filter(
                Expense.user_id == user_id,
                Expense.date >= date_window_start,
                Expense.date <= date_window_end,
            )
            .order_by(Expense.date.asc())
            .all()
        )
        voice_notes_on_date = (
            db.query(VoiceNote)
            .filter(
                VoiceNote.user_id == user_id,
                VoiceNote.created_at >= date_window_start,
                VoiceNote.created_at <= date_window_end,
            )
            .order_by(VoiceNote.created_at.asc())
            .limit(10)
            .all()
        )
    except Exception:
        reminders_on_date, expenses_on_date, voice_notes_on_date = [], [], []

    # Format travel dates
    try:
        from_dt = datetime.fromisoformat(travel_date)
        date_display = from_dt.strftime("%B %d, %Y at %I:%M %p")
    except Exception:
        date_display = travel_date

    date_range = travel_date
    if return_date:
        date_range = f"{travel_date} → {return_date}"

    title = f"Journey to {booking.destination_name} — {travel_date}"

    # Build the journey block (always included, focused only on journey info)
    journey_block = (
        f"Journey: {booking.destination_name}\n"
        f"Travel Date: {travel_date}\n"
    )
    if return_date:
        journey_block += f"Return Date: {return_date}\n"
    journey_block += f"Agency: {booking.agency_name}\n"
    journey_block += f"Travelers: {booking.num_people}"

    # Build date-specific context for reminders, voice notes, expenses
    context_parts = [f"JOURNEY INFO:\n{journey_block}"]

    if reminders_on_date:
        lines = ["REMINDERS ON THIS DATE:"]
        for r in reminders_on_date:
            lines.append(f"  • {r.title} (at {(r.datetime or '')[:16]})")
        context_parts.append("\n".join(lines))

    vn_transcripts = [v.transcript for v in voice_notes_on_date if v.transcript]
    if vn_transcripts:
        lines = ["VOICE NOTES:"]
        for t in vn_transcripts[:5]:
            lines.append(f'  • "{t[:150]}"')
        context_parts.append("\n".join(lines))

    if expenses_on_date:
        total = sum(e.amount for e in expenses_on_date)
        lines = [f"EXPENSES (PKR {total:,.0f} total):"]
        for e in expenses_on_date:
            desc = f" — {e.description}" if e.description else ""
            lines.append(f"  • {e.category}: PKR {e.amount:,.0f}{desc}")
        context_parts.append("\n".join(lines))

    full_context = "\n\n".join(context_parts)

    # Try AI to compose a focused journey diary entry
    api_key = _get_openai_api_key()
    content = ""

    if api_key and api_key.startswith("sk-"):
        try:
            import openai
            client = openai.OpenAI(api_key=api_key, timeout=30.0)
            response = await asyncio.to_thread(
                client.chat.completions.create,
                model="gpt-4o-mini",
                messages=[
                    {
                        "role": "system",
                        "content": (
                            "You are a travel diary writer. Write a short, focused diary entry "
                            "about the START of a journey. ALWAYS write in English. "
                            "Include ONLY the journey essentials: destination, travel dates, "
                            "and a brief summary of any reminders, voice notes or expenses "
                            "recorded on the travel date. Keep it concise (100-200 words). "
                            "Do NOT pad with generic travel descriptions."
                        ),
                    },
                    {
                        "role": "user",
                        "content": (
                            f"{full_context}\n\n"
                            "Write a focused journey diary entry in English. "
                            "Mention the destination, travel date(s), and summarise "
                            "any reminders, voice notes, and expenses from this date. "
                            "Write only the diary body — no separate title line."
                        ),
                    },
                ],
                temperature=0.65,
                max_tokens=400,
            )
            content = response.choices[0].message.content.strip()
        except Exception as ai_err:
            logger.warning(f"Journey diary AI failed: {ai_err}")

    # Fallback: structured plain-text entry
    if not content or len(content.strip()) < 40:
        lines = [f"New journey started to {booking.destination_name}."]
        lines.append(f"Travel date: {date_range}.")
        if reminders_on_date:
            items = ", ".join(r.title for r in reminders_on_date[:3])
            lines.append(f"Reminders for this date: {items}.")
        if vn_transcripts:
            lines.append(f'Voice note: "{vn_transcripts[0][:120]}".')
        if expenses_on_date:
            total = sum(e.amount for e in expenses_on_date)
            lines.append(f"Expenses recorded today: PKR {total:,.0f}.")
        content = " ".join(lines)

    db_entry = DiaryEntry(
        user_id=user_id,
        title=title,
        content=content,
        location=booking.destination_name,
        destination_name=booking.destination_name,
        timestamp=now_iso,
        is_auto_generated=True,
    )
    db.add(db_entry)
    db.commit()
    db.refresh(db_entry)
    return db_entry


async def generate_voice_diary(db: Session, user_id: str, audio_file) -> DiaryEntry:
    """POST /api/diary/voice: Transcribe audio → AI composes English diary entry.

    Also incorporates recent tour reminders and voice notes as context so the
    entry reflects the traveller's full day, not just the recorded snippet.
    """
    from ai.inference.stt_pipeline.transcriber import transcribe_audio

    now_iso = now_utc_iso()
    now_dt = datetime.now()
    date_str = now_dt.strftime("%B %d, %Y")
    window_start = (now_dt - timedelta(hours=24)).isoformat()

    # ── 1. Transcribe ──────────────────────────────────────────────────────────
    stt_result = await transcribe_audio(audio_file, language="en", use_fallback=True)
    transcript = (stt_result.get("transcript") or "").strip()

    if not transcript:
        db_entry = DiaryEntry(
            user_id=user_id,
            title=f"Voice Diary — {date_str}",
            content="Your voice recording could not be transcribed. Please try again in a quiet environment.",
            timestamp=now_iso,
            is_auto_generated=True,
        )
        db.add(db_entry)
        db.commit()
        db.refresh(db_entry)
        return db_entry

    # ── 2. Gather recent context (reminders + voice notes from last 24 h) ─────
    recent_reminders = (
        db.query(Reminder)
        .filter(Reminder.user_id == user_id, Reminder.datetime >= window_start)
        .order_by(Reminder.datetime.asc())
        .limit(5)
        .all()
    )
    recent_voice_notes = (
        db.query(VoiceNote)
        .filter(VoiceNote.user_id == user_id, VoiceNote.created_at >= window_start)
        .order_by(VoiceNote.created_at.desc())
        .limit(5)
        .all()
    )

    context_lines = [f"Voice recording: {transcript}"]
    for r in recent_reminders:
        context_lines.append(f"Tour reminder: {r.title} (scheduled: {r.datetime})")
    for v in recent_voice_notes:
        if v.transcript:
            context_lines.append(f"Voice note: {v.transcript[:120]}")

    # ── 3. AI compose diary entry in English ──────────────────────────────────
    api_key = _get_openai_api_key()
    content = transcript  # raw-transcript fallback

    if api_key and api_key.startswith("sk-"):
        try:
            import openai
            client = openai.OpenAI(api_key=api_key, timeout=30.0)
            context_str = "\n".join(context_lines)

            response = await asyncio.to_thread(
                client.chat.completions.create,
                model="gpt-4o-mini",
                messages=[
                    {
                        "role": "system",
                        "content": (
                            "You are a travel diary writer. Create vivid, engaging diary entries "
                            "from voice recordings. Write ONLY in English regardless of the input "
                            "language. Analyse tour reminders, weather cues, and voice notes in the "
                            "context to enrich the narrative. Tone: warm, personal, descriptive."
                        ),
                    },
                    {
                        "role": "user",
                        "content": (
                            f"Date: {date_str}\n\n"
                            f"Context:\n{context_str}\n\n"
                            "Write a travel diary entry in English based on this voice recording. "
                            "Weave in any relevant tour reminders, weather conditions, or travel alerts "
                            "mentioned in the context. Write 2-4 paragraphs (150-300 words). "
                            "Write only the diary body — no separate title line needed."
                        ),
                    },
                ],
                temperature=0.75,
                max_tokens=600,
            )
            content = response.choices[0].message.content.strip()
        except Exception as e:
            logger.warning(f"Voice diary AI composition failed: {e}")
            content = transcript

    # ── 4. Persist ────────────────────────────────────────────────────────────
    try:
        db_entry = DiaryEntry(
            user_id=user_id,
            title=f"Voice Diary — {date_str}",
            content=content,
            timestamp=now_iso,
            is_auto_generated=True,
        )
        db.add(db_entry)
        db.commit()
        db.refresh(db_entry)
        return db_entry
    except Exception as e:
        logger.error(f"Error saving voice diary entry: {e}")
        db.rollback()
        raise


def export_diary(db: Session, fmt: str, user_id: Optional[str] = None) -> str:
    """
    GET /api/diary/export?format=pdf|docx
    Returns the file path of the generated export file, scoped to user_id.
    """
    query = db.query(DiaryEntry).order_by(DiaryEntry.timestamp.asc())
    if user_id:
        query = query.filter(DiaryEntry.user_id == user_id)
    entries = query.all()

    # Ensure export directory exists
    Path(EXPORT_DIR).mkdir(parents=True, exist_ok=True)

    if fmt.lower() == "docx":
        return _export_docx(entries, user_id=user_id)
    else:
        return _export_pdf(entries, user_id=user_id)


def _export_pdf(entries: List[DiaryEntry], user_id: Optional[str] = None) -> str:
    """Generate PDF using reportlab, scoped to a specific user."""
    from reportlab.lib.pagesizes import A4
    from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer
    from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
    from reportlab.lib.units import cm

    safe_uid = (user_id or "shared").replace("/", "_")[:32]
    ts = datetime.utcnow().strftime("%Y%m%d_%H%M%S_%f")
    file_path = os.path.join(EXPORT_DIR, f"travel_diary_{safe_uid}_{ts}.pdf")
    doc = SimpleDocTemplate(file_path, pagesize=A4,
                            leftMargin=2*cm, rightMargin=2*cm,
                            topMargin=2*cm, bottomMargin=2*cm)
    styles = getSampleStyleSheet()
    title_style = ParagraphStyle('Title', parent=styles['Title'], fontSize=18, spaceAfter=12)
    heading_style = ParagraphStyle('Heading', parent=styles['Heading2'], fontSize=12, spaceAfter=6)
    body_style = styles['BodyText']

    story = [Paragraph("Travel Diary", title_style), Spacer(1, 0.5*cm)]

    for entry in entries:
        story.append(Paragraph(entry.title, heading_style))
        story.append(Paragraph(f"📅 {entry.timestamp[:10]}", body_style))
        if entry.location:
            story.append(Paragraph(f"📍 {entry.location}", body_style))
        story.append(Spacer(1, 0.2*cm))
        # Escape HTML characters for reportlab
        content = entry.content.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')
        story.append(Paragraph(content, body_style))
        story.append(Spacer(1, 0.5*cm))

    doc.build(story)
    return file_path


def _export_docx(entries: List[DiaryEntry], user_id: Optional[str] = None) -> str:
    """Generate DOCX using python-docx, scoped to a specific user."""
    from docx import Document
    from docx.shared import Pt

    safe_uid = (user_id or "shared").replace("/", "_")[:32]
    ts = datetime.utcnow().strftime("%Y%m%d_%H%M%S_%f")
    file_path = os.path.join(EXPORT_DIR, f"travel_diary_{safe_uid}_{ts}.docx")
    doc = Document()
    doc.add_heading("Travel Diary", 0)

    for entry in entries:
        doc.add_heading(entry.title, level=2)
        doc.add_paragraph(f"Date: {entry.timestamp[:10]}")
        if entry.location:
            doc.add_paragraph(f"Location: {entry.location}")
        doc.add_paragraph(entry.content)
        doc.add_paragraph("")  # Spacer

    doc.save(file_path)
    return file_path
