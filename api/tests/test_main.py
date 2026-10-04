"""Tests for the Week 0 API scaffold.

Runs against an isolated SQLite file so a local `medaix.db` is never touched.
"""

import os

import pytest
from fastapi.testclient import TestClient

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