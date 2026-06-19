"""Authentication and user-context dependencies."""

import base64
import binascii
import json
import logging
import os
import threading
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Optional

from fastapi import Header, HTTPException, status
from firebase_admin import auth as firebase_auth
from firebase_admin import credentials, initialize_app

try:
    from .config import settings
except ImportError:
    from config import settings

logger = logging.getLogger(__name__)


@dataclass
class AuthenticatedUser:
    uid: str
    email: Optional[str] = None
    name: Optional[str] = None


_BACKEND_DIR = Path(__file__).resolve().parent
_firebase_initialized = False
# Serialises Firebase initialisation so concurrent first requests (the dashboard
# fires reminders + diary + alerts in parallel on app open) cannot both call
# initialize_app() and trigger a spurious "default app already exists" 503.
_firebase_init_lock = threading.Lock()
_AUTH_BYPASS_ALLOWED_ENVS = {"development", "dev", "test", "testing", "local"}


def _as_bool(value: str, default: bool = False) -> bool:
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


def _resolve_cred_path(cred_path: str) -> Optional[Path]:
    """Resolve the Firebase credentials path robustly, independent of the
    directory uvicorn was launched from.

    Tries, in order: the path as given (relative to cwd), relative to the
    backend/ folder, relative to the project root, and finally the bare filename
    inside backend/. Returns the first file that exists, else None.
    """
    raw = (cred_path or "").strip()
    if not raw:
        return None
    p = Path(raw).expanduser()
    if p.is_absolute():
        return p if p.exists() else None
    candidates = [
        Path.cwd() / p,
        _BACKEND_DIR / p,
        _BACKEND_DIR.parent / p,
        _BACKEND_DIR / p.name,
    ]
    for candidate in candidates:
        if candidate.exists():
            return candidate
    return None


def _firebase_credentials_from_env() -> Optional[dict[str, Any]]:
    """Load Firebase Admin service account JSON from cloud env variables."""
    encoded = (settings.FIREBASE_CREDENTIALS_BASE64 or "").strip()
    raw_json = (settings.FIREBASE_CREDENTIALS_JSON or "").strip()

    if encoded:
        try:
            raw_json = base64.b64decode(encoded).decode("utf-8")
        except (binascii.Error, UnicodeDecodeError) as exc:
            raise ValueError("FIREBASE_CREDENTIALS_BASE64 is not valid base64 JSON.") from exc

    if not raw_json:
        return None

    try:
        parsed = json.loads(raw_json)
    except json.JSONDecodeError as exc:
        raise ValueError("Firebase credentials JSON environment variable is invalid JSON.") from exc

    if not isinstance(parsed, dict):
        raise ValueError("Firebase credentials JSON must decode to an object.")
    return parsed


def _do_firebase_init() -> None:
    """Initialise the default Firebase app exactly once.

    Raises the underlying exception on a genuine configuration failure (missing
    or invalid credentials). Treats "default app already exists" as success.
    """
    global _firebase_initialized
    if _firebase_initialized:
        return

    with _firebase_init_lock:
        # Double-checked: another caller may have finished init while we waited.
        if _firebase_initialized:
            return

        cred_path = (settings.FIREBASE_CREDENTIALS_PATH or "").strip()
        cred_info = _firebase_credentials_from_env()
        try:
            if cred_info:
                initialize_app(credentials.Certificate(cred_info))
            elif cred_path:
                resolved = _resolve_cred_path(cred_path)
                if resolved is None:
                    raise FileNotFoundError(
                        f"Firebase credentials file not found for "
                        f"FIREBASE_CREDENTIALS_PATH='{cred_path}' (looked relative to the "
                        f"launch dir, {_BACKEND_DIR}, and {_BACKEND_DIR.parent})."
                    )
                initialize_app(credentials.Certificate(str(resolved)))
            else:
                # Allow ADC/container-level credential discovery when file path is not set.
                initialize_app()
        except ValueError as exc:
            # initialize_app() raises ValueError if the default app already exists
            # (e.g. it was initialised at startup first). That is a success state.
            if "already exists" not in str(exc).lower():
                raise
        # Only reached when init succeeded or the app already existed; a real
        # configuration error (bad/missing creds) propagates out unset.
        _firebase_initialized = True


def init_firebase_at_startup() -> None:
    """Eagerly initialise Firebase during app startup (single-threaded), so the
    first concurrent requests never race to initialise it. Logs the real reason
    on failure but does NOT crash the server, so the startup log is diagnostic.
    """
    try:
        _do_firebase_init()
        logger.info("firebase_initialized_at_startup")
    except Exception as exc:
        logger.error("firebase_startup_init_failed: %s", exc, exc_info=True)


def _ensure_firebase_initialized() -> None:
    """Lazy fallback used by request auth. After startup init this is a no-op."""
    try:
        _do_firebase_init()
    except Exception as exc:
        logger.error("firebase_init_failed: %s", exc, exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=(
                "Authentication is enabled but Firebase Admin is not configured. "
                "Set FIREBASE_CREDENTIALS_JSON, FIREBASE_CREDENTIALS_BASE64, "
                "or FIREBASE_CREDENTIALS_PATH to valid service account credentials."
            ),
        ) from exc


def get_current_user(authorization: str = Header(default="")) -> AuthenticatedUser:
    """
    Resolve current authenticated user from Firebase ID token.
    Set AUTH_BYPASS=true only for local testing.
    """
    if _as_bool(os.getenv("AUTH_BYPASS", "false"), default=False):
        env = os.getenv("ENVIRONMENT", "development").strip().lower()
        if env not in _AUTH_BYPASS_ALLOWED_ENVS:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail=(
                    "AUTH_BYPASS is only allowed in local/test environments. "
                    "Disable AUTH_BYPASS for this deployment environment."
                ),
            )
        return AuthenticatedUser(uid=os.getenv("AUTH_BYPASS_UID", "test_user"), email=None, name=None)

    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing or invalid Authorization header.",
        )
    token = authorization.split(" ", 1)[1].strip()
    if not token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Empty bearer token.",
        )

    _ensure_firebase_initialized()
    try:
        decoded = firebase_auth.verify_id_token(token)
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired authentication token.",
        ) from exc

    uid = decoded.get("uid")
    if not uid:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token does not contain a valid user id.",
        )
    return AuthenticatedUser(
        uid=uid,
        email=decoded.get("email"),
        name=decoded.get("name") or decoded.get("display_name"),
    )
