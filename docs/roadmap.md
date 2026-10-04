# MedAIx — 32-Week Solo Execution Plan (Muhammad Taha Naeem)

> **Status:** Week 0 setup is complete — production runs on Neon Postgres, both
> workflows deploy green, and uptime is monitored by both `keep-alive.yml` (10-min
> cron) and UptimeRobot (5-min interval, 100% uptime, 0 incidents). The canonical
> visual spec is [`color-system.md`](color-system.md), which replaces the deleted
> `AGENTS.md`. Next up: **Sprint 1**.

Built on your existing stack/workflow from `foam-shop-erp`: Flutter + Riverpod + Firebase, GitHub Actions CI/CD, spec-first + OpenCode CLI build pattern. No group dependency — every sprint is sequenced so one person can execute it. **Zero-cost stack:** Render's free web service for backend hosting + Neon's free Postgres tier for the database — no Railway, no paid infra anywhere.

**Repo setup (Week 0):**
- **Single monorepo:** `tahasync/medaix/` with `/app` (Flutter) and `/api` (FastAPI) as top-level folders. One repo, one Trello board, one commit history.
- **CI/CD — three GitHub Actions workflows in the same repo:**
  - `.github/workflows/app-build.yml` — triggers on changes under `/app/**`, builds & signs the APK (copy your foam-shop-erp workflow, adjust paths + signing config).
  - `.github/workflows/api-deploy.yml` — triggers on changes under `/api/**`, runs tests, then `curl`s Render's deploy hook URL to trigger a deploy.
  - `.github/workflows/keep-alive.yml` — **scheduled cron, no path filter**, `schedule: - cron: '*/10 * * * *'`, curls the API's own `/health` route every 10 minutes so Render's free instance never crosses the 15-minute idle threshold that puts it to sleep. Must hit a real app route, not `/robots.txt` — Render answers that path itself even while the service is spun down, so it never reaches your app and never resets the idle timer.
- Add repo secrets: `RENDER_DEPLOY_HOOK_URL` (Render dashboard → service → Settings → Deploy Hook), `NEON_DATABASE_URL` (use Neon's pooled connection string — the one with `-pooler` in the hostname), `ANDROID_SIGNING_KEY` (reuse Foam Shop's if same keystore, else generate new).
- Confirm both workflows run green on a trivial commit (empty FastAPI `/health` route + empty Flutter splash screen) before building real features — this validates the whole pipeline early instead of debugging CI in Week 20.

**Solo working rhythm per 2-week sprint:**
- Days 1–4: Backend/AI logic (FastAPI endpoint + model/library integration)
- Days 5–8: Frontend (Flutter screen consuming that endpoint)
- Days 9–11: Wire together, fix integration bugs
- Days 12–14: Test against sample data, write down defects/notes, commit + push, update Trello

This "backend-first, then UI, then wire, then test" loop is the same shape as how you built the Foam Shop app's features one at a time — just applied per epic here.

---

## UX Requirement Baseline (applies to every screen, every sprint)

Source: `must-have-ux-feature-checklist.md`. Build these into each screen as you build it — not as a separate pass at the end:

| State | Requirement |
|---|---|
| Normal / Content | Must have |
| Empty | Must have — explain what belongs on the screen, why it's empty, one clear primary CTA |
| Loading | Must have — skeleton/placeholder matching real layout size, no blank screen, real progress where measurable |
| Error | Must have — plain-language message, never a raw exception/stack trace, clear recovery + retry action, tell the user whether their data is safe |
| Success | Must have — confirm what happened, make the next step obvious |
| Offline | Must have for anything that syncs (report upload, wellness logs, QR sessions) — save locally, sync later, no data loss |
| Permission Denied | Required when applicable (camera, notifications, storage) — explain why before asking, offer a fallback on denial |
| First Use / Onboarding | Must have — short, one meaningful first action, progress indicator + skip option if multi-step |
| Disabled | Required when applicable |

CTA labels are action-oriented ("Try again", "View report", "Continue offline") rather than generic ("OK", "Submit", "Done"). Settings screen follows the Preferences / Account / Help & Support structure (§6 of the checklist).

---

## SEMESTER 1 — Weeks 1–16

### Week 0 — Setup
- FastAPI skeleton (`/health` endpoint working), Postgres/SQLite schema (User, Report, Medicine, WellnessLog, QRSession).
- Flutter skeleton: Riverpod providers structure, routing, theme — reuse Foam Shop's CI/CD and Firebase setup *structure*, but the visual language is MedAIx's own: brand palette Ink `#0E0D15` / Navy `#182346` / Steel `#3D5387` / Slate `#7C83AD` / Mauve `#BFA9BA`, full light/dark `ColorScheme` + separate error/warning/success semantic colors, styled per the premium glass/atmospheric direction (selective glass + subtle elevation, not the old flat no-elevation look) — spec lives in [`color-system.md`](color-system.md). Nothing's built yet, so this is the starting theme, not a migration.
- GitHub Actions: copy foam-shop-erp's APK build workflow, retarget to medaix-app repo.
- Render web service created for `medaix-api` (free tier); Neon project created for the Postgres DB; confirm `api-deploy.yml` pushes a "hello world" `/health` endpoint live before building real features.
- Set up `keep-alive.yml` (10-min cron pinging `/health`) and, as a backup since GitHub's scheduled crons can be delayed under load, a free UptimeRobot or cron-job.org monitor hitting the same URL every 5 minutes — verify in the Render dashboard that the service actually stays "Live" instead of cycling to "Suspended" over a few idle hours before you trust it. ✅ **Done** — `keep-alive.yml` on the 10-min cron plus a UptimeRobot HTTP(s) monitor on `https://medaix.onrender.com/health` at 5-minute intervals. Both report the service up; UptimeRobot shows 100% uptime and 0 incidents.

### Sprint 1 (Wk 1–2) — Report Upload + OCR (EP-01, PB-01, US-01)
- Backend: Tesseract OCR integration, `/upload-report` endpoint, image/PDF preprocessing.
- Frontend: Upload screen (camera/gallery/file picker) — empty state before first upload, skeleton loading during OCR, plain-language error + retry on failure, success confirmation once parsed.
- Test: Run 15–20 sample reports through it, log accuracy (target ≥85%).

### Sprint 2 (Wk 3–4) — NLP Simplification + Profile Storage (EP-01/02, PB-02/03)
- Backend: SpaCy pipeline, medical-term simplification dictionary, `/simplify-report`, report history storage.
- Frontend: Simplified-report display screen (empty state for no reports yet), patient profile screen, Firebase Auth (reuse your Foam Shop Firebase setup pattern) + the mandatory onboarding questionnaire (age/weight/height/sex/conditions/medications/allergies) that gates the app post-login — short, progress indicator across steps, no unnecessary permission requests upfront, ends by dropping the user into their first real action.
- Test: Validate NLP output on 10+ term sets, verify profile CRUD.

### Sprint 3 (Wk 5–6) — Risk/Trend Analysis (EP-02, PB-03, US-03)
- Backend: rule-based trend detection first, `/risk-trends` endpoint.
- Frontend: trend/alert UI on profile screen (empty state until 2+ reports exist to trend against).
- Test: build abnormal-value test cases, verify alerts fire correctly.

### Sprint 4 (Wk 7–8) — Wellness Tracking UI (EP-06, PB-07/08/09)
- Backend: wellness APIs (condition-based step goals, hydration calc by weight), RAG stub for tips.
- Frontend: steps/water/exercise logging UI (empty state before first log, success feedback per entry), daily habit-score widget with skeleton loading.
- Test: log flows end-to-end, draft the Sem-2 usability testing script now (write it while it's fresh, use it later).

### Sprint 5 (Wk 9–10) — Integration Pass 1
- Wire Upload → OCR → NLP → Profile → Risk → Wellness into one continuous flow.
- Fix API contract mismatches, add error handling across the chain.
- Audit every screen built so far against the Global UX State System (empty/loading/error/success) and close gaps.
- Full regression pass, log bugs to Trello.

### Sprint 6 (Wk 11–12) — Bug Fixing + Advisor Feedback Round
- Address advisor feedback from Sem 1 review.
- Backend: stability pass, OpenAPI/Swagger docs.
- Frontend: UI consistency pass against the brand palette, styled per the premium glass/atmospheric direction (selective glass + subtle elevation, floating bottom nav, AI-insight card on Home) — full spec in [`color-system.md`](color-system.md).
- Update SRS with actuals; refine Sem 2 backlog.

### Sprint 7 (Wk 13–14) — Buffer / Hardening
- No new features — this week exists because solo dev slips more than group estimates. Use it to catch up on whatever's behind.
- Start drafting Sem 1 report sections that don't change (Introduction, Literature Review — copy/adapt from proposal).

### Sprint 8 (Wk 15–16) — Sem 1 Documentation & Defense
- Stabilize demo build: Upload → simplified report → risk trend → wellness log.
- Compile Sem 1 documentation package.
- Build and rehearse defense presentation solo (practice out loud, time yourself).

**Sem 1 checklist:** ☐ OCR ~80–85% ☐ NLP simplification working ☐ Upload/view UI smooth ☐ Profile storage works ☐ Basic risk analysis flags abnormal values ☐ Wellness checklist functional ☐ Every Sem 1 screen has empty/loading/error/success states ☐ Onboarding questionnaire is short and ends in a real first action

---

## SEMESTER 2 — Weeks 17–32

### Sprint 9 (Wk 17–18) — Drug Safety Checker (EP-03, PB-04, US-04)
- Source/validate drug interaction data (NLM/FDA), define test interaction pairs.
- Backend: `/check-interactions` endpoint.
- Frontend: medicine entry UI (multi-add, empty state with "Add first medicine" CTA) + warning display in plain language, no raw error codes.

### Sprint 10 (Wk 19–20) — Medicine Image Scanner (EP-04, PB-05, US-05)
- Backend: image recognition for medicine packaging → name matching.
- Frontend: camera capture screen (permission-denied fallback + explanation before requesting), loading state during recognition, verified/mismatch result UI.
- Test: 15–20 medicine photos (target ~75–80% accuracy).

### Sprint 11 (Wk 21–22) — Doctor Recommendation Engine (EP-05, PB-06, US-06)
- Backend: rule-based/ML specialist classification, `/recommend-doctor`.
- Frontend: recommendation result UI with brief "why this specialist" explanation.
- Test: validate against test scenarios (target ≥80% correct match).

### Sprint 12 (Wk 23–24) — QR Generation (EP-07, PB-10, US-08)
- Backend: JWT-based time-limited token + `qrcode` generation, revocation logic.
- Frontend: "Generate QR" screen (empty state before first QR, loading indicator during generation, success confirmation on generate, duration picker, revoke button).
- Draft security test cases for QR (expiry, reuse prevention, revocation).

### Sprint 13 (Wk 25–26) — Doctor-Side QR Scan + Notifications (EP-07/08, PB-11/12)
- Backend: doctor-scan endpoint — read-only curated access + audit logging.
- Frontend: doctor scan/portal screen (permission-denied fallback for camera); full Settings screen built to the checklist's structure — Preferences (notifications/reminders, appearance), Account (profile, sign-out, data management), Help & Support (FAQ, troubleshooting, contact).
- Firebase Cloud Messaging reminders (meds, water, follow-up) — reuse your Foam Shop notification patterns if any overlap.
- Begin privacy/security testing (proposal specifies Wks 25–27) — start now since it's solo and takes longer without a second tester.

### Sprint 14 (Wk 27–28) — Full Integration + Security Testing
- Finish security/privacy test suite: encryption, RBAC, audit log verification, no unauthorized data leakage.
- Backend: performance pass — async processing, caching, load handling (target 20 concurrent users).
- Frontend: finish full UI development, consistency pass across all backlog items — final audit against the Master Must-Have UX Checklist (every screen: empty/loading/error/success/offline/permission-denied/disabled as applicable).
- End-to-end integration test of all 8 epics connected.

### Sprint 15 (Wk 29–30) — User Testing + Cloud Deployment
- Recruit 5–10 real users yourself (classmates, family, Photography Club contacts) for usability testing — including whether they understand empty/error states and can recover without help; collect + summarize feedback.
- Confirm `api-deploy.yml` is pushing clean builds to Render production on every merge to `main`; run production DB migration to Neon. Double-check `keep-alive.yml` (or the external monitor) is still running so usability-test participants don't hit a 30–60s cold start on their first tap.
- Trigger `app-build.yml` for the release APK; test on real Android devices.

### Sprint 16 (Wk 31–32) — Final Report, Docs, Submission
- Final report, user manual, cleaned-up GitHub repo, defense rehearsal.
- API documentation finalized, backend README.
- App walkthrough doc/demo video, final presentation.

**Sem 2 / success checklist:** ☐ Drug checker ≥90% ☐ Medicine scanner ~75–80% ☐ Doctor recommendation ≥80% ☐ QR sharing passes security tests ☐ Notifications working ☐ Deployed, handles 20 concurrent users ☐ ≥80% users rate app easy ☐ Final report + code + docs submitted ☐ Settings screen complete (Preferences/Account/Help & Support) ☐ Every screen passes the Master Must-Have UX Checklist audit

---

## Solo-Specific Notes
1. **Lean harder on OpenCode CLI + DeepSeek** than you would in a group plan — draft the spec + prompt for each sprint's backend endpoint and frontend screen separately (same pattern as your Foam Shop HTML-mockup-and-prompt workflow), then review/fix the generated code rather than hand-writing everything.
2. **Don't parallelize backend and frontend within a week** — context-switching solo costs more than it saves. Finish the endpoint, then build the screen against it.
3. **The buffer weeks (13–14, and effectively 27–28) are not optional** — as a solo dev you have no one to absorb a slipped sprint. If you're on pace, use buffer time to get ahead on docs instead of skipping it.
4. **Security testing (Sprint 13–14) will take you longer solo** — a group can split "attack the QR flow" across two people; you're doing all attack scenarios (expired token reuse, tampered JWT, wrong user access) yourself. Budget real time here, don't rush it.
5. Since you already have a working CI/CD pipeline from Foam Shop, Sprint 0 setup should take days, not weeks — reuse, don't rebuild.
6. **Monorepo path-based triggers matter.** Set `paths:` filters correctly in both workflow YAMLs (`app/**` vs `api/**`) so a backend-only commit doesn't waste minutes rebuilding the APK, and vice versa. Test this in Week 0 with a throwaway commit to each folder.
7. **Deploy via GitHub Actions curling Render's deploy hook**, not Render's own GitHub integration — same reasoning as before: every deploy shows up in your Actions tab alongside app builds, one place to watch CI.
8. **UX states aren't a separate polish pass — build them inline.** Solo, there's no QA person catching a happy-path-only screen before it ships. Add the empty/loading/error/success state for a screen in the same sprint you build it (per `must-have-ux-feature-checklist.md`), so Sprint 14's "final audit" is a quick check, not a rebuild of 20+ screens.
9. **Keeping Render's free instance from sleeping:** any inbound HTTP request or WebSocket message resets Render's 15-minute idle timer, so a scheduled ping keeps it "Live." Two ways, best used together:
   - `keep-alive.yml` — a GitHub Actions workflow on a `schedule: cron` (every 10 min) that curls your own `/health` route. Free, lives in your repo, no third party — but GitHub can delay scheduled runs under load, so don't rely on it alone.
   - A free external monitor (UptimeRobot or cron-job.org, 5-minute interval, no card needed) hitting the same `/health` URL as a backup.
   Ping a real app route, never `/robots.txt` — Render answers that path itself even while spun down, so it never reaches your FastAPI app and never resets the timer. This trick keeps the service inside Render's 750 free instance-hours/month (a single service pinged 24/7 uses ~720–744 hours, under the cap) — but if you ever spin up a second free service in the same workspace, the two will compete for that shared monthly budget. **Don't** try the equivalent trick on Neon — its 100 compute-hours/month would be gone in about four days if kept always-on, and its cold start (well under a second, usually) isn't worth solving anyway; only Render's ~30–60s wake-up is the actual problem.
10. **Don't treat the keep-alive ping as a guarantee.** Render's own docs note a free instance can be restarted at any time regardless of traffic, so budget a few minutes before any live demo or advisor call to hit `/health` yourself and visually confirm the service answers fast before you rely on it in front of someone.
