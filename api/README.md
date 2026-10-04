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

`api/database.py` reads the URL in this order, first match wins:

1. Real process environment (`DATABASE_URL`, then `NEON_DATABASE_URL`)
2. `api/.env` (hand-written local settings)
3. repo-root `.env.local` (where `neon link` / `neon env pull` write)
4. `sqlite:///./medaix.db` — the last-resort fallback

Store report images and medicine photos in Firebase Storage, not Postgres —
Neon's free tier is 0.5 GB and structured rows are what belong there.

### Which database is production actually using?

```bash
curl -s https://medaix.onrender.com/health
```

```json
{"status": "ok", "database": "postgres"}
```

`database: "sqlite"` means the deployed service is writing to a throwaway disk.
The value is derived from the configured URL and never opens a connection, so it
stays cheap enough for the keep-alive ping to hit.

### ⚠️ SQLite on Render is ephemeral

Render gives every deploy a fresh disk, so a SQLite file is **deleted on each
redeploy or restart**. At Week 0 only `/health` exists so nothing is actually
lost, and `warn_if_ephemeral()` logs a warning at startup to make that visible.

### Pointing production at Neon (required before real data lands)

Production is **not** on Neon yet — it still runs on ephemeral SQLite. Both steps
below are one-time dashboard configuration; neither can be done from the repo.

**1. Add the connection string to the service**

Render → `medaix-api` → **Environment** → *Add Environment Variable*:

| Key | Value |
| --- | --- |
| `NEON_DATABASE_URL` | `postgresql://neondb_owner:<password>@ep-rough-heart-b3am3e5t-pooler.c-4.ap-southeast-1.aws.neon.tech/neondb?sslmode=require` |

Use the **pooled** host (`-pooler`), never the direct one. Save, then redeploy —
Render only applies env changes on a new deploy.

**2. Make pushes actually deploy**

Every push to `main` currently reports success while deploying nothing, because
`RENDER_DEPLOY_HOOK_URL` is unset and the deploy step skipped it. That step now
**fails loudly** instead of skipping, so a green `API Deploy` run means a deploy
actually happened.

Copy the hook from Render → `medaix-api` → **Settings** → **Deploys** →
*Deploy hook* (also shown as the URL behind the blue status badge), then:

```bash
gh secret set RENDER_DEPLOY_HOOK_URL --repo tahasync/MedAIx
```

Verify both landed:

```bash
curl -s https://medaix.onrender.com/health   # expect "database": "postgres"
```

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