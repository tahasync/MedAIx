"""Tests for the Week 0 API scaffold.

Runs against an isolated SQLite file so a local `medaix.db` is never touched.
"""

import io
import os
from datetime import date, datetime

import pytest
from fastapi import Depends
from fastapi.testclient import TestClient
from PIL import Image, ImageDraw, ImageFont
from sqlalchemy import create_engine, inspect, text
from sqlalchemy.orm import Session

os.environ.setdefault("DATABASE_URL", "sqlite:///./test_medaix.db")

# Order-sensitive, and it must stay above the `database` import below.
#
# `database` reads DATABASE_URL at import time, and it loads `api/.env` and the
# repo-root `.env.local` with override=False. That means the value already in
# os.environ wins over both files, so this setdefault is what keeps the suite
# off the real Neon Postgres database instead of creating tables in it.
#
# A developer who has DATABASE_URL exported in their shell will still override
# this line, so the tests then run against whatever that points at. Delete
# DATABASE_URL from the environment when a green run matters more than a
# configured local database.
#
# Do not move this above the `database` import: doing so lets `.env.local`
# decide the URL and the tests will write to Neon.
import database  # noqa: E402
import ocr as ocr_module  # noqa: E402
import main as main_module  # noqa: E402
import simplify as simplify_module  # noqa: E402
from auth import get_current_user  # noqa: E402
from database import SessionLocal, get_db  # noqa: E402
from main import app  # noqa: E402
from models import Report, User, utc_now  # noqa: E402
from profile import CONSENT_VERSION  # noqa: E402


@pytest.fixture(autouse=True)
def _signed_in_user():
    """Treat API calls as the test user unless a test removes the override."""

    def _user(db: Session = Depends(get_db)) -> User:
        # Same contract as the real dependency: the user is attached to the
        # request-scoped session the route handler will write through.
        user = db.query(User).filter(User.supabase_uid == "test-user").one_or_none()
        if user is None:
            user = User(supabase_uid="test-user")
            db.add(user)
            db.commit()
        return user

    app.dependency_overrides[get_current_user] = _user
    yield
    app.dependency_overrides.pop(get_current_user, None)


@pytest.fixture()
def client() -> TestClient:
    return TestClient(app)


def test_health_returns_ok(client: TestClient) -> None:
    """Given the API is running, when GET /health is called, then it reports ok."""
    response = client.get("/health")

    assert response.status_code == 200
    assert response.json() == {"status": "ok", "database": "sqlite"}


def test_health_reports_postgres_when_configured(
    monkeypatch: pytest.MonkeyPatch,
    client: TestClient,
) -> None:
    """/health must name the backend, so a SQLite deploy is visible from outside.

    Without this, a service on ephemeral SQLite returns a healthy 200 and the
    problem is only discoverable by reading Render's startup logs.

    Patches ``main`` rather than ``database``: main.py imports the URL into its
    own namespace at import time, so patching the database module would leave
    the route reading the original value.
    """
    monkeypatch.setattr(
        main_module,
        "SQLALCHEMY_DATABASE_URL",
        "postgresql://user:pw@ep-x-pooler.aws.neon.tech/medaix",
    )

    response = client.get("/health")

    assert response.json()["database"] == "postgres"


def test_openapi_schema_is_served(client: TestClient) -> None:
    """Given the API is running, when /openapi.json is fetched, then docs are exposed."""
    response = client.get("/openapi.json")

    assert response.status_code == 200
    assert "paths" in response.json()


def test_sqlite_on_disk_triggers_ephemeral_warning(
    caplog: pytest.LogCaptureFixture,
) -> None:
    """A SQLite URL must warn, since Render's disk is wiped on every deploy."""
    with caplog.at_level("WARNING"):
        database.warn_if_ephemeral()

    assert any("ephemeral" in record.message for record in caplog.records)


def test_postgres_url_does_not_warn(
    monkeypatch: pytest.MonkeyPatch,
    caplog: pytest.LogCaptureFixture,
) -> None:
    """Once Neon is configured the warning is noise, so it must stay silent."""
    monkeypatch.setattr(
        database,
        "SQLALCHEMY_DATABASE_URL",
        "postgresql://user:pw@ep-x-pooler.aws.neon.tech/medaix",
    )

    with caplog.at_level("WARNING"):
        database.warn_if_ephemeral()

    assert not any("ephemeral" in record.message for record in caplog.records)


# ---- Sprint 1: /upload-report ----


def _lab_report_image(lines: list[str] | None = None) -> bytes:
    """Render a report-like PNG in memory.

    Real Tesseract output, not a stub — a mocked extractor would prove only
    that the route wires up, which the OCR tests do not need repeated for.
    """
    rows = lines or [
        "COMPLETE BLOOD COUNT",
        "TEST RESULT UNIT REFERENCE",
        "Haemoglobin 14.2 g/dL 12.0 - 16.0",
        "Platelets 245 10*9/L 150 - 400",
    ]
    image = Image.new("L", (1500, 700), color=255)
    draw = ImageDraw.Draw(image)
    for index, row in enumerate(rows):
        draw.text((60, 60 + index * 70), row, fill=0, font=_report_font(34))
    buffer = io.BytesIO()
    image.save(buffer, format="PNG")
    return buffer.getvalue()


def _report_font(size: int):
    for candidate in ("arial.ttf", "segoeui.ttf", "calibri.ttf"):
        try:
            return ImageFont.truetype(candidate, size)
        except OSError:
            continue
    try:
        # Pillow >= 10.1 renders a crisp scalable font at the requested size.
        # The CI runner has none of the Windows fonts above, and the bare
        # load_default() bitmap fallback ignored `size`, producing tiny blocky
        # glyphs that Tesseract misread ("Haemoglobin" -> "Haemeglobin"), which
        # failed the deploy workflow's test step. Scaling the default font fixes it.
        return ImageFont.load_default(size=size)
    except TypeError:  # Pillow < 10.1 has no scalable default.
        return ImageFont.load_default()


def test_upload_report_extracts_and_stores_text(client: TestClient) -> None:
    """Given a report photo, when it is uploaded, then text is stored with it."""
    response = client.post(
        "/upload-report",
        files={"file": ("cbc.png", _lab_report_image(), "image/png")},
    )

    assert response.status_code == 200
    body = response.json()
    assert body["id"] is not None
    # OCR of clean synthetic print should comfortably clear the floor.
    assert body["confidence"] >= 30.0
    assert "Haemoglobin" in body["text"]
    assert body["width"] > 0
    stored = SessionLocal()
    try:
        report = stored.get(Report, body["id"])
        owner = stored.query(User).filter(User.supabase_uid == "test-user").one()
        assert report is not None
        assert report.user_id == owner.id
    finally:
        stored.close()


@pytest.mark.parametrize("language", ["english", "urdu", "roman_urdu"])
def test_upload_report_passes_selected_language(
    client: TestClient,
    monkeypatch: pytest.MonkeyPatch,
    language: str,
) -> None:
    selected: list[str] = []

    def fake_extract(image: Image.Image, *, language):
        selected.append(language.value)
        return main_module.OcrResult(
            text="Sample lab report",
            confidence=88.0,
            width=image.width,
            height=image.height,
            skew_degrees=0.0,
        )

    monkeypatch.setattr(main_module, "extract_text", fake_extract)
    response = client.post(
        "/upload-report",
        data={"language": language},
        files={"file": ("report.png", _lab_report_image(), "image/png")},
    )

    assert response.status_code == 200
    assert selected == [language]
    assert response.json()["language"] == language


def test_upload_report_defaults_to_english(client: TestClient) -> None:
    response = client.post(
        "/upload-report",
        files={"file": ("cbc.png", _lab_report_image(), "image/png")},
    )

    assert response.status_code == 200
    assert response.json()["language"] == "english"


def test_upload_report_rejects_unknown_language(client: TestClient) -> None:
    response = client.post(
        "/upload-report",
        data={"language": "french"},
        files={"file": ("cbc.png", _lab_report_image(), "image/png")},
    )

    assert response.status_code == 422


def test_urdu_upload_explains_when_language_data_is_missing(
    client: TestClient,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(
        ocr_module.pytesseract,
        "get_languages",
        lambda **_: ["eng", "osd"],
    )
    response = client.post(
        "/upload-report",
        data={"language": "urdu"},
        files={"file": ("urdu.png", _lab_report_image(), "image/png")},
    )

    assert response.status_code == 503
    assert "urd" in response.json()["detail"]


def test_upload_report_rejects_empty_file(client: TestClient) -> None:
    """Given a zero-byte upload, when posted, then the user gets a clear 422."""
    response = client.post(
        "/upload-report",
        files={"file": ("empty.png", b"", "image/png")},
    )

    assert response.status_code == 422
    assert "empty" in response.json()["detail"].lower()


def test_upload_report_rejects_non_image(client: TestClient) -> None:
    """Given a file that is not an image, when posted, then it is a 415."""
    response = client.post(
        "/upload-report",
        files={"file": ("notes.txt", b"just some text", "text/plain")},
    )

    assert response.status_code == 415
    assert "not a readable image" in response.json()["detail"]


def test_upload_report_rejects_oversized_file(client: TestClient) -> None:
    """Given a file over the cap, when posted, then it is a 413 not an OOM."""
    oversized = b"\x89PNG\r\n\x1a\n" + b"0" * (main_module.MAX_UPLOAD_BYTES + 1)

    response = client.post(
        "/upload-report",
        files={"file": ("big.png", oversized, "image/png")},
    )

    assert response.status_code == 413
    assert "12 MB" in response.json()["detail"]


def test_upload_report_rejects_blank_image(client: TestClient) -> None:
    """Given a photo with no readable text, when posted, then it is a 422.

    Storing an empty report would leave the user to discover the failure
    themselves when the simplified view comes back blank.
    """
    blank = io.BytesIO()
    Image.new("L", (600, 400), color=255).save(blank, format="PNG")

    response = client.post(
        "/upload-report",
        files={"file": ("blank.png", blank.getvalue(), "image/png")},
    )

    assert response.status_code == 422
    assert "could not read" in response.json()["detail"].lower()


def test_upload_report_corrects_skew(client: TestClient) -> None:
    """Given a rotated photo, when uploaded, then the skew is detected and fixed."""
    image = Image.open(io.BytesIO(_lab_report_image())).convert("L")
    rotated = image.rotate(3.0, resample=Image.BICUBIC, expand=True, fillcolor=255)
    buffer = io.BytesIO()
    rotated.save(buffer, format="PNG")

    response = client.post(
        "/upload-report",
        files={"file": ("tilted.png", buffer.getvalue(), "image/png")},
    )

    assert response.status_code == 200
    assert response.json()["skew_corrected_degrees"] != 0.0


def test_deskew_recovers_the_tilt_angle() -> None:
    """A page tilted by +3 degrees must be rotated back by -3, not +3 or 0."""
    image = Image.open(io.BytesIO(_lab_report_image())).convert("L")
    rotated = image.rotate(3.0, resample=Image.BICUBIC, expand=True, fillcolor=255)

    _levelled, angle = ocr_module._deskew(rotated)

    assert angle == pytest.approx(-3.0, abs=ocr_module._SKEW_STEP)


@pytest.mark.parametrize(
    ("token", "confidence", "noise"),
    [
        ("Saytall", 0.0, True),  # Arabic header read with the English model
        ("oayyall", 12.0, True),
        ("Haemoglobin", 10.0, False),  # known lab word: keep even when unsure
        ("count", 5.0, False),
        ("14.2", 3.0, False),  # anything with a digit is kept
        ("59Y", 20.0, False),
        ("+", 0.0, False),  # single characters carry meaning
        ("Saytall", 40.0, False),  # above the floor: not our call
    ],
)
def test_noise_filter_keeps_numbers_and_lab_words(
    token: str,
    confidence: float,
    noise: bool,
) -> None:
    assert ocr_module._is_noise(token, confidence) is noise


def test_preprocess_downscales_oversized_image() -> None:
    """A 12 MP photo is reined in to the max long edge before OCR.

    Tesseract's cost and memory both scale with pixel count, so a full-resolution
    phone photo fed straight in is the slowest step of the request for no accuracy
    gain past ~300 DPI. The long edge must be clamped down, never left oversized.
    """
    oversized = Image.new("L", (4000, 3000), color=255)

    prepared, _skew = ocr_module.preprocess(oversized)

    assert max(prepared.size) == ocr_module._MAX_LONG_EDGE
    # Aspect ratio preserved: a 4:3 frame stays 4:3 after scaling.
    assert prepared.width * 3000 == prepared.height * 4000


def test_preprocess_upscales_small_image() -> None:
    """A small image is still upscaled so fine print survives binarisation."""
    small = Image.new("L", (800, 600), color=255)

    prepared, _skew = ocr_module.preprocess(small)

    assert max(prepared.size) == ocr_module._MIN_LONG_EDGE


def test_preprocess_leaves_in_range_image_untouched() -> None:
    """An already well-sized scan is returned as-is, not needlessly resampled."""
    sized = Image.new("L", (2000, 2500), color=255)

    prepared, _skew = ocr_module.preprocess(sized)

    assert prepared.size == (2000, 2500)


def test_openapi_documents_upload_route(client: TestClient) -> None:
    """The upload route must appear in the schema for the client to target it."""
    schema = client.get("/openapi.json").json()

    assert "/upload-report" in schema["paths"]

# ---- Sprint 2: /simplify-report ----


def test_simplify_replaces_medical_terms() -> None:
    """Given raw OCR text with jargon, when simplified, then terms are reworded."""
    result = simplify_module.simplify_text("Your WBC count is high, and glucose is elevated.")

    assert "white blood cells" in result.simplified_text.lower()
    assert "blood sugar" in result.simplified_text.lower()
    assert "higher than normal" in result.simplified_text.lower()
    assert result.terms_simplified > 0


def test_simplify_preserves_numbers_and_units() -> None:
    """Numbers and units are left verbatim so results cannot be misread."""
    result = simplify_module.simplify_text("Glucose 98 mg/dL, sodium 140 mmol/L.")

    assert "98" in result.simplified_text
    assert "140" in result.simplified_text
    assert "milligrams per decilitre" in result.simplified_text
    assert "millimoles per litre" in result.simplified_text


def test_simplify_empty_text_returns_empty() -> None:
    """Empty input yields an empty result, not an error."""
    result = simplify_module.simplify_text("")

    assert result.simplified_text == ""
    assert result.terms_simplified == 0


def test_simplify_report_endpoint_simplifies_and_stores(client: TestClient) -> None:
    """POST /simplify-report stores and returns the simplification."""
    upload = client.post(
        "/upload-report",
        files={"file": ("report.png", _lab_report_image(), "image/png")},
    )
    assert upload.status_code == 200
    report_id = upload.json()["id"]

    response = client.post("/simplify-report", json={"report_id": report_id})

    assert response.status_code == 200
    body = response.json()
    assert body["id"] == report_id
    assert body["simplified_text"]
    assert body["terms_simplified"] is not None
    assert body["sentence_count"] is not None


def test_simplify_report_stamps_processed_at(client: TestClient) -> None:
    """Simplifying records when it happened, separately from the upload time."""
    upload = client.post(
        "/upload-report",
        files={"file": ("report.png", _lab_report_image(), "image/png")},
    )
    report_id = upload.json()["id"]

    assert client.post("/simplify-report", json={"report_id": report_id}).status_code == 200

    session = SessionLocal()
    try:
        report = session.get(Report, report_id)
        assert report is not None
        assert report.simplified_text
        assert report.processed_at >= report.uploaded_at
    finally:
        session.close()


def test_simplify_report_endpoint_is_idempotent(client: TestClient) -> None:
    """Simplifying the same report twice returns the stored text both times."""
    upload = client.post(
        "/upload-report",
        files={"file": ("report.png", _lab_report_image(), "image/png")},
    )
    report_id = upload.json()["id"]

    first = client.post("/simplify-report", json={"report_id": report_id})
    second = client.post("/simplify-report", json={"report_id": report_id})

    assert first.status_code == 200
    assert second.status_code == 200
    assert first.json()["simplified_text"] == second.json()["simplified_text"]
    assert second.json()["note"] == "Previously simplified."


def test_simplify_report_missing_id_returns_404(client: TestClient) -> None:
    """A report that does not exist gets a plain-language 404."""
    response = client.post("/simplify-report", json={"report_id": 999999})

    assert response.status_code == 404
    assert "can't find that report" in response.json()["detail"].lower()


def test_simplify_report_invalid_id_returns_422(client: TestClient) -> None:
    """A non-integer id gets a plain-language 422."""
    response = client.post("/simplify-report", json={"report_id": "not-a-number"})

    assert response.status_code == 422


def test_list_reports_returns_newest_first(client: TestClient) -> None:
    """GET /reports lists stored reports newest first."""
    client.post("/upload-report", files={"file": ("a.png", _lab_report_image(), "image/png")})
    client.post("/upload-report", files={"file": ("b.png", _lab_report_image(), "image/png")})

    response = client.get("/reports")

    assert response.status_code == 200
    reports = response.json()
    # The two reports we just uploaded must appear newest-first (b.png before a.png)
    # regardless of any leftover rows from earlier tests in this session.
    paths = [report["image_path"] for report in reports]
    b_index = paths.index("b.png")
    a_index = paths.index("a.png")
    assert b_index < a_index, f"b.png ({b_index}) must precede a.png ({a_index})"
    assert all(not report["has_simplified"] for report in reports if report["image_path"] in ("a.png", "b.png"))


def test_upload_report_requires_sign_in(client: TestClient) -> None:
    """A missing session is rejected before the file is read."""
    app.dependency_overrides.pop(get_current_user, None)

    response = client.post(
        "/upload-report",
        files={"file": ("report.png", b"not-an-image", "image/png")},
    )

    assert response.status_code == 401
    assert "sign in" in response.json()["detail"].lower()


def test_reports_are_private_to_the_signed_in_user(client: TestClient) -> None:
    """Another user's report is hidden from the list and from simplify."""
    session = SessionLocal()
    try:
        owner = session.query(User).filter(User.supabase_uid == "test-user").one()
        other = (
            session.query(User)
            .filter(User.supabase_uid == "other-user")
            .one_or_none()
        )
        if other is None:
            other = User(supabase_uid="other-user")
            session.add(other)
            session.commit()
            session.refresh(other)
        session.add(
            Report(
                user_id=owner.id,
                original_text="mine",
                image_path="mine.png",
                ocr_confidence=90,
            )
        )
        secret = Report(
            user_id=other.id,
            original_text="secret",
            image_path="secret.png",
            ocr_confidence=90,
        )
        session.add(secret)
        session.commit()
        secret_id = secret.id
    finally:
        session.close()

    listed = client.get("/reports")
    assert listed.status_code == 200
    paths = [row["image_path"] for row in listed.json()]
    assert "mine.png" in paths
    assert "secret.png" not in paths

    denied = client.post("/simplify-report", json={"report_id": secret_id})
    assert denied.status_code == 404


def _dob(years_ago: int) -> str:
    """ISO date of someone who turned ``years_ago`` a month ago."""
    today = date.today()
    month = today.month - 1 or 12
    year = today.year - years_ago - (1 if today.month == 1 else 0)
    return date(year, month, 1).isoformat()


def test_profile_crud_removes_reports_on_delete(client: TestClient) -> None:
    """Create, read, update, and delete the signed-in profile."""
    assert client.delete("/profile").status_code == 200
    created = client.get("/profile")
    assert created.status_code == 200
    assert created.json()["onboarding_complete"] is False

    saved = client.put(
        "/profile",
        json={
            "name": "  Faizan  ",
            "date_of_birth": _dob(28),
            "sex_at_birth": "Male",
            "consent": {"terms": True, "health_data": True},
            "weight_kg": 72.5,
            "height_cm": 175,
            "conditions": "Asthma",
            "medications": "",
            "allergies": "Peanuts",
        },
    )
    assert saved.status_code == 200
    body = saved.json()
    assert body["name"] == "Faizan"
    assert body["sex_at_birth"] == "male"
    assert body["sex"] == "male"
    assert body["age"] == 28
    assert body["weight_kg"] == 72.5
    assert body["weight"] == 72.5
    assert body["height_cm"] == 175
    assert body["conditions"] == "Asthma"
    assert body["onboarding_complete"] is True

    again = client.get("/profile")
    assert again.status_code == 200
    assert again.json()["allergies"] == "Peanuts"

    session = SessionLocal()
    try:
        session.add(
            Report(
                user_id=body["id"],
                original_text="owned",
                image_path="owned.png",
                ocr_confidence=80,
            )
        )
        session.commit()
    finally:
        session.close()
    assert any(
        row["image_path"] == "owned.png" for row in client.get("/reports").json()
    )

    deleted = client.delete("/profile")
    assert deleted.status_code == 200
    assert deleted.json()["deleted"] is True

    fresh = client.get("/profile")
    assert fresh.status_code == 200
    assert fresh.json()["onboarding_complete"] is False
    # The account survives (name stays); every health answer is gone.
    assert fresh.json()["name"] == "Faizan"
    assert fresh.json()["allergies"] == ""
    assert fresh.json()["date_of_birth"] is None
    assert fresh.json()["sex_at_birth"] is None
    assert fresh.json()["weight_kg"] is None
    assert client.get("/reports").json() == []


def test_profile_rejects_an_impossible_age(client: TestClient) -> None:
    response = client.put(
        "/profile",
        json={"age": 0, "weight": 70, "height": 170, "sex": "female"},
    )

    assert response.status_code == 422
    assert "age" in response.json()["detail"].lower()


# ---- Sprint 3: questionnaire profile ----


def _consented_profile(client: TestClient, **extra: object) -> dict[str, object]:
    """Reset the test user and store the required sign-up answers."""
    assert client.delete("/profile").status_code == 200
    payload: dict[str, object] = {
        "name": "Muhammad",
        "date_of_birth": "1990-05-14",
        "sex_at_birth": "female",
        "consent": {"terms": True, "health_data": True},
    }
    payload.update(extra)
    response = client.put("/profile", json=payload)
    assert response.status_code == 200, response.json()
    return response.json()


def test_profile_payload_matches_the_contract_shape(client: TestClient) -> None:
    body = _consented_profile(
        client,
        conditions="Diabetes, Hypertension",
        allergies="Penicillin",
        takes_medicines=True,
        medications="Metformin 500 mg, Amlodipine",
        first_goal="reports",
        height_cm=172,
        weight_kg=68,
    )

    assert set(body) == {
        "id",
        "name",
        "email",
        "date_of_birth",
        "age",
        "sex_at_birth",
        "consent",
        "conditions",
        "allergies",
        "takes_medicines",
        "medications",
        "pregnancy_status",
        "prostate_urinary_issue",
        "first_goal",
        "height_cm",
        "weight_kg",
        "weight",
        "height",
        "sex",
        "onboarding_complete",
    }
    assert body["date_of_birth"] == "1990-05-14"
    assert body["age"] == (date.today().year - 1990) - (1 if (date.today().month, date.today().day) < (5, 14) else 0)
    assert body["email"] is None
    assert body["takes_medicines"] is True
    assert body["first_goal"] == "reports"
    assert body["height_cm"] == 172.0
    assert body["onboarding_complete"] is True


def test_profile_partial_update_keeps_other_fields(client: TestClient) -> None:
    _consented_profile(client, conditions="Asthma", weight_kg=70)

    response = client.put("/profile", json={"allergies": "Peanuts"})

    assert response.status_code == 200
    body = response.json()
    assert body["allergies"] == "Peanuts"
    assert body["conditions"] == "Asthma"
    assert body["weight_kg"] == 70.0
    assert body["name"] == "Muhammad"
    assert body["onboarding_complete"] is True


def test_profile_onboarding_needs_name_dob_sex_and_consent(client: TestClient) -> None:
    assert client.delete("/profile").status_code == 200
    client.put("/profile", json={"name": None})

    step = client.put("/profile", json={"name": "Muhammad", "date_of_birth": "1990-05-14"})
    assert step.json()["onboarding_complete"] is False

    step = client.put("/profile", json={"sex_at_birth": "prefer not to say"})
    assert step.json()["sex_at_birth"] == "prefer_not_to_say"
    assert step.json()["onboarding_complete"] is False

    step = client.put("/profile", json={"consent": {"terms": True}})
    assert step.json()["consent"] is None
    assert step.json()["onboarding_complete"] is False

    step = client.put("/profile", json={"consent": {"health_data": True}})
    assert step.json()["consent"]["terms"] is True
    assert step.json()["onboarding_complete"] is True


def test_profile_rejects_under_18_and_stores_nothing(client: TestClient) -> None:
    _consented_profile(client, name="Muhammad")

    response = client.put(
        "/profile",
        json={"name": "Teenager", "date_of_birth": _dob(16), "weight_kg": 50},
    )

    assert response.status_code == 422
    assert response.json()["detail"] == (
        "MedAIx is for adults. A parent or guardian can use it for you."
    )
    stored = client.get("/profile").json()
    assert stored["name"] == "Muhammad"
    assert stored["date_of_birth"] == "1990-05-14"
    assert stored["weight_kg"] is None


def test_profile_accepts_someone_who_turned_18_recently(client: TestClient) -> None:
    response = client.put("/profile", json={"date_of_birth": _dob(18)})

    assert response.status_code == 200
    assert response.json()["age"] == 18


@pytest.mark.parametrize(
    ("payload", "message"),
    [
        ({"name": "A"}, "Use a name between 2 and 60 characters."),
        ({"name": "x" * 61}, "Use a name between 2 and 60 characters."),
        ({"date_of_birth": "2999-01-01"}, "Enter a date of birth in the past."),
        ({"date_of_birth": "1899-12-31"}, "Enter a date of birth after 1900."),
        ({"date_of_birth": "yesterday"}, "Enter your date of birth as a date (YYYY-MM-DD)."),
        ({"height_cm": 49}, "Enter a height in centimetres, from 50 to 250."),
        ({"height_cm": 251}, "Enter a height in centimetres, from 50 to 250."),
        ({"weight_kg": 1}, "Enter a weight in kilograms, from 2 to 400."),
        ({"weight_kg": 401}, "Enter a weight in kilograms, from 2 to 400."),
        ({"sex_at_birth": "unknown"}, "Choose female, male, or prefer not to say."),
        ({"first_goal": "sleep"}, "Choose reports, medicines, condition, or habits."),
        ({"pregnancy_status": "maybe"}, "Choose no, pregnant, breastfeeding, or prefer not to say."),
        ({"prostate_urinary_issue": "sometimes"}, "Choose no, yes, or prefer not to say."),
        ({"takes_medicines": "sometimes"}, "Answer yes or no to whether you take regular medicines."),
    ],
)
def test_profile_validation_messages(client: TestClient, payload: dict, message: str) -> None:
    response = client.put("/profile", json=payload)

    assert response.status_code == 422
    assert response.json()["detail"] == message


def test_profile_consent_is_stamped_with_version_and_time(client: TestClient) -> None:
    before = utc_now().replace(microsecond=0)

    body = _consented_profile(client)

    consent = body["consent"]
    assert consent["terms"] is True
    assert consent["health_data"] is True
    assert consent["version"] == CONSENT_VERSION == "2026-10"
    assert datetime.fromisoformat(consent["accepted_at"]) >= before


def test_profile_consent_cannot_be_withdrawn_by_put(client: TestClient) -> None:
    _consented_profile(client)

    for payload in ({"terms": False}, {"health_data": False}, {"terms": True, "health_data": False}):
        response = client.put("/profile", json={"consent": payload})
        assert response.status_code == 422
        assert response.json()["detail"] == (
            "Consent can only be withdrawn by deleting your health data."
        )

    assert client.get("/profile").json()["consent"]["terms"] is True


def test_profile_delete_clears_consent_and_health_answers(client: TestClient) -> None:
    _consented_profile(client, conditions="Diabetes", takes_medicines=True, first_goal="habits")

    assert client.delete("/profile").json() == {"deleted": True}

    body = client.get("/profile").json()
    assert body["consent"] is None
    assert body["conditions"] == ""
    assert body["takes_medicines"] is None
    assert body["first_goal"] is None
    assert body["date_of_birth"] is None
    assert body["age"] is None
    assert body["sex_at_birth"] is None
    assert body["name"] == "Muhammad"
    assert body["onboarding_complete"] is False


def test_profile_pregnancy_status_only_for_female(client: TestClient) -> None:
    female = _consented_profile(client, sex_at_birth="female", pregnancy_status="Breastfeeding")
    assert female["pregnancy_status"] == "breastfeeding"

    male = _consented_profile(client, sex_at_birth="male", pregnancy_status="pregnant")
    assert male["pregnancy_status"] is None

    # Changing group drops the answer that no longer applies.
    _consented_profile(client, sex_at_birth="female", pregnancy_status="no")
    switched = client.put("/profile", json={"sex_at_birth": "prefer_not_to_say"}).json()
    assert switched["pregnancy_status"] is None


def test_profile_prostate_question_only_for_men_over_40(client: TestClient) -> None:
    older_man = _consented_profile(
        client, sex_at_birth="male", date_of_birth=_dob(45), prostate_urinary_issue="Yes"
    )
    assert older_man["prostate_urinary_issue"] == "yes"

    younger_man = _consented_profile(
        client, sex_at_birth="male", date_of_birth=_dob(30), prostate_urinary_issue="yes"
    )
    assert younger_man["prostate_urinary_issue"] is None

    woman = _consented_profile(
        client, sex_at_birth="female", date_of_birth=_dob(45), prostate_urinary_issue="yes"
    )
    assert woman["prostate_urinary_issue"] is None


def test_profile_accepts_legacy_keys(client: TestClient) -> None:
    assert client.delete("/profile").status_code == 200

    response = client.put(
        "/profile",
        json={"age": 52, "weight": 80, "height": 170, "sex": "other"},
    )

    assert response.status_code == 200
    body = response.json()
    assert body["age"] == 52  # no date of birth, so the legacy age is reported
    assert body["weight_kg"] == 80.0 and body["weight"] == 80.0
    assert body["height_cm"] == 170.0 and body["height"] == 170.0
    assert body["sex_at_birth"] == "prefer_not_to_say"
    assert body["sex"] == "prefer_not_to_say"
    assert body["date_of_birth"] is None


def test_add_missing_user_columns_upgrades_a_legacy_table(tmp_path) -> None:
    """A users table from before Sprint 3 gains the new columns, idempotently."""
    legacy = create_engine(f"sqlite:///{tmp_path / 'legacy.db'}")
    with legacy.begin() as connection:
        connection.execute(
            text(
                "CREATE TABLE users ("
                "id INTEGER PRIMARY KEY, supabase_uid VARCHAR NOT NULL, "
                "name VARCHAR, age INTEGER, weight FLOAT, height FLOAT, sex VARCHAR, "
                "conditions TEXT, medications TEXT, allergies TEXT, created_at TIMESTAMP)"
            )
        )
        connection.execute(text("INSERT INTO users (supabase_uid, name) VALUES ('u1', 'Old')"))

    added = database.add_missing_user_columns(bind=legacy)

    assert set(added) == {
        "email",
        "date_of_birth",
        "sex_at_birth",
        "consent_terms",
        "consent_health_data",
        "consent_version",
        "consent_accepted_at",
        "takes_medicines",
        "pregnancy_status",
        "prostate_urinary_issue",
        "first_goal",
    }
    columns = {column["name"] for column in inspect(legacy).get_columns("users")}
    assert set(added) <= columns
    with legacy.connect() as connection:
        row = connection.execute(
            text("SELECT name, date_of_birth, consent_terms FROM users")
        ).one()
    assert row == ("Old", None, None)
    assert database.add_missing_user_columns(bind=legacy) == []


def test_add_missing_user_columns_without_table_is_a_no_op(tmp_path) -> None:
    empty = create_engine(f"sqlite:///{tmp_path / 'empty.db'}")

    assert database.add_missing_user_columns(bind=empty) == []


# ---- Sprint 3: /risk-trends ----


def _seed_reports(client: TestClient, texts: list[str]) -> list[int]:
    owner_id = client.get("/profile").json()["id"]
    session = SessionLocal()
    try:
        ids = []
        for index, body in enumerate(texts):
            report = Report(
                user_id=owner_id,
                original_text=body,
                image_path=f"seed-{index}.png",
                ocr_confidence=90,
                uploaded_at=datetime(2026, 3 + 3 * index, 2, 9, 0),
            )
            session.add(report)
            session.commit()
            ids.append(report.id)
        return ids
    finally:
        session.close()


def test_risk_trends_flags_a_rising_hba1c_streak(client: TestClient) -> None:
    _consented_profile(client, sex_at_birth="female", conditions="Diabetes")
    ids = _seed_reports(
        client,
        [
            "HbA1c 5.9 % 4.0-6.0\nHaemoglobin 13.1 g/dL",
            "HbA1c 6.1 %\nHaemoglobin 13.0 g/dL",
            "HbA1c 6.4 % 4.0 - 6.0\nHaemoglobin 13.2 g/dL",
        ],
    )

    response = client.get("/risk-trends")

    assert response.status_code == 200
    body = response.json()
    assert body["reports_count"] == 3
    assert body["needs_reports"] is False
    assert body["focus_markers"] == ["HbA1c", "Fasting glucose"]
    assert body["insight"] == {
        "marker": "HbA1c",
        "title": "Your HbA1c has risen across 3 reports",
        "body": "5.9 in March to 6.4 now. Worth raising with your doctor.",
    }
    hba1c, haemoglobin = body["trends"]
    assert hba1c["marker"] == "HbA1c"
    assert hba1c["focus"] is True
    assert hba1c["range"]["source"] == "report"
    assert hba1c["alert"]["code"] == "rising_streak"
    assert hba1c["alert"]["level"] == "error"
    assert [point["report_id"] for point in hba1c["points"]] == ids
    assert [point["label"] for point in hba1c["points"]] == ["Mar", "Jun", "Sep"]
    assert haemoglobin["marker"] == "Haemoglobin"
    assert haemoglobin["range"] == {
        "low": 12.0,
        "high": 15.5,
        "label": "Normal range 12.0–15.5 g/dL",
        "source": "default",
    }
    assert haemoglobin["alert"] is None


def test_risk_trends_needs_two_reports(client: TestClient) -> None:
    _consented_profile(client)
    _seed_reports(client, ["HbA1c 9.5 %"])

    body = client.get("/risk-trends").json()

    assert body["reports_count"] == 1
    assert body["needs_reports"] is True
    assert body["insight"] is None
    assert [trend["marker"] for trend in body["trends"]] == ["HbA1c"]
    assert body["trends"][0]["alert"] is None


def test_risk_trends_is_private_to_the_signed_in_user(client: TestClient) -> None:
    _consented_profile(client)
    session = SessionLocal()
    try:
        other = session.query(User).filter(User.supabase_uid == "other-user").one_or_none()
        if other is None:
            other = User(supabase_uid="other-user")
            session.add(other)
            session.commit()
        session.add(Report(user_id=other.id, original_text="HbA1c 9.9 %", ocr_confidence=90))
        session.commit()
    finally:
        session.close()

    body = client.get("/risk-trends").json()

    assert body["reports_count"] == 0
    assert body["trends"] == []


def test_risk_trends_requires_sign_in(client: TestClient) -> None:
    app.dependency_overrides.pop(get_current_user, None)

    assert client.get("/risk-trends").status_code == 401


def test_list_reports_uses_panel_title_not_letterhead(client: TestClient) -> None:
    client.post(
        "/upload-report",
        files={"file": ("cbc.png", _lab_report_image(), "image/png")},
    )

    row = next(r for r in client.get("/reports").json() if r["image_path"] == "cbc.png")

    assert row["title"] == "Complete blood count"
    assert row["derived_title"] == "Complete blood count"
    assert row["report_date"]
    assert "attention_count" in row
    assert row["title"] != "CITY LAB"


def test_patient_can_rename_a_report(client: TestClient) -> None:
    uploaded = client.post(
        "/upload-report",
        files={"file": ("cbc.png", _lab_report_image(), "image/png")},
    ).json()

    renamed = client.patch(f"/reports/{uploaded['id']}", json={"title": "My CBC"})
    listed = next(r for r in client.get("/reports").json() if r["id"] == uploaded["id"])

    assert renamed.status_code == 200
    assert renamed.json()["title"] == "My CBC"
    assert listed["title"] == "My CBC"
    assert listed["derived_title"] == "Complete blood count"


def test_sign_in_copies_email_from_the_token(client: TestClient, monkeypatch: pytest.MonkeyPatch) -> None:
    import auth as auth_module

    app.dependency_overrides.pop(get_current_user, None)
    monkeypatch.setattr(
        auth_module,
        "verify_access_token",
        lambda _token: {"sub": "jwt-user", "email": "Ada@Example.com"},
    )

    body = client.get("/profile", headers={"Authorization": "Bearer fake"}).json()

    assert body["email"] == "ada@example.com"
