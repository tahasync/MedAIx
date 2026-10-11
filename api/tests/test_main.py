"""Tests for the Week 0 API scaffold.

Runs against an isolated SQLite file so a local `medaix.db` is never touched.
"""

import io
import os

import pytest
from fastapi.testclient import TestClient
from PIL import Image, ImageDraw, ImageFont

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
from main import app  # noqa: E402


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
