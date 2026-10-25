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
# expire_on_commit=False: a request reads back the row it just wrote (the new
# report id, the simplified text) and sessions are request-scoped, so there is
# no later writer to be stale against. The default would silently issue one
# more SELECT per committed object. Against Neon that is ~100 ms per request.
SessionLocal = sessionmaker(
    autocommit=False,
    autoflush=False,
    expire_on_commit=False,
    bind=engine,
)
Base = declarative_base()


def get_db():
    """FastAPI dependency yielding one session for the whole request.

    The auth dependency and the route handler both depend on this, and FastAPI
    resolves a dependency once per request, so they share the session and the
    connection. Opening a second session per request cost an extra pool
    checkout (``pool_pre_ping`` SELECT) and an extra ROLLBACK on return: two
    network round trips on every authenticated call.
    """
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def rename_legacy_user_uid() -> None:
    """Rename an older ``users.firebase_uid`` column to ``supabase_uid``.

    ``create_all`` does not alter an existing column. Local databases created
    before Supabase Auth still have ``firebase_uid``, and queries against
    ``supabase_uid`` would fail until the name is updated.
    """
    from sqlalchemy import inspect, text

    inspector = inspect(engine)
    if not inspector.has_table("users"):
        return
    columns = {column["name"] for column in inspector.get_columns("users")}
    if "firebase_uid" in columns and "supabase_uid" not in columns:
        with engine.begin() as connection:
            connection.execute(
                text(
                    "ALTER TABLE users RENAME COLUMN firebase_uid TO supabase_uid"
                )
            )


def _portable_column_type(column_type: object) -> str:
    """DDL type name that both SQLite and Postgres accept for a model column."""
    from sqlalchemy import Boolean, Date, DateTime, Float, Integer, Text

    if isinstance(column_type, Boolean):
        return "BOOLEAN"
    if isinstance(column_type, Date):
        return "DATE"
    if isinstance(column_type, DateTime):
        return "TIMESTAMP"
    if isinstance(column_type, Integer):
        return "INTEGER"
    if isinstance(column_type, Float):
        return "FLOAT"
    if isinstance(column_type, Text):
        return "TEXT"
    return "VARCHAR"


def add_missing_user_columns(bind=None) -> list[str]:
    """Add any ``users`` column the model declares but the table lacks.

    ``create_all`` only creates missing *tables*, so a database created before
    the Sprint 3 questionnaire would keep its old ``users`` shape and every
    profile read would fail on the first new column. Each missing column is
    added with ``ALTER TABLE ... ADD COLUMN`` using a type name SQLite and
    Postgres both understand. Idempotent: a second call adds nothing.

    ``bind`` defaults to the application engine; tests pass a throwaway one.
    Returns the names of the columns that were added.
    """
    from models import Report, User

    added = _add_missing_columns(User, bind)
    added.extend(_add_missing_columns(Report, bind))
    return added


def add_missing_wellness_columns(bind=None) -> list[str]:
    """Add Sprint 4 wellness fields to databases created by older releases."""
    from sqlalchemy import inspect

    from models import WellnessLog

    target = bind if bind is not None else engine
    if not inspect(target).has_table(WellnessLog.__tablename__):
        return []
    added = _add_missing_columns(WellnessLog, target)
    # Existing installations already have the table, so create_all cannot
    # create its indexes while adding the new nullable idempotency column.
    for index in WellnessLog.__table__.indexes:
        index.create(target, checkfirst=True)
    return added


def _add_missing_columns(model: type, bind=None) -> list[str]:
    from sqlalchemy import inspect, text

    target = bind if bind is not None else engine
    table = model.__tablename__
    inspector = inspect(target)
    if not inspector.has_table(table):
        return []
    existing = {column["name"] for column in inspector.get_columns(table)}
    added: list[str] = []
    with target.begin() as connection:
        for column in model.__table__.columns:
            if column.name in existing:
                continue
            connection.execute(
                text(
                    f"ALTER TABLE {table} ADD COLUMN {column.name} "
                    f"{_portable_column_type(column.type)}"
                )
            )
            added.append(column.name)
    return added


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
