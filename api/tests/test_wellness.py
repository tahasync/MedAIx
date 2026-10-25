"""Sprint 4 daily wellness log API tests."""

from datetime import datetime, timezone
import os

import pytest
from fastapi import Depends
from fastapi.testclient import TestClient
from sqlalchemy.orm import Session

# Keep the test suite away from any developer-configured database URL before
# importing the database module (which also reads local .env files).
os.environ.setdefault("DATABASE_URL", "sqlite:///./test_medaix.db")

import auth  # noqa: E402
import database  # noqa: E402
import main as main_module
from database import SessionLocal, get_db  # noqa: E402
from main import app  # noqa: E402
from models import User, WellnessLog  # noqa: E402


@pytest.fixture(autouse=True)
def _signed_in_user():
    def _user(db: Session = Depends(get_db)) -> User:
        user = db.query(User).filter(User.supabase_uid == "test-user").one_or_none()
        if user is None:
            user = User(supabase_uid="test-user")
            db.add(user)
            db.commit()
        return user

    app.dependency_overrides[auth.get_current_user] = _user
    yield
    app.dependency_overrides.pop(auth.get_current_user, None)


@pytest.fixture
def client() -> TestClient:
    return TestClient(app)


@pytest.fixture
def wellness_user():
    db: Session = SessionLocal()
    user = db.query(User).filter(User.supabase_uid == "test-user").one()
    db.query(WellnessLog).filter(WellnessLog.user_id == user.id).delete()
    old_weight, old_conditions = user.weight, user.conditions
    user.weight = None
    user.conditions = None
    db.commit()
    try:
        yield user
    finally:
        db.query(WellnessLog).filter(WellnessLog.user_id == user.id).delete()
        user.weight, user.conditions = old_weight, old_conditions
        db.commit()
        db.close()


def _entry(**overrides: object) -> dict[str, object]:
    return {
        "client_id": "entry-1",
        "type": "water",
        "value": 250,
        "occurred_at": datetime.now(timezone.utc).isoformat(),
        "timezone_offset_minutes": 0,
        **overrides,
    }


def test_get_wellness_day_returns_empty_totals_goals_and_tip(
    client: TestClient,
    wellness_user: User,
) -> None:
    response = client.get("/wellness/log")

    assert response.status_code == 200
    body = response.json()
    assert body["water_ml"] == 0
    assert body["water_goal_ml"] == 2100
    assert body["steps"] == 0
    assert body["step_goal"] == 6000
    assert body["exercise_label"] is None
    assert body["daily_tip"]


def test_water_entries_accumulate_and_replay_is_idempotent(
    client: TestClient,
    wellness_user: User,
) -> None:
    first = client.post("/wellness/log", json=_entry())
    replay = client.post("/wellness/log", json=_entry())
    second = client.post(
        "/wellness/log",
        json=_entry(client_id="entry-2", value=500),
    )

    assert first.status_code == 200
    assert replay.status_code == 200
    assert second.status_code == 200
    assert first.json()["water_ml"] == 250
    assert replay.json()["water_ml"] == 250
    assert second.json()["water_ml"] == 750
    db: Session = SessionLocal()
    try:
        assert len(
            db.query(WellnessLog).filter_by(user_id=wellness_user.id).all()
        ) == 2
    finally:
        db.close()


def test_steps_and_exercise_are_saved_with_daily_totals(
    client: TestClient,
    wellness_user: User,
) -> None:
    steps = client.post(
        "/wellness/log",
        json=_entry(client_id="steps-1", type="steps", value=1200, label=None),
    )
    exercise = client.post(
        "/wellness/log",
        json=_entry(
            client_id="exercise-1",
            type="exercise",
            value=15,
            label="Walk",
        ),
    )

    assert steps.status_code == 200
    assert steps.json()["steps"] == 1200
    assert exercise.status_code == 200
    assert exercise.json()["exercise_label"] == "Walk"
    assert exercise.json()["exercise_minutes"] == 15


def test_profile_weight_and_conditions_set_cautious_starting_goals(
    client: TestClient,
    wellness_user: User,
) -> None:
    db: Session = SessionLocal()
    user = db.query(User).filter(User.id == wellness_user.id).one()
    user.weight = 70
    user.conditions = "Arthritis"
    db.commit()
    db.close()

    body = client.get("/wellness/log").json()

    assert body["water_goal_ml"] == 2100
    assert "saved weight" in body["water_goal_note"]
    assert body["step_goal"] == 4000
    assert "saved condition" in body["step_goal_note"]


@pytest.mark.parametrize(
    "condition",
    ["chronic kidney disease", "dialysis", "heart failure", "fluid restriction"],
)
def test_fluid_restriction_conditions_suppress_water_estimate(
    client: TestClient,
    wellness_user: User,
    condition: str,
) -> None:
    db: Session = SessionLocal()
    user = db.query(User).filter(User.id == wellness_user.id).one()
    user.weight = 70
    user.conditions = condition
    db.commit()
    db.close()

    body = client.get("/wellness/log").json()

    assert body["water_goal_ml"] is None
    assert "clinician" in body["water_goal_note"]
    assert "clinician" in body["daily_tip"]


def test_client_local_day_window_handles_utc_midnight(
    client: TestClient,
    wellness_user: User,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    frozen_now = datetime(2026, 10, 26, 1, 0)
    monkeypatch.setattr(main_module, "utc_now", lambda: frozen_now)
    occurred = datetime(2026, 10, 25, 21, 0, tzinfo=timezone.utc)

    response = client.post(
        "/wellness/log",
        json=_entry(
            client_id="late-pakistan-water",
            occurred_at=occurred.isoformat(),
            timezone_offset_minutes=300,
        ),
    )

    assert response.status_code == 200
    assert response.json()["date"] == "2026-10-26"
    assert response.json()["water_ml"] == 250


@pytest.mark.parametrize(
    ("kind", "value"),
    [("water", 2001), ("steps", 50001), ("exercise", 481)],
)
def test_wellness_rejects_unreasonable_single_entries(
    client: TestClient,
    wellness_user: User,
    kind: str,
    value: int,
) -> None:
    response = client.post(
        "/wellness/log",
        json=_entry(client_id=f"invalid-{kind}", type=kind, value=value),
    )

    assert response.status_code == 422
    assert response.json()["detail"] == "Check the habit entry and try again."
