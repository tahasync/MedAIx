"""Database engine and session wiring.

Defaults to a local SQLite file for Sprint 1. Set ``DATABASE_URL`` (or
``NEON_DATABASE_URL`` on Render) to Neon's pooled connection string to move to
Postgres — the pooled ``-pooler`` host is preferred so a single Render dyno
doesn't exhaust direct connections.

``.env`` files are loaded before the URL is read. Without this the process
environment is the *only* source, so a developer following the documented
"copy .env.example to .env" step would silently keep writing to SQLite.
Real process environment variables always win over the files, so Render's
dashboard-configured ``NEON_DATABASE_URL`` is never overridden locally.
"""

import logging
import os
from pathlib import Path

from dotenv import load_dotenv
from sqlalchemy import create_engine
from sqlalchemy.orm import declarative_base, sessionmaker

# api/.env holds hand-written local settings; the repo-root .env.local is
# where `neon link` / `neon env pull` write the Neon-managed credentials.
# First-wins, so the api/.env values above the root .env.local values.
_ROOT = Path(__file__).resolve().parent.parent
load_dotenv(_ROOT / "api" / ".env", override=False)
load_dotenv(_ROOT / ".env.local", override=False)

SQLALCHEMY_DATABASE_URL = os.getenv(
    "DATABASE_URL", os.getenv("NEON_DATABASE_URL", "sqlite:///./medaix.db")
)

# Neon/SQLAlchemy URL normalisation.
if SQLALCHEMY_DATABASE_URL.startswith("postgres://"):
    SQLALCHEMY_DATABASE_URL = SQLALCHEMY_DATABASE_URL.replace(
        "postgres://", "postgresql://", 1
    )

connect_args: dict[str, object] = {}
if SQLALCHEMY_DATABASE_URL.startswith("sqlite"):
    connect_args["check_same_thread"] = False

engine_kwargs: dict[str, object] = dict(connect_args=connect_args)
if not SQLALCHEMY_DATABASE_URL.startswith("sqlite"):
    # Neon scales to zero, so the pooler happily hands back connections that
    # have already been closed on the server side. pool_pre_ping discards those
    # instead of raising an "operational error" on the first real request.
    # recycle stays well under the pooler's idle cut-off for the same reason.
    engine_kwargs.update(pool_pre_ping=True, pool_recycle=1800)

engine = create_engine(SQLALCHEMY_DATABASE_URL, **engine_kwargs)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()


def get_db():
    """FastAPI dependency yielding a scoped session."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def warn_if_ephemeral() -> None:
    """Log loudly when running on a throwaway filesystem.

    Render (and every container platform) gives each deploy a fresh,
    ephemeral disk, so a SQLite file written there disappears on the next
    redeploy. That is harmless while `/health` is the only route, but the
    failure mode is silent: rows are written, reads succeed, and the data is
    simply gone after a restart. Surfacing this at startup means the warning
    is read long before someone loses a report to it.
    """
    if not SQLALCHEMY_DATABASE_URL.startswith("sqlite"):
        return

    logger = logging.getLogger(__name__)
    logger.warning(
        "Using SQLite (%s) on what may be an ephemeral filesystem: "
        "data will be LOST on the next deploy or restart. Set DATABASE_URL "
        "(or NEON_DATABASE_URL on Render) to a pooled Postgres connection "
        "string before storing real user data.",
        SQLALCHEMY_DATABASE_URL,
    )