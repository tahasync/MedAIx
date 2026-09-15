from contextlib import asynccontextmanager
from fastapi import FastAPI
from database import engine, Base
from models import User, Report, Medicine, WellnessLog, QRSession

Base.metadata.create_all(bind=engine)

app = FastAPI(title="MedAIx API", version="0.1.0")

@app.get("/health")
def health():
    return {"status": "ok"}
