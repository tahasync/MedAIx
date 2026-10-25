"""MedAIx API entrypoint.

`/health` is the route the keep-alive ping hits, so it must stay cheap and
dependency-free. Feature endpoints land in their own sprint: Sprint 1 added
`/upload-report`; Sprint 2 added `/simplify-report`, `/reports`, and
`/profile`; Sprint 3 added `/risk-trends` and the questionnaire profile.
"""

import io
import logging
from datetime import date, datetime, time, timedelta, timezone
from typing import Annotated

from fastapi import Depends, FastAPI, File, Form, HTTPException, Query, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from PIL import Image, UnidentifiedImageError
from pypdf import PdfReader
from sqlalchemy import func
from sqlalchemy.orm import Session

from auth import get_current_user
from database import (
    SQLALCHEMY_DATABASE_URL,
    Base,
    add_missing_wellness_columns,
    add_missing_user_columns,
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
    apply_profile_update,
    clear_health_data,
    profile_error_message,
    profile_payload,
)
from pydantic import BaseModel, Field, ValidationError, model_validator
from simplify import SimplifyResult, simplify_text
from trends import build_risk_trends, summarise_report

logger = logging.getLogger(__name__)

CurrentUser = Annotated[User, Depends(get_current_user)]
# The same session the auth dependency used: one connection per request.
DbSession = Annotated[Session, Depends(get_db)]

rename_legacy_user_uid()
Base.metadata.create_all(bind=engine)
# create_all never alters an existing table, so columns added since the
# database was created (the Sprint 3 questionnaire) are bolted on here.
add_missing_user_columns()
add_missing_wellness_columns()
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
    db.flush()
    _stamp_report(report, user)
    db.commit()

    return {
        "id": report.id,
        "text": result.text,
        "language": language.value,
        "confidence": result.confidence,
        "width": result.width,
        "height": result.height,
        "skew_corrected_degrees": result.skew_degrees,
        "title": report.title or report.derived_title,
        "attention_count": report.attention_count,
        "values_read": report.values_read,
        "values_expected": report.values_expected,
        "parse_note": report.parse_note,
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
            Report.title,
            Report.derived_title,
            Report.report_date,
            Report.attention_count,
            Report.values_read,
            Report.values_expected,
            Report.parse_note,
            Report.original_text,
        )
        .filter(Report.user_id == user.id)
        .order_by(Report.uploaded_at.desc())
        .all()
    )
    listed: list[dict[str, object]] = []
    for (
        report_id,
        uploaded_at,
        confidence,
        image_path,
        simplified_length,
        title,
        derived_title,
        report_date,
        attention_count,
        values_read,
        values_expected,
        parse_note,
        original_text,
    ) in rows:
        panel = derived_title or summarise_report(original_text or "")["title"]
        day = report_date or (uploaded_at.date() if uploaded_at else None)
        listed.append(
            {
                "id": report_id,
                "title": title or panel,
                "derived_title": panel,
                "report_date": day.isoformat() if day else None,
                "uploaded_at": uploaded_at.isoformat(),
                "confidence": confidence,
                "has_simplified": simplified_length > 0,
                "image_path": image_path,
                "attention_count": attention_count or 0,
                "values_read": values_read,
                "values_expected": values_expected,
                "parse_note": parse_note,
            }
        )
    return listed


class ReportTitleUpdate(BaseModel):
    title: str = Field(min_length=1, max_length=80)


@app.patch("/reports/{report_id}")
def rename_report(
    report_id: int,
    body: ReportTitleUpdate,
    user: CurrentUser,
    db: DbSession,
) -> dict[str, object]:
    """Let the patient rename a report. The derived panel title is kept."""
    report = (
        db.query(Report)
        .filter(Report.id == report_id, Report.user_id == user.id)
        .one_or_none()
    )
    if report is None:
        raise HTTPException(status_code=404, detail="That report is no longer available.")
    cleaned = body.title.strip()
    if not cleaned:
        raise HTTPException(status_code=422, detail="Give this report a name.")
    report.title = cleaned
    db.commit()
    return {
        "id": report.id,
        "title": report.title,
        "derived_title": report.derived_title,
    }


def _stamp_report(report: Report, user: User) -> None:
    """Fill list-facing fields from the OCR text. Never uses the first line."""
    summary = summarise_report(
        report.original_text or "",
        getattr(user, "sex_at_birth", None) or getattr(user, "sex", None),
    )
    report.derived_title = str(summary["title"])
    report.report_date = (report.uploaded_at or utc_now()).date()
    report.attention_count = int(summary["attention_count"])
    report.values_read = int(summary["values_read"])
    report.values_expected = int(summary["values_expected"])
    report.parse_note = summary["parse_note"]  # type: ignore[assignment]


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
    """Save the questionnaire answers that were sent; other fields are kept.

    Every key is optional, so the three onboarding screens can each save as
    the user finishes them. A failed validation stores nothing.
    """
    try:
        update = ProfileUpdate.model_validate(payload)
    except ValidationError as exc:
        raise HTTPException(
            status_code=422,
            detail=profile_error_message(exc),
        ) from exc

    # ``user`` is attached to this request's session, so write to it directly.
    apply_profile_update(user, update)
    db.commit()
    return profile_payload(user)


@app.delete("/profile")
def delete_profile(user: CurrentUser, db: DbSession) -> dict[str, bool]:
    """Delete this patient's health data: answers, consent and stored reports.

    The account (sign-in id, name, email) stays, so the user is not locked
    out; onboarding simply runs again because consent is gone.
    """
    db.query(Report).filter(Report.user_id == user.id).delete()
    db.query(Medicine).filter(Medicine.user_id == user.id).delete()
    db.query(WellnessLog).filter(WellnessLog.user_id == user.id).delete()
    db.query(QRSession).filter(QRSession.user_id == user.id).delete()
    clear_health_data(user)
    db.commit()
    return {"deleted": True}


class WellnessLogInput(BaseModel):
    """One offline-safe, idempotent wellness entry from the signed-in user."""

    client_id: str = Field(min_length=1, max_length=80)
    type: str = Field(pattern=r"^(water|steps|exercise)$")
    value: int = Field(gt=0)
    label: str | None = Field(default=None, max_length=40)
    occurred_at: datetime | None = None
    timezone_offset_minutes: int = Field(default=0, ge=-840, le=840)

    @model_validator(mode="after")
    def validate_entry(self) -> "WellnessLogInput":
        self.client_id = self.client_id.strip()
        if not self.client_id:
            raise ValueError("Missing entry id.")
        maximum = {"water": 2000, "steps": 50000, "exercise": 480}[self.type]
        if self.value > maximum:
            raise ValueError("Entry is above the allowed amount.")
        if self.type == "exercise":
            self.label = (self.label or "Exercise").strip() or "Exercise"
        elif self.label is not None:
            raise ValueError("Labels are only used for exercise entries.")
        if self.occurred_at is not None and self.occurred_at.tzinfo is None:
            raise ValueError("Entry time must include a timezone.")
        return self


_FLUID_RESTRICTION_TERMS = (
    "kidney disease",
    "chronic kidney",
    "renal disease",
    "dialysis",
    "heart failure",
    "cirrhosis",
    "liver failure",
    "hyponatremia",
    "fluid restriction",
)


def _wellness_goals(user: User) -> tuple[int | None, str, int, str]:
    """Return cautious starting estimates, never individualized prescriptions."""
    conditions = (user.conditions or "").lower()
    fluid_limited = any(term in conditions for term in _FLUID_RESTRICTION_TERMS)
    if fluid_limited:
        water_goal = None
        water_note = "Follow your clinician’s fluid limit; no estimate is shown."
    elif user.weight is not None and user.weight > 0:
        # A capped tracking estimate from the saved profile weight. It is not a
        # clinical fluid prescription; people with fluid restrictions are
        # excluded above and shown their clinician's plan instead.
        water_goal = round(user.weight * 30 / 50) * 50
        water_goal = int(max(1200, min(3600, water_goal)))
        water_note = "A starting estimate based on your saved weight."
    else:
        water_goal = 2100
        water_note = "A general starting estimate; add your weight for a tailored estimate."

    mobility_limited_terms = (
        "arthritis",
        "chronic pain",
        "mobility",
        "copd",
        "heart failure",
    )
    if any(term in conditions for term in mobility_limited_terms):
        step_goal = 4000
        step_note = "A lower starting goal based on your saved condition."
    elif conditions.strip():
        step_goal = 5000
        step_note = "A starting goal based on your saved condition."
    else:
        step_goal = 6000
        step_note = "A general starting goal."
    return water_goal, water_note, step_goal, step_note


def _wellness_tip(
    *,
    water_ml: int,
    water_goal_ml: int | None,
    steps: int,
    step_goal: int,
    exercise_label: str | None,
) -> str:
    """Local retrieval stub for short, non-diagnostic habit suggestions."""
    # Sprint 4 keeps the tip corpus on-device with the API: deterministic
    # retrieval, no external model call and no diagnosis or treatment advice.
    if water_goal_ml is None:
        return "Follow the fluid guidance your clinician or care team gave you."
    if water_ml < water_goal_ml:
        return "Log drinks as you have them to keep today’s estimate up to date."
    if exercise_label is None:
        return "A short, comfortable walk can count as movement; follow your care plan."
    if steps < step_goal:
        return "A few short walks can add steps through the day if that feels comfortable."
    return "You’ve logged today’s habits. Keep choosing what feels comfortable for you."


def _wellness_day(
    db: Session,
    user: User,
    *,
    day: date,
    timezone_offset_minutes: int,
) -> dict[str, object]:
    local_start = datetime.combine(day, time.min) - timedelta(
        minutes=timezone_offset_minutes
    )
    local_end = local_start + timedelta(days=1)
    logs = (
        db.query(WellnessLog)
        .filter(
            WellnessLog.user_id == user.id,
            WellnessLog.logged_at >= local_start,
            WellnessLog.logged_at < local_end,
        )
        .order_by(WellnessLog.logged_at, WellnessLog.id)
        .all()
    )
    water_ml = int(sum(log.value for log in logs if log.log_type == "water"))
    steps = int(sum(log.value for log in logs if log.log_type == "steps"))
    exercises = [log for log in logs if log.log_type == "exercise"]
    exercise_minutes = int(sum(log.value for log in exercises))
    exercise_label = exercises[-1].label if exercises else None
    water_goal, water_note, step_goal, step_note = _wellness_goals(user)
    return {
        "date": day.isoformat(),
        "water_ml": water_ml,
        "water_goal_ml": water_goal,
        "water_goal_note": water_note,
        "steps": steps,
        "step_goal": step_goal,
        "step_goal_note": step_note,
        "exercise_label": exercise_label,
        "exercise_minutes": exercise_minutes,
        "daily_tip": _wellness_tip(
            water_ml=water_ml,
            water_goal_ml=water_goal,
            steps=steps,
            step_goal=step_goal,
            exercise_label=exercise_label,
        ),
    }


@app.get("/wellness/log")
def read_wellness_log(
    user: CurrentUser,
    db: DbSession,
    day: date | None = None,
    timezone_offset_minutes: Annotated[int, Query(ge=-840, le=840)] = 0,
) -> dict[str, object]:
    """Return this user's daily totals, profile-based starting goals and tip."""
    selected_day = day or utc_now().date()
    if selected_day > utc_now().date() + timedelta(days=1):
        raise HTTPException(status_code=422, detail="Choose today or an earlier day.")
    if selected_day < utc_now().date() - timedelta(days=90):
        raise HTTPException(status_code=422, detail="That day is too far in the past.")
    return _wellness_day(
        db,
        user,
        day=selected_day,
        timezone_offset_minutes=timezone_offset_minutes,
    )


@app.post("/wellness/log")
def create_wellness_log(
    payload: dict[str, object],
    user: CurrentUser,
    db: DbSession,
) -> dict[str, object]:
    """Save one water, step or exercise entry and return refreshed daily totals."""
    try:
        entry = WellnessLogInput.model_validate(payload)
    except ValidationError as exc:
        raise HTTPException(
            status_code=422,
            detail="Check the habit entry and try again.",
        ) from exc

    now = utc_now()
    happened = (
        entry.occurred_at.astimezone(timezone.utc).replace(tzinfo=None)
        if entry.occurred_at is not None
        else now
    )
    if happened > now + timedelta(minutes=5) or happened < now - timedelta(days=90):
        raise HTTPException(
            status_code=422,
            detail="Log an entry from the last 90 days.",
        )

    existing = (
        db.query(WellnessLog)
        .filter(
            WellnessLog.user_id == user.id,
            WellnessLog.client_id == entry.client_id,
        )
        .one_or_none()
    )
    if existing is None:
        water_goal, _, step_goal, _ = _wellness_goals(user)
        target = (
            water_goal
            if entry.type == "water"
            else step_goal
            if entry.type == "steps"
            else None
        )
        log = WellnessLog(
            user_id=user.id,
            log_type=entry.type,
            value=entry.value,
            target=target,
            label=entry.label,
            client_id=entry.client_id,
            logged_at=happened,
        )
        db.add(log)
        db.commit()

    local_day = (
        happened + timedelta(minutes=entry.timezone_offset_minutes)
    ).date()
    return _wellness_day(
        db,
        user,
        day=local_day,
        timezone_offset_minutes=entry.timezone_offset_minutes,
    )


@app.get("/risk-trends")
def risk_trends(user: CurrentUser, db: DbSession) -> dict[str, object]:
    """Rule-based trends and alerts across the signed-in user's reports.

    Parses lab values out of each report's OCR text, groups them per marker
    and applies the Sprint 3 rules (``trends.py``). ``needs_reports`` is true
    until two reports exist; single-point markers are still listed so the app
    can show "1 report so far", but never raise an alert.
    """
    rows = (
        db.query(Report.id, Report.uploaded_at, Report.original_text)
        .filter(Report.user_id == user.id)
        .order_by(Report.uploaded_at, Report.id)
        .all()
    )
    return build_risk_trends(user, rows)

