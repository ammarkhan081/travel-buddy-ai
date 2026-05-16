"""Authentication and user-context dependencies."""

import os
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

from fastapi import Header, HTTPException, status
from firebase_admin import auth as firebase_auth
from firebase_admin import credentials, initialize_app

try:
    from .config import settings
except ImportError:
    from config import settings


@dataclass
class AuthenticatedUser:
    uid: str
    email: Optional[str] = None
    name: Optional[str] = None


_firebase_initialized = False
_AUTH_BYPASS_ALLOWED_ENVS = {"development", "dev", "test", "testing", "local"}


def _as_bool(value: str, default: bool = False) -> bool:
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


def _ensure_firebase_initialized() -> None:
    global _firebase_initialized
    if _firebase_initialized:
        return

    cred_path = (settings.FIREBASE_CREDENTIALS_PATH or "").strip()
    try:
        if cred_path:
            p = Path(cred_path)
            if not p.is_absolute():
                p = Path.cwd() / p
            if not p.exists():
                raise FileNotFoundError(f"Firebase credentials file not found: {p}")
            initialize_app(credentials.Certificate(str(p)))
        else:
            # Allow ADC/container-level credential discovery when file path is not set.
            initialize_app()
        _firebase_initialized = True
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=(
                "Authentication is enabled but Firebase Admin is not configured. "
                "Set FIREBASE_CREDENTIALS_PATH to a valid service account file."
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
