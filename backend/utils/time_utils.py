"""Timezone-safe datetime helpers (UTC-first storage)."""

from datetime import datetime, timedelta, timezone
from typing import Optional

# Pakistan Standard Time is a fixed UTC+5 offset year-round (no daylight saving),
# so a static timezone is exact and avoids any tz-database dependency. This app
# is Pakistan-specific, so PKT is the canonical default for resolving any
# relative time when the client does not supply its own local time.
PAKISTAN_TZ = timezone(timedelta(hours=5))


def now_utc_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def now_pakistan() -> datetime:
    """Current time in Pakistan Standard Time (UTC+5, no DST)."""
    return datetime.now(PAKISTAN_TZ)


def to_utc_iso(value: str | datetime) -> str:
    if isinstance(value, datetime):
        dt = value
    else:
        dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    else:
        dt = dt.astimezone(timezone.utc)
    return dt.isoformat()


def parse_utc_datetime(value: str | datetime | None) -> Optional[datetime]:
    if value is None:
        return None
    if isinstance(value, datetime):
        dt = value
    else:
        dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)
