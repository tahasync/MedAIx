# MedAIx API

FastAPI backend for MedAIx. Week 0 scaffold — currently just `/health`.

## Requirements

Python 3.12+ and [`uv`](https://docs.astral.sh/uv/). No `requirements.txt`, no
manual `venv` — dependencies are declared in `pyproject.toml` and locked in
`uv.lock`.

## Setup

```bash
cd api
uv sync --dev
```

## Run

```bash
uv run uvicorn main:app --reload --port 8000
```

- Health: <http://localhost:8000/health>
- Swagger docs: <http://localhost:8000/docs>

## Test

```bash
uv run pytest -v
```

## Database

Defaults to SQLite at `./medaix.db`. Set `DATABASE_URL` (or `NEON_DATABASE_URL`)
to point at Neon Postgres — use the **pooled** connection string (the one whose
hostname contains `-pooler`) so a single Render dyno doesn't exhaust direct
connections.

Store report images and medicine photos in Firebase Storage, not Postgres —
Neon's free tier is 0.5 GB and structured rows are what belong there.

### ⚠️ SQLite on Render is ephemeral

Render gives every deploy a fresh disk, so a SQLite file is **deleted on each
redeploy or restart**. At Week 0 only `/health` exists so nothing is actually
lost, and `warn_if_ephemeral()` logs a warning at startup to make that visible.

Do this before Sprint 12 or real rows will disappear:

1. Create a Neon project and copy its **pooled** connection string.
2. Add it to the Render service's environment as `NEON_DATABASE_URL`.
3. Confirm the startup warning is gone — that confirms Postgres is in use.

## Deploying to Render

Configured and live at <https://medaix.onrender.com>.

| Setting | Value |
| --- | --- |
| Root Directory | `api` |
| Build Command | `uv sync --frozen --no-dev` |
| Start Command | `uv run --no-dev uvicorn main:app --host 0.0.0.0 --port $PORT` |
| Health Check Path | `/health` |
| `PYTHON_VERSION` | `3.12.11` |
| Plan / Region | Free / Singapore |

`--no-dev` on the **start** command matters: without it `uv run` re-installs the
dev group (pytest, httpx, ~1.2 MB) on every cold start.

Two notes on the free tier:

- **Cold starts.** The instance sleeps after ~15 idle minutes and takes up to
  ~50s to wake. `.github/workflows/keep-alive.yml` pings `/health` every 10
  minutes to hold it resident; GitHub Actions can delay those runs under load,
  so an occasional slow first request is expected. The app retries transient
  failures three times before reporting an error.
- **Region is permanent.** Render cannot move an existing service between
  regions, so Singapore is fixed for this service.

The `VIRTUAL_ENV ... does not match` warning is expected and harmless: because
the root directory is `api`, uv uses `api/.venv` (where `uv sync` installed the
dependencies) and ignores the path Render advertises.