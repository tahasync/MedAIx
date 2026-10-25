"""Supabase session checks for the MedAIx API.

The Flutter app signs in with Supabase Auth and sends the access token as
``Authorization: Bearer``. This module verifies that token against the
project's public JWKS (ES256) and maps the ``sub`` claim to a local user row.

The publishable key never belongs here. The JWT secret does not either:
this project signs tokens with an asymmetric key, so verification uses only
the public key set.
"""

import logging
import os

import jwt
from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jwt import PyJWKClient
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

import database  # noqa: F401  # loads .env before SUPABASE_URL is read
from database import get_db
from models import User

logger = logging.getLogger(__name__)

# Public project URL. Override with SUPABASE_URL when pointing at another project.
DEFAULT_SUPABASE_URL = "https://fmjcifnrwbazdlrhklta.supabase.co"

_bearer = HTTPBearer(auto_error=False)
_jwks_client: PyJWKClient | None = None
_jwks_for_url: str | None = None


def supabase_url() -> str:
    configured = os.getenv("SUPABASE_URL", DEFAULT_SUPABASE_URL).strip().rstrip("/")
    return configured or DEFAULT_SUPABASE_URL


def _jwks() -> PyJWKClient:
    global _jwks_client, _jwks_for_url
    url = f"{supabase_url()}/auth/v1/.well-known/jwks.json"
    if _jwks_client is None or _jwks_for_url != url:
        # Cache for 10 minutes. Longer than that would keep trusting a revoked key.
        _jwks_client = PyJWKClient(url, cache_jwk_set=True, lifespan=600, timeout=10)
        _jwks_for_url = url
    return _jwks_client


def verify_access_token(token: str) -> dict[str, object]:
    """Return the verified claims, or raise HTTPException."""
    try:
        signing_key = _jwks().get_signing_key_from_jwt(token)
        claims = jwt.decode(
            token,
            signing_key.key,
            algorithms=["ES256", "RS256"],
            audience="authenticated",
        )
    except (jwt.PyJWTError, jwt.PyJWKClientError) as exc:
        logger.info("Rejected session token: %s", exc.__class__.__name__)
        raise HTTPException(
            status_code=401,
            detail="Your session has expired. Please sign in again.",
        ) from exc
    except Exception as exc:  # noqa: BLE001 - JWKS outage, not a bad password
        logger.error("Could not verify session: %s", exc.__class__.__name__)
        raise HTTPException(
            status_code=503,
            detail="Sign-in is temporarily unavailable. Try again shortly.",
        ) from exc

    subject = claims.get("sub")
    if not isinstance(subject, str) or not subject:
        raise HTTPException(
            status_code=401,
            detail="Your session has expired. Please sign in again.",
        )
    return claims


def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer),
    db: Session = Depends(get_db),
) -> User:
    """Verify the bearer token and return the matching local user.

    Creates the row on first sign-in. The client never chooses the user id;
    it always comes from the verified ``sub`` claim.

    The user stays attached to ``db``, the request-scoped session shared with
    the route handler, so profile updates can write to it directly.
    """
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise HTTPException(
            status_code=401,
            detail="Please sign in to continue.",
        )

    subject = verify_access_token(credentials.credentials)["sub"]
    if not isinstance(subject, str):
        raise HTTPException(
            status_code=401,
            detail="Your session has expired. Please sign in again.",
        )

    user = db.query(User).filter(User.supabase_uid == subject).one_or_none()
    if user is None:
        user = User(supabase_uid=subject)
        db.add(user)
        try:
            db.commit()
        except IntegrityError:
            # Two first requests raced; the other one won. Use its row.
            db.rollback()
            user = db.query(User).filter(User.supabase_uid == subject).one()
    return user
