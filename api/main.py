"""MedAIx API entrypoint (Week 0 scaffold).

Only the health route exists at this stage — feature endpoints land in their
own sprint. `/health` is also the route the keep-alive ping hits, so it must
stay cheap and dependency-free.
"""

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from database import (
    SQLALCHEMY_DATABASE_URL,
    Base,
    engine,
    warn_if_ephemeral,
)
from models import Medicine, QRSession, Report, User, WellnessLog  # noqa: F401

Base.metadata.create_all(bind=engine)
warn_if_ephemeral()

app = FastAPI(
    title="MedAIx API",
    version="0.1.0",
    description="Clinical decision-support API for MedAIx.",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
def health() -> dict[str, str]:
    """Liveness, plus which database backend is actually serving requests.

    ``database`` exists so "is production on Postgres or throwaway SQLite?" is
    answerable with a single curl against the public URL. That question was
    previously unanswerable from outside, which is how a deploy sat on ephemeral
    SQLite for weeks unnoticed — the service returned 200 the whole time.

    Kept cheap and dependency-free on purpose: this is the route the keep-alive
    ping hits, so it must not open a database connection. The value is derived
    from the configured URL, not from a live query. The Flutter client matches on
    ``"ok"`` via a substring check, so adding this key does not break it.
    """
    return {
        "status": "ok",
        "database": (
            "sqlite" if SQLALCHEMY_DATABASE_URL.startswith("sqlite") else "postgres"
        ),
    }