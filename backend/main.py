"""
Travel Buddy AI - FastAPI Backend Application
Main entry point for the backend API server.
"""

import sys
import os
import re
import logging
import uvicorn
from pathlib import Path

# Add project root to path so `ai/` package is always resolvable
_PROJECT_ROOT = Path(__file__).resolve().parent.parent
if str(_PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(_PROJECT_ROOT))

from contextlib import asynccontextmanager
from fastapi import FastAPI, HTTPException, Request, Depends, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse, Response
from sqlalchemy import inspect, text
import requests
try:
    from .auth import get_current_user
    from .config import settings
    from .database import Base, engine
    from .models import reminder, expense, voice_note, diary_entry, alert_cache, rag_embedding, decision_review, chat_conversation, chat_message, booking, trip
except ImportError:
    from auth import get_current_user
    from config import settings
    from database import Base, engine
    from models import reminder, expense, voice_note, diary_entry, alert_cache, rag_embedding, decision_review, chat_conversation, chat_message, booking, trip

try:
    # Preferred package-safe imports when running via `uvicorn backend.main:app`
    from .routes import reminders, voice_notes, diary, expenses, alerts, intent, chat, bookings, trips
except ImportError:
    # Backward-compatible fallback for direct execution contexts
    from routes import reminders, voice_notes, diary, expenses, alerts, intent, chat, bookings, trips

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)
_AUTH_BYPASS_ALLOWED_ENVS = {"development", "dev", "test", "testing", "local"}


def _ensure_user_indexes() -> None:
    """Backfill local SQLite schema drift and ensure safe indexes if tables exist."""
    with engine.begin() as conn:
        if conn.dialect.name == "sqlite":
            _repair_legacy_sqlite_schema(conn)

        index_specs = [
            ("ix_trips_user_id", "trips", ["user_id"]),
            ("ix_trips_status", "trips", ["status"]),
            ("ix_trips_start_date", "trips", ["start_date"]),
            ("ix_expenses_trip_id", "expenses", ["trip_id"]),
            ("ix_reminders_trip_id", "reminders", ["trip_id"]),
            ("ix_voice_notes_trip_id", "voice_notes", ["trip_id"]),
            ("ix_diary_entries_trip_id", "diary_entries", ["trip_id"]),
            ("ix_bookings_trip_id", "bookings", ["trip_id"]),
            ("ix_reminders_user_id", "reminders", ["user_id"]),
            ("ix_expenses_user_id", "expenses", ["user_id"]),
            ("ix_diary_entries_user_id", "diary_entries", ["user_id"]),
            ("ix_voice_notes_user_id", "voice_notes", ["user_id"]),
            ("ix_alert_cache_user_id", "alert_cache", ["user_id"]),
            ("ix_rag_embeddings_user_id", "rag_embeddings", ["user_id"]),
            ("ix_decision_reviews_user_id", "decision_reviews", ["user_id"]),
            ("ix_chat_conversations_user_id", "chat_conversations", ["user_id"]),
            ("ix_chat_conversations_updated_at", "chat_conversations", ["updated_at"]),
            ("ix_chat_messages_conversation_id", "chat_messages", ["conversation_id"]),
            ("ix_chat_messages_user_id", "chat_messages", ["user_id"]),
        ]
        _create_indexes_if_possible(conn, index_specs)


def _repair_legacy_sqlite_schema(conn) -> None:
    """Local-only repair path for older SQLite demo databases."""
    inspector = inspect(conn)

    def _table_exists(name: str) -> bool:
        return inspector.has_table(name)

    def _columns(table: str) -> set[str]:
        if not _table_exists(table):
            return set()
        return {col["name"] for col in inspector.get_columns(table)}

    def _add_column_if_missing(table: str, column: str, ddl_type: str) -> None:
        if _table_exists(table) and column not in _columns(table):
            conn.execute(text(f"ALTER TABLE {table} ADD COLUMN {column} {ddl_type}"))

    _add_column_if_missing("alert_cache", "user_id", "TEXT")
    _add_column_if_missing("diary_entries", "destination_name", "TEXT")
    _add_column_if_missing("bookings", "user_email", "TEXT")

    conn.execute(text(
        """
        CREATE TABLE IF NOT EXISTS trips (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id TEXT NOT NULL,
            destination TEXT NOT NULL,
            origin TEXT,
            start_date TEXT NOT NULL,
            end_date TEXT,
            status TEXT NOT NULL DEFAULT 'active',
            transport TEXT,
            notes TEXT,
            booking_id INTEGER,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        )
        """
    ))

    _add_column_if_missing("expenses", "trip_id", "INTEGER")
    _add_column_if_missing("expenses", "location", "TEXT")
    _add_column_if_missing("expenses", "merchant", "TEXT")
    _add_column_if_missing("reminders", "trip_id", "INTEGER")
    _add_column_if_missing("voice_notes", "trip_id", "INTEGER")
    _add_column_if_missing("voice_notes", "location", "TEXT")
    _add_column_if_missing("diary_entries", "trip_id", "INTEGER")
    _add_column_if_missing("bookings", "trip_id", "INTEGER")


def _create_indexes_if_possible(conn, index_specs: list[tuple[str, str, list[str]]]) -> None:
    inspector = inspect(conn)
    table_names = set(inspector.get_table_names())

    for index_name, table_name, columns in index_specs:
        if table_name not in table_names:
            continue
        existing_columns = {col["name"] for col in inspector.get_columns(table_name)}
        if not set(columns).issubset(existing_columns):
            continue
        cols_sql = ", ".join(columns)
        conn.execute(text(f"CREATE INDEX IF NOT EXISTS {index_name} ON {table_name} ({cols_sql})"))


@asynccontextmanager
async def lifespan(_app: FastAPI):
    """Startup: validate config and create DB tables. Shutdown: no-op."""
    # C-2: Prevent AUTH_BYPASS from being active outside explicit local/test envs.
    auth_bypass = os.getenv("AUTH_BYPASS", "false").strip().lower() in {"1", "true", "yes", "on"}
    env = os.getenv("ENVIRONMENT", "development").strip().lower()
    if auth_bypass and env not in _AUTH_BYPASS_ALLOWED_ENVS:
        raise RuntimeError(
            "FATAL: AUTH_BYPASS=true is only allowed when ENVIRONMENT is one of "
            f"{sorted(_AUTH_BYPASS_ALLOWED_ENVS)}. Disable AUTH_BYPASS before deploying."
        )

    # CORS hardening: require explicit origins outside local/test environments.
    raw_origins = os.getenv("ALLOWED_ORIGINS", "").strip()
    if env not in _AUTH_BYPASS_ALLOWED_ENVS:
        if not raw_origins:
            raise RuntimeError(
                "FATAL: ALLOWED_ORIGINS must be explicitly set in non-local environments."
            )
        parsed_origins = [o.strip() for o in raw_origins.split(",") if o.strip()]
        if not parsed_origins:
            raise RuntimeError(
                "FATAL: ALLOWED_ORIGINS is set but empty after parsing."
            )
        if "*" in parsed_origins:
            raise RuntimeError(
                "FATAL: Wildcard '*' is not allowed in ALLOWED_ORIGINS for non-local environments."
            )

    # Keep SQLAlchemy create_all for local/test convenience, but avoid schema drift
    # in non-local environments where Alembic migrations should be authoritative.
    raw_auto_create = os.getenv("AUTO_CREATE_TABLES", "").strip().lower()
    if raw_auto_create:
        auto_create_tables = raw_auto_create in {"1", "true", "yes", "on"}
    else:
        auto_create_tables = env in _AUTH_BYPASS_ALLOWED_ENVS

    if auto_create_tables:
        Base.metadata.create_all(bind=engine)

    _ensure_user_indexes()

    # Eagerly initialise Firebase Admin once, single-threaded, before any request
    # can arrive. This removes the cold-start race where the dashboard's parallel
    # requests each tried to initialise Firebase and intermittently got a 503.
    if not auth_bypass:
        try:
            from .auth import init_firebase_at_startup
        except ImportError:
            from auth import init_firebase_at_startup
        init_firebase_at_startup()

    logger.info(
        "startup_complete",
        extra={
            "auth_bypass": auth_bypass,
            "environment": env,
            "auto_create_tables": auto_create_tables,
        },
    )
    yield


# --- App Initialization ---
app = FastAPI(
    title="Travel Buddy AI API",
    description="Backend API for Travel Buddy AI - FYP",
    version="1.0.0",
    lifespan=lifespan,
)

# --- CORS Middleware ---
_raw_origins = os.getenv("ALLOWED_ORIGINS", "").strip()
_allowed_origins: list[str] = (
    [o.strip() for o in _raw_origins.split(",") if o.strip()]
    if _raw_origins
    else ["http://localhost", "http://localhost:8080", "http://127.0.0.1"]
)
app.add_middleware(
    CORSMiddleware,
    allow_origins=_allowed_origins,
    allow_origin_regex=r"https?://(localhost|127\.0\.0\.1)(:\d+)?",
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# --- Register all Routers ---
app.include_router(reminders.router,  prefix="/api/reminders",   tags=["Reminders"], dependencies=[Depends(get_current_user)])
app.include_router(voice_notes.router,prefix="/api/voice-notes", tags=["Voice Notes"], dependencies=[Depends(get_current_user)])
app.include_router(diary.router,      prefix="/api/diary",       tags=["Travel Diary"], dependencies=[Depends(get_current_user)])
app.include_router(expenses.router,   prefix="/api/expenses",    tags=["Expenses"], dependencies=[Depends(get_current_user)])
app.include_router(alerts.router,     prefix="/api/alerts",      tags=["Alerts"], dependencies=[Depends(get_current_user)])
app.include_router(intent.router,     prefix="/api/intent",      tags=["Intent"], dependencies=[Depends(get_current_user)])
app.include_router(chat.router,       prefix="/api/chat",        tags=["Chat"], dependencies=[Depends(get_current_user)])
app.include_router(bookings.router,   prefix="/api/bookings",    tags=["Bookings"], dependencies=[Depends(get_current_user)])
app.include_router(trips.router,      prefix="/api/trips",       tags=["Trips"], dependencies=[Depends(get_current_user)])


# --- Global Exception Handler (prevents traceback leaks) ---
@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    """Catch-all exception handler to prevent leaking internal error details."""
    logger.error(f"GLOBAL ERROR: {exc}", exc_info=True)
    return JSONResponse(
        status_code=500,
        content={"detail": "An internal server error occurred. Our team has been notified."},
    )


# --- Health & Root Endpoints ---
@app.get("/")
async def root():
    """Root endpoint."""
    return {"message": "Travel Buddy AI API", "version": "1.0.0", "status": "running"}


@app.get("/health")
async def health_check():
    """Health check endpoint."""
    return {"status": "healthy"}


@app.get("/api/destination-photo")
async def destination_photo(
    location: str = Query(..., min_length=2, max_length=160),
    width: int = Query(900, ge=320, le=1200),
    height: int = Query(700, ge=240, le=1200),
):
    """Proxy exact Google Street View location photos without exposing the API key."""
    if not settings.GOOGLE_MAPS_API_KEY:
        raise HTTPException(status_code=503, detail="Google Maps API key is not configured")

    params = {
        "size": f"{width}x{height}",
        "location": location,
        "fov": "80",
        "heading": "235",
        "pitch": "5",
        "return_error_code": "true",
        "key": settings.GOOGLE_MAPS_API_KEY,
    }
    try:
        google_response = requests.get(
            "https://maps.googleapis.com/maps/api/streetview",
            params=params,
            timeout=8,
        )
    except requests.RequestException as exc:
        logger.warning("destination_photo_fetch_failed: %s", exc)
        raise HTTPException(status_code=502, detail="Unable to fetch destination photo") from exc

    if google_response.status_code != 200:
        raise HTTPException(status_code=google_response.status_code, detail="Destination photo is unavailable")

    return Response(
        content=google_response.content,
        media_type=google_response.headers.get("content-type", "image/jpeg"),
        headers={"Cache-Control": "public, max-age=86400"},
    )


# --- Secure File Serving ---
def _is_safe_filename(name: str) -> bool:
    """Allow only alphanumeric, underscore, hyphen, dot; no path traversal."""
    if not name or len(name) > 200:
        return False
    return bool(re.match(r"^[\w\-.]+\.[a-z]+$", name))


def _expected_export_prefix(user_id: str) -> str:
    """Build the per-user export filename prefix used by diary exports."""
    safe_uid = (user_id or "").replace("/", "_")[:32]
    return f"travel_diary_{safe_uid}_"


@app.get("/files/{filename}")
async def serve_diary_file(
    filename: str,
    current_user=Depends(get_current_user),
):
    """Serve a generated diary file (PDF or DOCX)."""
    FILES_DIR = os.getenv("DIARY_FILES_DIR", "diary_files")
    if not _is_safe_filename(filename):
        raise HTTPException(status_code=400, detail="Invalid filename")

    # Enforce per-user ownership for generated export files.
    expected_prefix = _expected_export_prefix(getattr(current_user, "uid", ""))
    if not filename.startswith(expected_prefix):
        raise HTTPException(status_code=403, detail="Access denied")

    path = Path(FILES_DIR) / filename
    if not path.exists() or not path.is_file():
        raise HTTPException(status_code=404, detail="File not found")
    media_type = (
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        if filename.lower().endswith(".docx")
        else "application/pdf"
    )
    return FileResponse(path, media_type=media_type, filename=filename)


if __name__ == "__main__":
    uvicorn.run("backend.main:app", host="0.0.0.0", port=8000, reload=True)
