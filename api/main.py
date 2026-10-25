"""MedAIx API entrypoint.

`/health` is the route the keep-alive ping hits, so it must stay cheap and
dependency-free. Feature endpoints land in their own sprint: Sprint 1 added
`/upload-report`; Sprint 2 added `/simplify-report`, `/reports`, and
`/profile`.
"""

import io
import logging
from typing import Annotated

from fastapi import Depends, FastAPI, File, Form, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from PIL import Image, UnidentifiedImageError
from pypdf import PdfReader
from sqlalchemy import func
from sqlalchemy.orm import Session

from auth import get_current_user
from database import (
    SQLALCHEMY_DATABASE_URL,
    Base,
    engine,
    get_db,
    rename_legacy_user_uid,
    warn_if_ephemeral,
)
from models import (  # noqa: F401
    Medicine,
    QRSession,
    Report,
    User,
    WellnessLog,
    utc_now,
)
from ocr import OcrLanguage, OcrResult, OcrUnavailableError, extract_text
from profile import (
    ProfileUpdate,
    profile_error_message,
    profile_payload,
)
from pydantic import ValidationError
from simplify import SimplifyResult, simplify_text

logger = logging.getLogger(__name__)

CurrentUser = Annotated[User, Depends(get_current_user)]
# The same session the auth dependency used: one connection per request.
DbSession = Annotated[Session, Depends(get_db)]

rename_legacy_user_uid()
Base.metadata.create_all(bind=engine)
warn_if_ephemeral()

# 12 MB. A 12MP phone photo is ~4 MB as JPEG; PDFs of lab reports sit well under
# this. The cap exists so one upload cannot exhaust the free tier's memory —
# Render gives a free instance roughly 512 MB.
MAX_UPLOAD_BYTES = 12 * 1024 * 1024

# Below this, Tesseract finds nothing worth storing. Surfacing it as a 422 lets
# the client show "we couldn't read that" instead of saving an empty report the
# user then has to recognise as useless.
MIN_CONFIDENCE = 30.0

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


def _first_page_image(payload: bytes) -> Image.Image:
    """Decode an uploaded image, or page 1 of a PDF, into a PIL image.

    PDFs go through their first page only. Tesseract reads images, not PDF
    text layers, and a scanned lab report has no text layer at all — so
    extracting text with pypdf would return nothing on exactly the documents
    this feature exists for. Rendering page 1 keeps both scanned and digital
    PDFs on the same code path.
    """
    if payload[:5] == b"%PDF-":
        try:
            reader = PdfReader(io.BytesIO(payload))
            if not reader.pages:
                raise HTTPException(
                    status_code=422,
                    detail="That PDF has no pages to read.",
                )
            # pypdf can rasterise only when an extra backend is present; fall
            # back to telling the user rather than raising a stack trace.
            for page in reader.pages[:1]:
                images = getattr(page, "images", None)
                if images:
                    return Image.open(io.BytesIO(images[0].data)).convert("RGB")
            raise HTTPException(
                status_code=422,
                detail="That PDF has no embedded image to read. "
                "Try uploading a photo of the report instead.",
            )
        except HTTPException:
            raise
        except Exception as exc:  # noqa: BLE001 - never leak parser internals
            logger.warning("PDF decode failed: %s", exc)
            raise HTTPException(
                status_code=422,
                detail="That PDF could not be read. "
                "Try uploading a photo of the report instead.",
            ) from exc

    try:
        image = Image.open(io.BytesIO(payload))
        image.load()
    except (UnidentifiedImageError, OSError) as exc:
        raise HTTPException(
            status_code=415,
            detail="That file is not a readable image. "
            "Upload a JPEG, PNG, or PDF of your report.",
        ) from exc

    return image.convert("RGB")


@app.post("/upload-report")
async def upload_report(
    user: CurrentUser,
    db: DbSession,
    file: Annotated[UploadFile, File(description="Lab report image or PDF")],
    language: Annotated[
        OcrLanguage,
        Form(description="OCR mode: English, Urdu script, or Roman Urdu"),
    ] = OcrLanguage.ENGLISH,
) -> dict[str, object]:
    """Accept a lab report, extract its text, and store the raw OCR result.

    Returns the stored report id and a confidence figure. Simplification into
    plain language is Sprint 2 (`/simplify-report`); Sprint 1 deliberately stops
    at raw extraction so the two can be measured separately.
    """
    payload = await file.read()
    if not payload:
        raise HTTPException(
            status_code=422,
            detail="That file was empty. Please choose a report to upload.",
        )
    if len(payload) > MAX_UPLOAD_BYTES:
        raise HTTPException(
            status_code=413,
            detail="That file is larger than 12 MB. "
            "Try a photo instead of a high-resolution scan.",
        )

    image = _first_page_image(payload)

    try:
        result: OcrResult = extract_text(image, language=language)
    except OcrUnavailableError as exc:
        # 503, not 500: the request was fine, the server is not ready.
        logger.error("OCR unavailable: %s", exc)
        raise HTTPException(
            status_code=503,
            detail=f"Report scanning is temporarily unavailable: {exc} "
            "Your file has not been lost.",
        ) from exc

    if not result.text or result.confidence < MIN_CONFIDENCE:
        raise HTTPException(
            status_code=422,
            detail="We could not read any text from that report. "
            "Try a clearer photo, with the whole page visible and good lighting.",
        )

    report = Report(
        user_id=user.id,
        original_text=result.text,
        ocr_confidence=result.confidence,
        image_path=file.filename,
    )
    db.add(report)
    db.commit()

    return {
        "id": report.id,
        "text": result.text,
        "language": language.value,
        "confidence": result.confidence,
        "width": result.width,
        "height": result.height,
        "skew_corrected_degrees": result.skew_degrees,
    }


@app.post("/simplify-report")
def simplify_report(
    user: CurrentUser,
    db: DbSession,
    payload: dict[str, object],
) -> dict[str, object]:
    """Simplify a stored report's OCR text into plain language.

    Body: ``{"report_id": <int>}``.

    Idempotent: if the report was already simplified, the stored
    ``simplified_text`` is returned without re-running the pipeline, so the
    client uses this same call to *view* a previous simplification. The
    simplification rewrites medical jargon only -- numbers, units, and
    reference ranges are left verbatim so a result cannot be misread.
    """
    report_id = payload.get("report_id")
    if not isinstance(report_id, int) or isinstance(report_id, bool):
        raise HTTPException(
            status_code=422,
            detail="Please send a valid report id (a whole number).",
        )

    report = db.get(Report, report_id)
    if report is None or report.user_id != user.id:
        raise HTTPException(
            status_code=404,
            detail="I can't find that report. Please upload it again first.",
        )
    if not report.original_text:
        raise HTTPException(
            status_code=422,
            detail="That report has no readable text to simplify.",
        )

    # Return a previous simplification instead of redoing the work.
    if report.simplified_text:
        return {
            "id": report.id,
            "original_text": report.original_text,
            "simplified_text": report.simplified_text,
            "terms_simplified": None,
            "sentence_count": None,
            "note": "Previously simplified.",
        }

    result: SimplifyResult = simplify_text(report.original_text)

    report.simplified_text = result.simplified_text
    report.processed_at = utc_now()
    db.commit()

    return {
        "id": report.id,
        "original_text": report.original_text,
        "simplified_text": result.simplified_text,
        "terms_simplified": result.terms_simplified,
        "sentence_count": result.sentence_count,
        "note": result.note,
    }


@app.get("/reports")
def list_reports(user: CurrentUser, db: DbSession) -> list[dict[str, object]]:
    """List the signed-in user's reports, newest first.

    Selects only the summary columns. Loading whole rows pulled every report's
    OCR text and simplified text (a few KB each) across the wire just to answer
    "is there a simplified version?".
    """
    rows = (
        db.query(
            Report.id,
            Report.uploaded_at,
            Report.ocr_confidence,
            Report.image_path,
            func.coalesce(func.length(Report.simplified_text), 0),
        )
        .filter(Report.user_id == user.id)
        .order_by(Report.uploaded_at.desc())
        .all()
    )
    return [
        {
            "id": report_id,
            "uploaded_at": uploaded_at.isoformat(),
            "confidence": confidence,
            "has_simplified": simplified_length > 0,
            "image_path": image_path,
        }
        for report_id, uploaded_at, confidence, image_path, simplified_length in rows
    ]


@app.get("/profile")
def read_profile(user: CurrentUser) -> dict[str, object]:
    """Return the signed-in patient's profile, including whether onboarding is done."""
    return profile_payload(user)


@app.put("/profile")
def update_profile(
    user: CurrentUser,
    db: DbSession,
    payload: dict[str, object],
) -> dict[str, object]:
    """Create or replace the profile answers collected during onboarding."""
    try:
        update = ProfileUpdate.model_validate(payload)
    except ValidationError as exc:
        raise HTTPException(
            status_code=422,
            detail=profile_error_message(exc),
        ) from exc

    # ``user`` is attached to this request's session, so write to it directly.
    user.name = update.name
    user.age = update.age
    user.weight = update.weight
    user.height = update.height
    user.sex = update.sex
    user.conditions = update.conditions
    user.medications = update.medications
    user.allergies = update.allergies
    db.commit()
    return profile_payload(user)


@app.delete("/profile")
def delete_profile(user: CurrentUser, db: DbSession) -> dict[str, bool]:
    """Delete this patient's MedAIx profile and the reports stored for them.

    The Supabase sign-in remains. The next request creates a blank profile,
    so onboarding runs again.
    """
    db.query(Report).filter(Report.user_id == user.id).delete()
    db.query(Medicine).filter(Medicine.user_id == user.id).delete()
    db.query(WellnessLog).filter(WellnessLog.user_id == user.id).delete()
    db.query(QRSession).filter(QRSession.user_id == user.id).delete()
    db.delete(user)
    db.commit()
    return {"deleted": True}

