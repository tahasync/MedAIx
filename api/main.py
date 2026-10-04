"""MedAIx API entrypoint (Week 0 scaffold).

Only the health route exists at this stage — feature endpoints land in their
own sprint. `/health` is also the route the keep-alive ping hits, so it must
stay cheap and dependency-free.
"""

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from database import Base, engine, warn_if_ephemeral
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
    return {"status": "ok"}