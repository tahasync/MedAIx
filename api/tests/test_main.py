"""Tests for the Week 0 API scaffold.

Runs against an isolated SQLite file so a local `medaix.db` is never touched.
"""

import os

import pytest
from fastapi.testclient import TestClient

os.environ.setdefault("DATABASE_URL", "sqlite:///./test_medaix.db")

import database
from main import app  # noqa: E402


@pytest.fixture()
def client() -> TestClient:
    return TestClient(app)


def test_health_returns_ok(client: TestClient) -> None:
    """Given the API is running, when GET /health is called, then it reports ok."""
    response = client.get("/health")

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


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