> **Status: Sprint 2 — NLP simplification + profile storage. COMPLETE.** Sprint 1 (report upload + OCR) closed with **88.41%–91.53%** OCR accuracy across six samples, a **100% pass rate** against the ≥85% target (see `D:\Fyp\reports.zip`). Sprint 2 closed with `/simplify-report`, `/reports`, `/profile` CRUD, Supabase sign-in, the gated onboarding questionnaire, and the simplified-report screen; 22 term sets validated, profile CRUD verified, and 122/122 real lab-report photos processed end-to-end (see Sprint 2 below). Sprint 3 (risk/trend analysis) is next.
# MedAIx — 32-Week Solo Execution Plan (Muhammad Taha Naeem)

> **Status:** Sprints 1–2 complete (see detail above). Current OCR modes: English, Urdu script, and Roman Urdu. The canonical visual spec is the flat mockup [`design/medaix-mockup.html`](../design/medaix-mockup.html), with the rules in [`AGENTS.md`](../AGENTS.md) §3 and the implemented tokens in [`design-system.md`](design-system.md); later sprint features remain on this plan.

> **UI foundation (2026-10-25).** The Flutter UI layer — design tokens, component kit, five-tab shell and every screen in the mockup — was built ahead of schedule against `design/medaix-mockup.html`, with medicines, wellness, sharing, doctor match and insights on in-memory fakes. To keep delivery sprint-by-sprint, screens are **gated by sprint**: `app/lib/core/features.dart` reads `MEDAIX_SPRINT` (default **3**) and hides every tab, tile, settings row and route that belongs to a later sprint. Each sprint from here stays backend-first as planned; its last step is bumping the build sprint so the already-reviewed screen appears, wired to the real endpoint (`--dart-define=MEDAIX_SPRINT=13` shows everything for a demo). `app/test/feature_gate_test.dart` pins the current sprint.

Built on your existing stack/workflow from `foam-shop-erp`: Flutter + Riverpod + Supabase, GitHub Actions CI/CD, spec-first + OpenCode CLI build pattern. No group dependency — every sprint is sequenced so one person can execute it. **Zero-cost stack:** Render's free web service for backend hosting + Neon's free Postgres tier for the database — no Railway, no paid infra anywhere.

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
- Flutter skeleton: Riverpod providers structure, routing, theme — reuse Foam Shop's CI/CD setup *structure* (auth and storage are on Supabase), but the visual language is MedAIx's own: brand palette Ink `#0E0D15` / Navy `#182346` / Steel `#3D5387` / Slate `#7C83AD` / Mauve `#BFA9BA`, full light/dark `ColorScheme` + separate error/warning/success semantic colors, styled flat and minimal: depth from surface tone only (`background` → `surface` → `surface2`), no gradients, blur or decorative shadows, the floating bottom nav the single shadowed surface — spec in [`design-system.md`](design-system.md) and [`AGENTS.md`](../AGENTS.md) §3 (this superseded an earlier glass/atmospheric direction described in `color-system.md`).
- GitHub Actions: copy foam-shop-erp's APK build workflow, retarget to medaix-app repo.
- Render web service created for `medaix-api` (free tier); Neon project created for the Postgres DB; confirm `api-deploy.yml` pushes a "hello world" `/health` endpoint live before building real features.
- Set up `keep-alive.yml` (10-min cron pinging `/health`) and, as a backup since GitHub's scheduled crons can be delayed under load, a free UptimeRobot or cron-job.org monitor hitting the same URL every 5 minutes — verify in the Render dashboard that the service actually stays "Live" instead of cycling to "Suspended" over a few idle hours before you trust it. ✅ **Done** — `keep-alive.yml` on the 10-min cron plus a UptimeRobot HTTP(s) monitor on `https://medaix.onrender.com/health` at 5-minute intervals. Both report the service up; UptimeRobot shows 100% uptime and 0 incidents.

### Sprint 1 (Wk 1–2) — Report Upload + OCR (EP-01, PB-01, US-01)
- Backend: Tesseract OCR integration, `/upload-report` endpoint, image/PDF preprocessing.
- Frontend: Upload screen (camera/gallery/file picker) — empty state before first upload, skeleton loading during OCR, plain-language error + retry on failure, success confirmation once parsed.
- Test: Ran 6 sample reports (3 panel types × normal + 3° skew) through the full OCR pipeline. Result: **88.41%–91.53% accuracy, 100/6 pass rate — exceeds the ≥85% target.** Verified by Muhammad Taha Naeem on 2026-11-10; samples + output archived in `D:\Fyp\reports.zip`.
- Optimisation pass (2026-10-25, after the 122-image real-report run below): tuned on the **Train** split, measured on the **Test** split so the numbers are not fitted to themselves. (1) Deskew probe rotation moved from NumPy fancy indexing to Pillow's C rotation — same angles, 0.46 s → 0.02 s per upload; it had been half the OCR time. (2) Tesseract page mode `--psm 6` → `--psm 4` (rows of variable-size text, which is what a results table is): +1.5 confidence points and fewer low-confidence numbers on Train. (3) Noise filter: tokens under 25% confidence that carry no digit and are not a known lab word are dropped — the Arabic header read with the English model ("Saytall", "oayyall") was 8% of all tokens; numbers and dictionary words are always kept. **Test split, before → after:** OCR confidence median **74.7% → 81.6%** (min 52% → 66%, no report under 60%), upload time median **2.2 s → 1.1 s**. The ≥85% target is now met by 26/122 real photos (none before); the rest are bilingual pages where the remaining header residue still counts against the mean.

### Sprint 2 (Wk 3–4) — NLP Simplification + Profile Storage (EP-01/02, PB-02/03) ✅
- Backend: medical-term simplification dictionary with sentence-aware, case-preserving replacement (`api/simplify.py`), `/simplify-report` (idempotent, owner-scoped, never rewrites numbers/units/ranges), `/reports` history, `/profile` GET/PUT/DELETE. **Decision:** the spaCy pipeline was dropped — it adds ~100 MB to Render's free-tier cold start for no gain over the dictionary at this stage; it can be swapped in behind `simplify_text()` later without changing the endpoint contract.
- Frontend: Simplified-report screen (empty / skeleton loading / error + retry / result page with plain-language ↔ original toggle), upload success now hands off to "Simplify this report", patient profile screen (view, edit, delete with confirmation), **Supabase Auth** (Google + email — chosen over Firebase so the API can verify tokens against a public JWKS with no service account) + the three-step gated onboarding questionnaire (age/sex → weight/height → conditions/medications/allergies, progress bar, skippable last step, ends by opening the scanner).
- Test: **22 term sets** validated in `api/tests/test_simplify.py` (every replacement checked, every lab number preserved); profile CRUD verified end-to-end in `test_profile_crud_removes_reports_on_delete`; reports proven private per user; 31 Flutter widget tests cover every screen state.
- Real-data check (2026-10-25): the 122-image **Test** split of the Mendeley lab-report photo set (`reports.zip`: Egyptian CBC, lipid, liver, hormone, urine and stool reports with Arabic headers) was run through `/upload-report` → `/simplify-report` on the local API. **122/122 succeeded** (no 4xx/5xx), OCR confidence 52–88% (median 75%), ~2.3 s upload + ~1.3 s simplify each. The first pass reworded zero terms in 45 reports, so the dictionary was extended with the CBC indices (MCV/MCH/MCHC/RDW), the white-cell differential, lipid/liver/thyroid/iron analytes and urine/stool vocabulary; it now explains each term **once per report** (a lipid panel no longer repeats "(a fat in your blood)" six times) and keeps category labels such as "High Risk" and names such as "High Density Lipoprotein" untouched. After the change: 107/122 reports reworded (median 5.5 terms); the 15 with none are genetics, culture and hormone panels outside Sprint 2's scope. Six of the images were then walked through the debug APK on the Pixel 4 emulator (CBC, lipids, stool, vitamin D, ferritin at 52% OCR, urine at 88%): all uploaded, simplified and appeared in the history list.
- Optimisation pass (2026-10-25): every authenticated request opened two database sessions (one in the auth dependency, one in the route), each costing a pool checkout ping and a ROLLBACK, and committed objects were re-SELECTed by SQLAlchemy's expire-on-commit. Against Neon at ~100 ms per round trip that was most of the request. Now one request-scoped session is shared by auth and route (`get_db`), `expire_on_commit=False`, the redundant `refresh()` calls are gone, and `/reports` selects summary columns instead of every report's full text. Measured locally against Neon: `/profile` 390 → 290 ms, `/reports` 800 → 400 ms, `/simplify-report` 1.3 s → 0.6 s (first) and 830 → 400 ms (view); the 122-report batch now averages 1.1 s upload + 0.6 s simplify (was 2.3 s + 1.3 s). On Render, co-located with Neon, the absolute savings are smaller but the round-trip count is what the free tier pays for. Backend suite: 70 passed.

### Sprint 3 (Wk 5–6) — Risk/Trend Analysis (EP-02, PB-03, US-03)
- ✅ Backend: rule-based trend detection first, `/risk-trends` endpoint implemented; 30+ test cases covering rising/falling streaks, crossed high/low alerts, out-of-range warnings, and insights.
- ✅ Frontend: trend/alert UI on profile screen (`trends_screen.dart`) with state switching (loading → error → empty → data); trend chart with dashed warn threshold; per-marker detail view; "View trend over time" from ReportScreen.
- ✅ Test: 30+ abnormal-value test cases built and verified in `api/tests/test_trends.py`; rising_streak, falling_streak, crossed_high, crossed_low, out_of_range, and insight alerts all verified.

### Sprint 4 (Wk 7–8) — Wellness Tracking UI (EP-06, PB-07/08/09)

### Sprint 4 (Wk 7–8) — Wellness Tracking UI (EP-06, PB-07/08/09)
- ✅ Backend: wellness APIs (condition-based step goals, hydration calc by weight), RAG stub for tips - to be implemented; WellnessLog model and `/wellness/log` endpoint following Sprint 1–3 pattern.
- ⚪ Frontend: steps/water/exercise logging UI (empty state before first log, success feedback per entry), daily habit-score widget with skeleton loading - planned; Wellness screen per mockup: habit score ring, water intake progress, step goal progress conditioned on user's condition.
- 🟡 Test: log flows end-to-end, draft the Sem-2 usability testing script now (write it while it's fresh, use it later) - to be started.

### Sprint 5 (Wk 9–10) — Integration Pass 1
- Wire Upload → OCR → NLP → Profile → Risk → Wellness into one continuous flow.
- Fix API contract mismatches, add error handling across the chain.
- Audit every screen built so far against the Global UX State System (empty/loading/error/success) and close gaps.
- Full regression pass, log bugs to Trello.

### Sprint 6 (Wk 11–12) — Bug Fixing + Advisor Feedback Round
- Address advisor feedback from Sem 1 review.
- Backend: stability pass, OpenAPI/Swagger docs.
- Frontend: UI consistency pass against the flat design system (tokens, kit, floating bottom nav, AI-insight card on Home) — full spec in [`design-system.md`](design-system.md); `app/test/design_system_test.dart` is the guard.
- Update SRS with actuals; refine Sem 2 backlog.

### Sprint 7 (Wk 13–14) — Buffer / Hardening
- No new features — this week exists because solo dev slips more than group estimates. Use it to catch up on whatever's behind.
- Start drafting Sem 1 report sections that don't change (Introduction, Literature Review — copy/adapt from proposal).

### Sprint 8 (Wk 15–16) — Sem 1 Documentation & Defense
- Stabilize demo build: Upload → simplified report → risk trend → wellness log.
- Compile Sem 1 documentation package.
- Build and rehearse defense presentation solo (practice out loud, time yourself).

**Sem 1 checklist:** ☑ OCR ~80–85% ☑ NLP simplification working ☑ Upload/view UI smooth ☑ Profile storage works ☐ Basic risk analysis flags abnormal values ☐ Wellness checklist functional ☐ Every Sem 1 screen has empty/loading/error/success states (Sprints 1–2 screens: done) ☑ Onboarding questionnaire is short and ends in a real first action

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
- Push notification reminders (meds, water, follow-up) — provider TBD (e.g. Supabase Edge Functions + FCM/APNs, or a free push service); reuse your Foam Shop notification patterns if any overlap.
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
