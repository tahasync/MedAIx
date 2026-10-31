# MedAIx

MedAIx helps patients review photographed lab reports. The current Sprint 5
release connects report upload and OCR, deterministic plain-language
simplification, Supabase sign-in and profile storage, numeric risk trends, and
condition-aware wellness logging in one account-scoped flow. Later roadmap
features such as medication safety, medicine scanning, doctor matching, and QR
sharing are not part of this release.

> **Current milestone: Sprint 5 (Wk 9–10) — Integration Pass 1.** See
> [`docs/roadmap.md`](docs/roadmap.md) for scope, checks, and limitations.

## Live

| | |
|---|---|
| API | <https://medaix.onrender.com> |
| Health | <https://medaix.onrender.com/health> → `{"status":"ok","database":"postgres"}` |
| Swagger | <https://medaix.onrender.com/docs> |

The `database` field reports which backend is actually serving requests —
`postgres` or `sqlite`. A `sqlite` value means the deploy is writing to an
ephemeral disk and data will be lost on restart.

## Stack

| Layer | Choice |
|---|---|
| Frontend | Flutter + Riverpod |
| Backend | FastAPI + SQLAlchemy |
| Auth | Supabase Auth (Google + email); API verifies the JWT against the project JWKS |
| Database | Neon Postgres (pooled) |
| Hosting | Render free web service |
| CI/CD | GitHub Actions |

Zero paid infrastructure.

## Layout

```
.
├── app/            Flutter client  — path-filtered CI trigger
├── api/            FastAPI backend  — path-filtered CI trigger
├── docs/
│   ├── roadmap.md       32-week solo execution plan
│   └── color-system.md  locked brand palette + semantic states
└── .github/workflows/
    ├── api-deploy.yml   on api/**  — tests, then Render deploy hook
    ├── app-build.yml    on app/**  — builds + signs the APK
    ├── app-build-sprint.yml — validates app/** and builds the Sprint 5 debug APK artifact
    └── keep-alive.yml   cron */10  — keeps the free instance awake
```

## Getting started

### API

Requires Python 3.12+ and [uv](https://docs.astral.sh/uv/).

```bash
cd api
uv sync --dev
uv run uvicorn main:app --reload --port 8000
```

On Windows, install the English and Urdu OCR models once from PowerShell:

```powershell
cd api
.\setup_ocr_languages.ps1
```

- Health: <http://localhost:8000/health>
- Swagger: <http://localhost:8000/docs>
- Tests: `uv run pytest -v`

Endpoints other than `/health` require `Authorization: Bearer <Supabase access
token>`. See [`api/.env.example`](api/.env.example) for `SUPABASE_URL`.

| Route | Sprint | Purpose |
|---|---|---|
| `POST /upload-report` | 1 | OCR a report image/PDF and store extracted text; retry-safe with `upload_id` |
| `POST /simplify-report` | 2 | Build a deterministic plain-language report summary |
| `GET /reports` | 2 | The signed-in user's reports, newest first |
| `GET/PUT/DELETE /profile` | 2 | Onboarding answers and profile CRUD |
| `GET /risk-trends` | 3 | Numeric lab trends and rule-based alerts |
| `GET/POST /wellness/log` | 4 | Account-scoped daily wellness totals and entries |

On Linux, install the OCR binaries and language data with `apt-get`; see
[`api/README.md`](api/README.md#ocr-language-data) for local and Render setup.

### App

Requires Flutter.

```bash
cd app
flutter pub get
flutter run --dart-define=API_BASE_URL=http://localhost:8000 \
  --dart-define=SUPABASE_ANON_KEY=<publishable key>
```

On Windows with the Android emulator, `run-pixel4.bat` (emulator with host
GPU), `run-backend.bat` (API on `0.0.0.0:8000`), and `run-app.bat` (reads the
Supabase key from `api/.env` and targets `10.0.2.2:8000`) do this for you.

### Database

Reads `DATABASE_URL` (or `NEON_DATABASE_URL`) from the environment, then
`api/.env`, then the repo-root `.env.local`, falling back to SQLite. With
`neon link` run locally, `.env.local` is populated automatically and a local
run talks to the same Neon database as production.

## Deployment

Pushing API changes to `main` runs the API test suite and triggers the Render
deploy hook. Pushing an app change or a `v*` tag runs the app release workflow;
the Sprint 5 workflow builds a debug APK artifact. Creating a local tag does
not publish it or start a GitHub Actions run.

| Secret | Purpose |
|---|---|
| `RENDER_DEPLOY_HOOK_URL` | Render deploy hook, called by `api-deploy.yml` |
| `ANDROID_SIGNING_KEY` + keystore password/alias/key | APK signing |
| `SUPABASE_ANON_KEY` | Supabase public client key supplied at build time |
| `API_BASE_URL`, `API_HEALTH_URL`, `SUPABASE_URL` | Repository variables, not secrets |

`NEON_DATABASE_URL` is configured in the **Render service environment** rather
than as a GitHub secret, since that is the only place it is consumed.

### Uptime monitoring

The free Render tier sleeps after ~15 idle minutes and takes up to ~50s to wake.
`keep-alive.yml` pings `/health` every 10 minutes to hold it resident, but
GitHub delays scheduled runs under load — so pair it with an external monitor:

1. Sign up at <https://uptimerobot.com> (free tier: 5-minute interval, 50
   monitors, no credit card)
2. **Add New Monitor** → type **HTTP(s)**
3. Friendly name: `MedAIx API`
4. URL: `https://medaix.onrender.com/health`
5. Monitoring interval: **5 minutes** (the shortest the free plan offers)

Choose alert contacts that you monitor. The GitHub cron is best-effort and may
be delayed under load.

> Ping a real app route, never `/robots.txt` — Render answers that path itself
> even while spun down, so it never reaches the app and never resets the idle
> timer.

## Contributing

Follow the sprint cadence in [`docs/roadmap.md`](docs/roadmap.md): backend
first, then the screen that consumes it, then wire them together, then test.
Every screen ships empty/loading/error/success states in the same sprint it is
built — there is no separate QA pass.

## Documentation

- [`docs/roadmap.md`](docs/roadmap.md) — 32-week solo execution plan
- [`docs/color-system.md`](docs/color-system.md) — brand palette + semantic states
- [`api/README.md`](api/README.md) — backend specifics and Neon/Render setup
