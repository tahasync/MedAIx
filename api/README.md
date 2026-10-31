# MedAIx API

FastAPI backend for MedAIx. The Sprint 5 integration connects retry-safe report
upload/OCR, deterministic simplification, account-scoped profile and report
storage, rule-based numeric trends, and wellness logging. OCR supports English,
Urdu script, and Roman Urdu inputs.

## Endpoints

All routes except `/health` need `Authorization: Bearer <Supabase access token>`.

| Method | Route | Purpose |
| --- | --- | --- |
| GET | `/health` | Liveness plus which database backend is configured |
| POST | `/upload-report` | OCR a report image/PDF (`file`, optional `language`, optional `upload_id`) and store the text. Reusing `upload_id` safely returns the same report after an ambiguous client retry. |
| POST | `/simplify-report` | `{"report_id": n}` → plain-language version of a stored report |
| GET | `/reports` | The signed-in user's reports, newest first |
| GET | `/profile` | Questionnaire answers + `onboarding_complete` |
| PUT | `/profile` | Partial update: only the keys sent change (see below) |
| DELETE | `/profile` | Clears every health answer, consent and stored reports; name/email stay |
| GET | `/risk-trends` | Lab values parsed from every report, grouped per marker, with rule-based alerts |
| GET/POST | `/wellness/log` | Read daily totals or add an idempotent, account-scoped wellness entry |

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

### OCR and report summaries

OCR first uses Tesseract's single-column layout. Sparse or low-confidence pages
get a second local layout pass; the API keeps the pass with more validated lab
rows, then confidence as a tie-breaker. Trend coverage counts validated result
rows and recognized missing-value rows, not arbitrary digits from dates,
ages, phone numbers, or page fragments. Explicit qualitative outcomes count
toward report coverage but remain separate from numeric trend values.

Urine and stool summaries use a small offline character n-gram classifier to
match noisy OCR labels against an allowlist. It does not generate prose or
change a result, unit, or printed range. Patient-facing text is still rendered
by deterministic report-aware templates, with a reminder to check the source
report. This is not a diagnostic model and does not establish clinical
accuracy.

### OCR validation (2026-10-31)

The backend OCR and row parsers were run on 138 Train and 122 Test report
images. Every image yielded at least one numeric or explicit qualitative row;
there were no OCR execution errors. A manually transcribed sample of 12 Test
images (14 expected rows) scored 92.9% row-level precision, recall, and F1,
with all sampled rows matched on 11 of 12 images. Matching normalizes known
analyte aliases and allows up to 0.01 or 0.1% numeric tolerance. One remaining
miss was a decimal point lost by OCR. Since the dataset lacks paired ground
truth for the full splits, these sample scores are not full-dataset accuracy.

On this Windows development machine, sequential OCR plus parsing of the 122
Test images averaged 0.579 seconds per image (median 0.588 seconds, p95 0.808
seconds; 1.73 images/second), after three warm-up images. This excludes HTTP,
database, and network time and has no before/after baseline.

Run the repeatable sample-panel benchmark from `api/` with
`.venv/Scripts/python scripts/benchmark_ocr.py --runs 5`. It checks marker
recall and latency on six synthetic panels (upright and skewed); it is a
regression check, not a benchmark of arbitrary phone photos.

### Experimental local dengue classifier

The local training pipeline is separate from OCR simplification and from the
existing report/trend flow. It trains a small NumPy logistic classifier from a
CSV supplied by the developer. The CSV remains outside the repository, and
`api/local_models/` is gitignored. The pipeline evaluates a stratified 80/20
holdout and five-fold cross-validation; imputation and scaling are fitted
inside each training split. `differential_count` and `rbc_count` are excluded
because they contain only 0/1 values and their meaning is not documented.

```powershell
cd api
.venv\Scripts\python scripts\train_dengue_model.py 'C:\path\to\dataset.csv'
```

The experimental `POST /experimental/dengue-screening` endpoint is disabled by
default. It requires authentication, an explicit
`MEDAIX_DENGUE_SCREENING_ENABLED=true` server setting, and the local model
artifact. It returns only an uncalibrated model score and an out-of-training-
range notice; it is not a diagnosis, clinical risk tier, or treatment advice.
The dataset's source and redistribution license have not been verified, and
this model has no external clinical validation. Do not enable it for patient
care or include its artifact in a public build.

For the supplied 989-row CSV, the stratified holdout result was ROC-AUC 0.924,
recall 0.961, specificity 0.725, and Brier score 0.099. Five-fold cross-
validation mean ROC-AUC was 0.899 (SD 0.032). These are internal dataset
metrics only; the lower specificity means false positives remain common even
on this holdout, and the scores should not guide patient care.

### Experimental local anemia classifier

The supplied `anemia.csv` contains 1,421 rows with an explicit `Result` target.
Train it locally with:

```powershell
cd api
.venv\Scripts\python scripts\train_anemia_model.py 'D:\Fyp\Fyp material\DataSets\anemia.csv'
```

This creates the ignored `api/local_models/anemia_screening.json` artifact and
reports a stratified holdout plus five-fold cross-validation. The model excludes
`Gender` because the dataset's binary encoding is undocumented. Its experimental
`POST /experimental/anemia-screening` endpoint is separately disabled by
default; it requires authentication and `MEDAIX_ANEMIA_SCREENING_ENABLED=true`.
It is not called by report upload, trends, or the Flutter client. The score is
not a diagnosis or treatment recommendation.

The other supplied files were inspected but not used as labeled training/test
data: `CBC data_for_meandeley_csv.csv` and `cbc information.xlsx` contain CBC
measurements without a verified outcome target, while `Train/` and `Test/`
contain report images without paired ground-truth transcriptions. These can
support an unlabeled OCR compatibility review, but cannot produce supervised
accuracy or train a new OCR model until verified labels are provided. Dataset
provenance and redistribution rights also need confirmation before any artifact
is included in a public build.

For the supplied 1,421-row anemia CSV, the internal holdout ROC-AUC was 0.968,
recall 0.887, specificity 0.888, and Brier score 0.097. Five-fold mean ROC-AUC
was 0.973 (SD 0.002). These are internal dataset results only; they are not
evidence of clinical performance or external validation.

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
