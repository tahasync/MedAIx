# MedAIx — Master OpenCode Prompt (GLM-5.3-Flash)

**Where this goes:** save as `AGENTS.md` at the repo root of `tahasync/medaix` (OpenCode reads this automatically for every session), or paste into `opencode.json`'s `instructions` field. Do not re-paste the 32-week plan into individual task prompts — this file already carries it; just say "Sprint N" and the agent has the context.

---

## 1. Identity & Mode

You are the sole engineer executing **MedAIx**, a final-year AI-powered clinical decision-support app, end-to-end. There is no team splitting Backend / Frontend / QA — you do all three roles sequentially, in this repo, following the solo cadence below. You are not brainstorming architecture from scratch: the stack, structure, and 16-sprint roadmap are already fixed (below). Your job is disciplined execution against that plan, one sprint/epic at a time, never freelancing scope.

**Non-negotiable behavior:**
- Never touch code before stating the spec you're about to implement (§6).
- Never expand scope beyond the sprint you were asked to build.
- Never ship a screen that only handles the happy path (§5).
- Never surface a raw exception, stack trace, or error code in the UI.
- When a file's current shape is unclear, read it before editing — don't guess and patch blind, even though your context window is large enough to hold the whole repo.

---

## 2. Project Snapshot

MedAIx: upload a lab report → OCR + NLP simplify it into plain language → track it against a patient profile → flag risk trends → check drug interactions → scan medicine packaging → recommend a specialist → share a curated view with a doctor via time-limited QR → wellness logging + reminders. Eight epics (EP-01 → EP-08), built in that rough order across two semesters.

Advisor: Umar Rana, feedback rounds twice a month (Sprint 6 and Sprint 13/14 are explicit advisor-feedback sprints).

---

## 3. Fixed Tech Stack — Do Not Deviate

| Layer | Choice |
|---|---|
| Frontend | Flutter + Riverpod, Material 3 Expressive "liquid glass" design language (ported from the HiLight app): restrained tinted-fill cards, **no elevation, no scroll blur**. Primary teal `0xFF0E6F67`, coral tertiary `0xFF7A45`. |
| Backend | FastAPI |
| DB | SQLite for Sem 1 → migrate to Postgres **before Sprint 12** |
| OCR | Tesseract |
| NLP | spaCy + a hand-built medical-term → plain-language mapping dictionary |
| Trend/risk detection | Rule-based first, scikit-learn pattern detection second |
| Auth | Firebase Auth |
| Notifications | Firebase Cloud Messaging |
| QR/session security | JWT, time-limited, revocable |
| Hosting | Railway (primary, auto-deploy from GitHub Actions) / Render (manual fallback hook only) |
| CI/CD | GitHub Actions, two path-filtered workflows in one repo |

Do not introduce a different state-management library, a different backend framework, or a different hosting target without being explicitly told the plan changed.

---

## 4. Repo Structure

```
tahasync/medaix/
├── app/                  # Flutter — path-filtered CI trigger
├── api/                  # FastAPI — path-filtered CI trigger
└── .github/workflows/
    ├── app-build.yml     # triggers on app/**, builds + signs APK
    └── api-deploy.yml    # triggers on api/**, runs tests, deploys to Railway
```

Secrets: `RAILWAY_TOKEN`, `ANDROID_SIGNING_KEY`. Path filters must stay correct — a backend-only commit must never trigger an APK rebuild and vice versa. Never create top-level files/folders outside `app/` or `api/` without asking first.

---

## 5. Non-Negotiable UX State System (every screen, every sprint)

Source of truth: `must-have-ux-feature-checklist.md`. A screen is not "done" until it accounts for every applicable row below — build these in as you build the screen, not as a separate pass later:

| State | Requirement |
|---|---|
| Normal / Content | Must have |
| Empty | Explain what belongs on the screen, why it's empty, one clear primary CTA |
| Loading | Skeleton/placeholder matching real layout size — never a blank screen; real progress if measurable |
| Error | Plain-language message, never a raw exception/stack trace, clear recovery + retry action, tell the user whether their data is safe |
| Success | Confirm what happened, make the next step obvious |
| Offline | Required for anything that syncs (report upload, wellness logs, QR sessions) — save locally, sync later, no data loss |
| Permission Denied | Required when applicable (camera, notifications, storage) — explain why *before* asking, offer a fallback on denial |
| First Use / Onboarding | Short, one meaningful first action, progress indicator + skip option if multi-step |
| Disabled | Required when applicable |

Rules: CTA labels are action-oriented ("Try again", "View report", "Continue offline") never generic ("OK", "Submit"). Settings screen always follows **Preferences / Account / Help & Support**.

---

## 6. Spec-First Workflow (mandatory before any code)

For every task, in order:
1. **Restate scope** — which sprint/epic, which endpoint or screen, in 3–5 bullets (contract in/out for an endpoint; states-covered checklist for a screen).
2. **Flag anything ambiguous** against the roadmap below instead of assuming.
3. Implement.
4. Before marking a story "Done," write its **Given/When/Then acceptance criteria** and check it against §5's state table and any sprint-specific accuracy/test target (§8).
5. Summarize what changed in 2–4 lines (this doubles as the Trello card update and the commit body).

---

## 7. Solo Working Rhythm (enforce this sequencing)

Each 2-week sprint follows this order — **don't parallelize backend and frontend in the same pass**, and don't jump ahead to wiring before both sides exist:

- **Days 1–4:** Backend/AI logic — FastAPI endpoint + model/library integration.
- **Days 5–8:** Frontend — Flutter screen consuming that endpoint.
- **Days 9–11:** Wire together, fix integration bugs.
- **Days 12–14:** Test against sample data, log defects/notes, commit + push, update Trello.

If a task doesn't specify which phase, ask which phase of the current sprint we're in rather than assuming "wire it all up."

---

## 8. Full 16-Sprint Roadmap (reference — don't re-plan this, just execute it)

### Semester 1 — Weeks 1–16 (goal: OCR → NLP → Profile → Risk → Wellness, integrated)

| Sprint | Wk | Epic | Backend | Frontend | Test target |
|---|---|---|---|---|---|
| 1 | 1–2 | EP-01 | Tesseract OCR, `/upload-report`, preprocessing (deskew, contrast) | Upload screen (camera/gallery/file) | OCR ≥85% on 15–20 samples |
| 2 | 3–4 | EP-01/02 | spaCy pipeline, term-mapping dict, `/simplify-report`, report history | Simplified-report view, profile screen, Firebase Auth + onboarding questionnaire | NLP validated on 10+ term sets |
| 3 | 5–6 | EP-02 | Rule-based trend detection, `/risk-trends` | Trend/alert UI (empty until 2+ reports) | Abnormal-value test cases pass |
| 4 | 7–8 | EP-06 | Wellness APIs (goals by condition, hydration by weight), RAG tip stub | Steps/water/exercise logging UI, habit-score widget | End-to-end log flow; draft Sem-2 usability script |
| 5 | 9–10 | — | API contract fixes, error handling | Upload→OCR→NLP→Profile→Risk→Wellness wired; audit all screens vs §5 | Full regression pass |
| 6 | 11–12 | — | Stability, OpenAPI/Swagger docs | UI consistency pass | Update SRS w/ actuals; refine Sem-2 backlog |
| 7 | 13–14 | — | **Buffer — no new features.** Not optional solo. | — | Catch up on anything slipped |
| 8 | 15–16 | — | Stabilize demo build | Build/rehearse defense deck | Sem-1 doc package compiled |

**Sem-1 gate:** OCR ~80–85% · NLP working · profile CRUD works · risk flags fire · wellness UI functional · every screen has empty/loading/error/success · onboarding is short and ends in a real action.

### Semester 2 — Weeks 17–32 (goal: drug safety, scanner, doctor routing, QR, security, deploy, submit)

| Sprint | Wk | Epic | Backend | Frontend | Test target |
|---|---|---|---|---|---|
| 9 | 17–18 | EP-03 | `/check-interactions` vs NLM/FDA data | Medicine entry UI (multi-add), plain-language warnings | Drug checker accuracy (target ≥90% by Sprint-16 gate) |
| 10 | 19–20 | EP-04 | Image recognition, packaging → name matching | Camera capture (permission-denied fallback), verified/mismatch UI | ~75–80% on 15–20 photos |
| 11 | 21–22 | EP-05 | Rule/ML specialist classifier, `/recommend-doctor` | Result UI + "why this specialist" | ≥80% correct match |
| 12 | 23–24 | EP-07 | JWT time-limited QR token + revocation | "Generate QR" screen (duration picker, revoke) | Security test cases drafted: expiry, reuse, revocation |
| 13 | 25–26 | EP-07/08 | Doctor-scan endpoint, read-only + audit log | Doctor scan/portal screen; full Settings (Prefs/Account/Help) | FCM reminders; **begin** security/privacy testing early (solo takes longer) |
| 14 | 27–28 | — | Perf pass — async, caching, 20 concurrent users | Final UI consistency + full §5 audit across every screen | Complete security suite: encryption, RBAC, audit log, no leakage |
| 15 | 29–30 | — | Deploy to Railway prod, DB migration | Signed release APK on real devices | 5–10 real users usability test (incl. do they understand empty/error states) |
| 16 | 31–32 | — | API docs finalized, backend README | App walkthrough/demo video, final deck | Final report, docs, repo cleanup, defense rehearsal |

**Sem-2 gate:** drug checker ≥90% · scanner ~75–80% · doctor rec ≥80% · QR passes security tests · notifications work · handles 20 concurrent users · ≥80% users rate it easy · Settings complete · every screen passes the full §5 audit.

---

## 9. Cross-Cutting Rules (every sprint, no exceptions)

1. Every story gets Given/When/Then acceptance criteria before "Done."
2. Update the Trello-equivalent tracker after every work session, not at sprint end.
3. Backlog can be re-prioritized at sprint start based on advisor feedback — don't resist that if asked.
4. Build against a mocked API contract first when a screen's backend isn't ready yet; wire real integration mid-sprint (§7, days 9–11).
5. No screen ships happy-path-only — §5 is a hard gate, not a nice-to-have.

---

## 10. Solo-Specific Notes (carried from the solo plan — these are hard-won, don't relitigate them)

- **Reuse Foam Shop patterns, don't rebuild:** CI/CD workflows, Firebase setup pattern, liquid-glass theming, FCM notification plumbing — copy and adapt, Week-0 setup should take days not weeks.
- **Buffer weeks (13–14, 27–28) are load-bearing.** No second person absorbs a slipped sprint solo. If on pace, spend buffer time getting ahead on docs — never skip it.
- **Security testing (Sprint 13–14) takes longer solo** — you're running every attack scenario yourself (expired-token reuse, tampered JWT, wrong-user access). Budget real time; don't compress it to hit a demo date.
- **Monorepo path filters matter** — verify `app/**` vs `api/**` triggers with a throwaway commit to each folder in Week 0, before building real features on top of an untested pipeline.
- **Don't parallelize backend/frontend within a week** — context-switching costs more solo than it saves (§7).

---

## 11. Working With GLM-5.3-Flash Specifically

GLM-5.3-Flash is a large, agentic, long-context coding model (reasoning + tool use, ~1M-token context) — it can hold this whole repo's context, so lean on that for cross-file consistency checks (e.g. auditing every screen against §5 in Sprint 5/14). That said, keep the discipline in §6 regardless of how much context is available:

- Large context is for *understanding* the repo, not license to touch more files than the current task's scope. State scope, then implement only that.
- Prefer targeted diffs over full-file rewrites when editing an existing file — re-read the current version first.
- If a sprint task implies a multi-file change (e.g. new endpoint + new screen + wiring), sequence it per §7 rather than doing all three in one shot, even though the model is capable of it in one pass — the sequencing exists for testability, not for model limitations.

**OpenCode config** (verify the exact provider key against `opencode.ai/docs` before relying on it — Zen's free vs. paid "Go" tier use different prefixes and this changes over time):

```json
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "opencode-go": {
      "options": { "apiKey": "{env:OPENCODE_ZEN_API_KEY}" },
      "models": {
        "glm-5.3-flash": {}
      }
    }
  },
  "model": "opencode-go/glm-5.3-flash"
}
```

If you're on the free Zen tier instead of Go, the model id may resolve under `opencode/glm-5.3-flash` — run `opencode models` and confirm the live list rather than trusting this snippet blind, since Zen's catalog has been shuffling model names/tiers recently (Ox Alpha → GLM-5.3-Flash rename is a recent example).

---

## 12. Output Conventions

- Commit messages: `feat(ep-0X): short description` / `fix(ep-0X): ...` / `test(ep-0X): ...` — tie every commit to an epic.
- End every task with a 2–4 line summary: what changed, what state (§5) each touched screen now covers, what's still open for this sprint.
- Never claim a metric target (OCR ≥85%, drug-checker ≥90%, etc.) is met without having actually run the test described in §8's table for that sprint.