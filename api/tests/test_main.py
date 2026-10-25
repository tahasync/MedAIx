"""Tests for the Week 0 API scaffold.

Runs against an isolated SQLite file so a local `medaix.db` is never touched.
"""

import io
import os

import pytest
from fastapi import Depends
from fastapi.testclient import TestClient
from PIL import Image, ImageDraw, ImageFont
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
from models import Report, User  # noqa: E402


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


def test_profile_crud_removes_reports_on_delete(client: TestClient) -> None:
    """Create, read, update, and delete the signed-in profile."""
    created = client.get("/profile")
    assert created.status_code == 200
    assert created.json()["onboarding_complete"] is False

    saved = client.put(
        "/profile",
        json={
            "name": "  Faizan  ",
            "age": 28,
            "weight": 72.5,
            "height": 175,
            "sex": "Male",
            "conditions": "Asthma",
            "medications": "",
            "allergies": "Peanuts",
        },
    )
    assert saved.status_code == 200
    body = saved.json()
    assert body["name"] == "Faizan"
    assert body["sex"] == "male"
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
    # A blank profile, not the old one: SQLite may reuse the deleted row id,
    # so the reset is checked through the fields rather than the id.
    assert fresh.json()["name"] is None
    assert fresh.json()["allergies"] == ""
    assert client.get("/reports").json() == []


def test_profile_rejects_an_impossible_age(client: TestClient) -> None:
    response = client.put(
        "/profile",
        json={"age": 0, "weight": 70, "height": 170, "sex": "female"},
    )

    assert response.status_code == 422
    assert "age" in response.json()["detail"].lower()
