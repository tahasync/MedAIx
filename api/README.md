# MedAIx API

FastAPI backend for MedAIx. Sprint 1 includes `/health` and `/upload-report`
with English, Urdu-script, and Roman Urdu OCR modes; Sprint 2 added
simplification, report listing and the profile; Sprint 3 added the
questionnaire profile and rule-based `/risk-trends`.

## Endpoints

All routes except `/health` need `Authorization: Bearer <Supabase access token>`.

| Method | Route | Purpose |
| --- | --- | --- |
| GET | `/health` | Liveness plus which database backend is configured |
| POST | `/upload-report` | OCR a report image/PDF (`file`, optional `language`) and store the text |
| POST | `/simplify-report` | `{"report_id": n}` → plain-language version of a stored report |
| GET | `/reports` | The signed-in user's reports, newest first |
| GET | `/profile` | Questionnaire answers + `onboarding_complete` |
| PUT | `/profile` | Partial update: only the keys sent change (see below) |
| DELETE | `/profile` | Clears every health answer, consent and stored reports; name/email stay |
| GET | `/risk-trends` | Lab values parsed from every report, grouped per marker, with rule-based alerts |

### `/profile` fields (Sprint 3 questionnaire)

`name` (2–60), `date_of_birth` (ISO date, must be 18+), `sex_at_birth`
(`female` / `male` / `prefer_not_to_say`), `consent` (`{"terms": true,
"health_data": true}` — the server stamps `version` and `accepted_at`; it can
only be withdrawn with `DELETE`), `conditions`, `allergies`, `takes_medicines`,
`medications`, `pregnancy_status` (stored for female only),
`prostate_urinary_issue` (stored for men 40+ only), `first_goal`
(`reports` / `medicines` / `condition` / `habits`), `height_cm` (50–250),
`weight_kg` (2–400). `age` is derived from `date_of_birth`. The legacy keys
`age`, `weight`, `height`, `sex` are still accepted and echoed.
`onboarding_complete` = name + date of birth + sex at birth + both consents.
Validation errors are 422 with a plain-language `detail` the app shows as-is.

### `/risk-trends`

Returns `reports_count`, `needs_reports` (true until 2 reports exist),
`focus_markers` (from the profile's conditions), one `insight` and a `trends`
list: per marker the unit, the reference range (printed on the report, else a
default by sex at birth), `direction`, dated `points` with `ok`/`warn`/`error`
status and an optional `alert` (`rising_streak`, `falling_streak`,
`crossed_high`, `crossed_low`, `out_of_range`). Pure rules in `trends.py`;
values are echoed exactly as OCR printed them.

## Requirements

Python 3.12+ and [`uv`](https://docs.astral.sh/uv/). No `requirements.txt`, no
manual `venv` — dependencies are declared in `pyproject.toml` and locked in
`uv.lock`.

## Setup

```bash
cd api
uv sync --dev
```

### OCR language data

Sprint 1 supports three upload modes: English (`eng`), Urdu script (`urd+eng`),
and Roman Urdu (`eng`, because it uses Latin letters). `pytesseract` is only a
Python wrapper; the Tesseract executable and traineddata files must also be
installed. The API checks the selected language data and returns a setup error
instead of failing the upload with an internal server error.

On Ubuntu/Debian, install both language packs with:

```bash
sudo apt-get update
sudo apt-get install -y tesseract-ocr tesseract-ocr-eng tesseract-ocr-urd
```

On Windows, install Tesseract, then run this from the `api` directory:

```powershell
.\setup_ocr_languages.ps1
```

The script copies the existing English model and downloads the Urdu model into
an ignored project-local `.tessdata` directory, so it does not need to write to
`Program Files`. English and Roman Urdu continue to use the English model.
For the existing Render service, set its Build Command to the value shown in
the deployment table below so the hosted instance installs both models too. (See "Deploying to Render": the service now runs as a Docker image that bakes in Tesseract + both traineddata packs.)

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

Store report images and medicine photos in Supabase Storage, not Postgres —
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
| `NEON_DATABASE_URL` | `postgresql://<user>:<password>@<endpoint>-pooler.<region>.aws.neon.tech/<database>?sslmode=require` (copy it from the Neon console → *Connection string*, pooled) |

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
| Environment | **Docker** — uses `api/Dockerfile` |
| Build | Handled by `Dockerfile` (installs Tesseract eng+urd, then `uv sync --frozen --no-dev`) |
| Start | Handled by `Dockerfile` `CMD` (`uvicorn main:app --host 0.0.0.0 --port $PORT`) |
| Health Check Path | `/health` |
| `PYTHON_VERSION` | `3.12.11` |
| Plan / Region | Free / Singapore |

**Why Docker, not a native build command.** Tesseract is not part of Render's
native Python runtime, and `apt-get install` run inside a native build command
does **not** persist into the runtime container — the binary is gone by the time
a request arrives, so every upload returned `503 Tesseract is not installed`.
Deploying the `api/Dockerfile` image is Render's documented way to ship a system
dependency it does not preinstall. To switch an existing native service over,
set **Environment → Docker** in the Render dashboard (this is a one-time
dashboard change; the API Deploy workflow's deploy hook then rebuilds the image
on the next push to `main`).

Verified locally by building the image and running it: `/health` returns 200 and
`/upload-report` returns extracted text (87.3% confidence) with `tesseract 5.5.0`
and `eng`/`urd` present inside the container.

Two notes on the free tier:

- **Cold starts.** The instance sleeps after ~15 idle minutes and takes up to
  ~50s to wake. `.github/workflows/keep-alive.yml` pings `/health` every 10
  minutes to hold it resident; GitHub Actions can delay those runs under load,
  so an occasional slow first request is expected. The app retries transient
  failures three times before reporting an error.
- **Region is permanent.** Render cannot move an existing service between
  regions, so Singapore is fixed for this service.

The app runs straight from the venv the image built (`/app/.venv/bin/uvicorn`),
so there is no `uv run` on the start path and no `VIRTUAL_ENV` path warning.
