"""Tests for the Week 0 API scaffold.

Runs against an isolated SQLite file so a local `medaix.db` is never touched.
"""

import os

import pytest
from fastapi.testclient import TestClient

os.environ.setdefault("DATABASE_URL", "sqlite:///./test_medaix.db")

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