# MedAIx

AI-powered clinical decision support. Upload a lab report → OCR + NLP simplify
it into plain language → track it against a patient profile → flag risk trends →
check drug interactions → scan medicine packaging → recommend a specialist →
share a curated view with a doctor via time-limited QR.

> **Status: Week 0 (setup).** Infrastructure is production-ready — the API runs
> on Render against Neon Postgres, and CI/CD deploys on every merge to `main`.
> The only implemented endpoint is `/health`; feature work starts at Sprint 1.
> See [`docs/roadmap.md`](docs/roadmap.md) for the full 32-week plan.

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

- Health: <http://localhost:8000/health>
- Swagger: <http://localhost:8000/docs>
- Tests: `uv run pytest -v`

### App

Requires Flutter.

```bash
cd app
flutter pub get
flutter run --dart-define=API_BASE_URL=http://localhost:8000
```

### Database

Reads `DATABASE_URL` (or `NEON_DATABASE_URL`) from the environment, then
`api/.env`, then the repo-root `.env.local`, falling back to SQLite. With
`neon link` run locally, `.env.local` is populated automatically and a local
run talks to the same Neon database as production.

## Deployment

Pushing to `main` deploys to Render via GitHub Actions.

| Secret | Purpose |
|---|---|
| `RENDER_DEPLOY_HOOK_URL` | Render deploy hook, called by `api-deploy.yml` |
| `ANDROID_SIGNING_KEY` + keystore password/alias/key | APK signing |
| `API_BASE_URL`, `API_HEALTH_URL` | Repository variables, not secrets |

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

Leave the default alert contacts. Once added, Render stays "Live" rather than
cycling to "Suspended".

✅ **Configured** — an HTTP(s) monitor on `https://medaix.onrender.com/health`
at 5-minute intervals, alongside the GitHub cron. Both currently report up.

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