"""Database engine and session wiring.

Defaults to a local SQLite file for Sprint 1. Set ``DATABASE_URL`` (or
``NEON_DATABASE_URL`` on Render) to Neon's pooled connection string to move to
Postgres — the pooled ``-pooler`` host is preferred so a single Render dyno
doesn't exhaust direct connections.
"""

import os

from sqlalchemy import create_engine
from sqlalchemy.orm import declarative_base, sessionmaker

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

engine = create_engine(SQLALCHEMY_DATABASE_URL, connect_args=connect_args)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()


def get_db():
    """FastAPI dependency yielding a scoped session."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()