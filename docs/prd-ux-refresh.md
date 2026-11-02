# MedAIx — Product Requirements: UX Refresh (v0.2)

| | |
|---|---|
| Status | Draft for owner review |
| Date | 2 Nov 2026 |
| Owner | Muhammad Taha (Scrum Master, Flutter lead) |
| Applies to | `app/` (Flutter) and a small static public site (`site/`) |
| Depends on | Sprint 5 corrections and the corrected light/dark palette (tokens `surface`, `surfaceModal`, `ai`, `aiFill`, `outlineStrong`, …) from `correction.md` / `master-prompt.md` |
| Does **not** change | Sprint gating (`kBuildSprint = 5`), API contract (additive only), Brand constants, later-sprint features |

---

## 1. Summary

MedAIx turns a photographed lab report into plain-language values, ranges and trends. After the Sprint 5 review the core flow works;
what is left is how the app **navigates, asks, fails and presents information**. This PRD uses six public design galleries as a
checklist of patterns (navigation, footers, calls to action, error pages, bento layouts, full-site structure) and translates the
ones that fit a calm, trust-first medical app on a phone — and explicitly rejects the ones that do not.

Outcomes: fewer dead ends, one obvious next step on every screen, clear recovery when something goes wrong, a Home screen that shows
what matters first, and the public pages (privacy, terms, support) that a health app needs before it can be published.

## 2. Problem statement (evidence from the Sprint 5 review)

1. **Dead ends.** The router has no error/not-found handler. A stale deep link, a deleted report or a malformed route has no designed
   outcome.
2. **Slow first request looks like a failure.** The free-tier API sleeps; the first call can take up to a minute. The UI shows a
   generic loading skeleton, then an error, with no explanation.
3. **Status is scattered.** Offline, syncing and "update available" are shown in different places and styles.
4. **CTAs are inconsistent.** Generic labels ("See the trend", "View trend over time"), the same visual weight for unequal actions,
   one stub action ("Export is coming soon").
5. **Home hierarchy.** The insight card, two tiles, habit score and latest report have similar visual weight; first-run and
   empty states are not collapsed into one clear next step.
6. **Legal links go nowhere verifiable.** The app opens `https://medaix.app/terms` and `/privacy`; no evidence was found that these
   pages exist. A health app that collects consent needs real, hosted policy pages (and the store listing needs a privacy-policy URL
   and data-deletion information).

## 3. Goals and non-goals

**Goals**
- G1 Every screen has exactly one obvious primary action, labelled with a specific verb + object.
- G2 Every failure has a designed, calm recovery path (what happened · is my data safe · what can I do).
- G3 Home and report screens present information in a clear hierarchy (bento layout, one idea per tile).
- G4 Status messages (offline, syncing, update) use one consistent pattern.
- G5 Public pages exist for privacy, terms and support, with the same visual language.
- G6 No new paid services, no new runtime dependencies in the app, no trackers.

**Non-goals**
- Marketing animation, 3D/WebGL, parallax, video backgrounds, playful/game-style error pages.
- Conversion tactics (urgency, scarcity, social-proof counters, "Yes, I want this!").
- New clinical features, new analytics, push notifications, accounts beyond the current auth.
- Redesigning the palette (done in the corrections) or the information architecture beyond the 4 tabs.
- RTL/Urdu UI translation (report OCR languages stay as they are).

## 4. Users and context

- **Primary — patient or family member** holding a printed or photographed lab report; often a mid/low-range Android phone;
  intermittent connectivity; may read English, Urdu or Roman Urdu; often anxious about the result.
- **Secondary — caregiver** helping a relative upload and understand reports.
- **Evaluators — advisor and examiners** viewing a live demo; they notice dead ends and broken states first.

Design for: one hand, bright light, 200 % text size, slow network, and a user who needs reassurance without being told what to do medically.

## 5. Design principles

1. **Calm over clever.** Plain words, steady layout, no urgency. The app explains; it never alarms or diagnoses.
2. **One next step.** One filled button per screen or sheet; everything else is quieter.
3. **Say what happened, say what's safe, say what to do.** Every error uses that order.
4. **Status is never colour alone.** Icon + word + colour (existing `StatusLabel` rule).
5. **One idea per tile.** Size follows importance; reading order equals visual order.
6. **Honest labelling.** Rule-based output is labelled as automated, never as a doctor.
7. **Light on the phone.** No heavy motion or effects; respect reduced-motion and text scaling.

## 6. Inspiration review

I could read each site's structure and categories; the galleries are mostly screenshots, which I could not inspect individually. The
table records what each source contributes **as a pattern checklist**, not as visuals to copy.

| Source | What it is | Patterns we take (mobile translation) | What we leave |
|---|---|---|---|
| getlayers.ai | A library of website templates, sections and motion effects, each with a structured build brief; publishes performance and SEO targets | Structure each screen spec the same way (intent, layout, tokens, states, accessibility, acceptance); the public-site checklist (sitemap, robots, canonical, Open Graph, structured data, semantic HTML, PageSpeed targets) | 3D/WebGL scenes, animated backgrounds, cinematic motion (performance, motion sensitivity, tone); paid templates (zero-cost rule; free layers are for trying, not shipping) |
| navbar.gallery | Navigation patterns by type: static/sticky, dropdown, mega menu, sidebar, search bar, announcement bar, full-screen, breadcrumbs, tabs | Static bottom bar (keep); announcement bar → status banner; search bar → Reports search; breadcrumbs → context line under titles; tabs → segmented controls (exists) | Mega menu, sidebar, full-screen and dropdown menus (too deep for a stressed user; 4 destinations suffice) |
| footer.design | Footer styles: typographic, small type, grid, cards, dark… | A quiet "footer block" at the end of Settings and of the public site: version, legal links, support, one-line disclaimer | Large-type/animated/illustrative footers |
| cta.gallery | CTA types: button, form, modal/pop-up, navigation, download; plus writing tips | Clear, direct, action-first, specific, short labels; risk-reducing microcopy ("Works offline…"); button hierarchy; confirmation sheets | Urgency, scarcity, social proof, "Yes, I want this!" first-person pressure, A/B conversion tactics |
| 404s.design | Creative error pages filterable by style (minimal, light, dark, illustrative, playful, game…) | A designed outcome for every dead end; minimal + light/dark + brand mark; one clear way back; humour only as a gentle sentence at most | Games, glitch effects, 3D, retro/playful styles (wrong tone for health) |
| bentogrids.com | Bento-style grid layouts | Asymmetric tile grid on Home/Wellness/Report summary; tile = one idea; reflow to one column | Dense decorative mosaics, tiny tiles, tiles with no purpose. (This site returned no readable text; the guidance above comes from the bento pattern itself.) |

## 7. Requirements

Priority: **P0** do first · **P1** next · **P2** if time allows. Sizing: S ≤ 1 day · M 2–3 days · L > 3 days.

### 7.1 Navigation and status (navbar patterns)

| ID | Requirement | Pri | Size | Acceptance |
|---|---|---|---|---|
| FR-N1 | Keep the 4-tab floating bottom bar; labels always visible; no counters or alert badges on tabs (avoids alarm). Dark mode: no black shadow; `surface2` + 1 px hairline | P0 | S | Guard test passes; screenshot check light/dark |
| FR-N2 | **Status banner** (announcement-bar pattern): one slim banner under the header; priority offline > retrying/syncing > update available > info; dismissible except offline; announced to screen readers (live region); uses status tokens + icon + text | P0 | M | Widget tests per priority; offline banner appears after a failed network call and clears after success; update prompt shown as banner, non-blocking |
| FR-N3 | Reports **search + filter chips** (All · Needs attention · Last 30 days) over the already-loaded list; client-side only | P1 | M | Typing filters by title/marker; empty-result state with "Clear search"; no API change |
| FR-N4 | **Context line** (breadcrumb pattern) under detail titles: "Complete blood count · 31 Oct 2026", "From 3 reports" | P2 | S | Present on Report detail and Trends detail |
| FR-N5 | Predictable back behaviour; unknown routes land on the designed Not-found screen (7.3) | P0 | S | Router test |
| — | Rejected: sidebar, mega menu, full-screen menu, dropdown menus | | | |

### 7.2 Calls to action and copy

| ID | Requirement | Pri | Size | Acceptance |
|---|---|---|---|---|
| FR-C1 | One filled primary button per screen/sheet; secondary = tonal/ghost; destructive = error fill, only inside a confirmation sheet with a "Keep" option | P0 | S | Visual audit list in the master brief |
| FR-C2 | Copy rules: verb + object, specific not generic, ≤ 3 words where possible, sentence case, no exclamation marks, no urgency/scarcity/social proof, no emoji | P0 | S | `docs/copy-guide.md`; source-scan test rejects banned phrases |
| FR-C3 | Risk-reducing microcopy under key actions where true ("Works offline. Reports sync when you reconnect.", "Your report stays on your account.") | P0 | S | Present under Upload and Delete flows |
| FR-C4 | Button states: default, pressed, disabled (with a reason line), loading (label stays), done | P0 | S | Gallery shows all states |
| FR-C5 | Sticky primary CTA on long screens (Report detail) sits above the nav, never covers content | P1 | S | Bottom padding test at 2.0 text scale |
| FR-C6 | Automated-content actions use the AI-surface style only while busy (dark glow) per the corrected palette | P1 | S | Guard test exception list unchanged |
| FR-C7 | Replace the "Export my data" stub with either a real export or a hidden row (flagged) — never a "coming soon" toast | P0 | S | Feature-flag test |

Copy changes are listed in Appendix A.

### 7.3 Dead ends and failure states (404 patterns)

| ID | Requirement | Pri | Size | Acceptance |
|---|---|---|---|---|
| FR-E1 | **Not-found screen** for unknown routes: brand mark, "We couldn't find that page", reason line, primary "Go to Home" | P0 | S | Router `errorBuilder` test |
| FR-E2 | **Report not available** (deleted, other account, expired id): "This report isn't available", primary "Back to reports" | P0 | S | Widget test with a 404 from the repository |
| FR-E3 | **Waking up** state: after ~8 s of waiting on a network call show "Waking up MedAIx…" with a plain explanation and that data is safe; after ~25 s add "Try again" | P0 | M | Fake-async test with a delayed repository |
| FR-E4 | **Offline** variants: banner (FR-N2) + inline empty/error states that say changes are kept on the device | P0 | S | Existing offline tests extended |
| FR-E5 | **Server error (5xx)**: "Something went wrong on our side. Your data is safe." primary "Try again", secondary "Contact support" | P0 | S | Widget test |
| FR-E6 | **Permission denied** (camera/storage): explain why, primary "Open settings", secondary "Choose from gallery" | P1 | S | Existing permission state upgraded |
| FR-E7 | **Session expired**: "Please sign in again", primary "Sign in"; local unsynced changes are kept | P1 | S | Auth test |
| FR-E8 | Every error screen follows: what happened → is my data safe → one primary action; no stack traces, no raw exceptions; neutral tone (no jokes, no games) | P0 | S | Source-scan for `toString()` in user text |

Catalogue with copy: Appendix C.

### 7.4 Bento layouts

| ID | Requirement | Pri | Size | Acceptance |
|---|---|---|---|---|
| FR-H1 | Reusable `BentoGrid` / `BentoTile` (span 1 or 2 columns; 12 dp gap; tokens only; no decorative tiles) that reflows to one column at width < 340 dp or text scale ≥ 1.5 | P1 | M | Layout tests at 320 dp and 2.0 scale |
| FR-H2 | **Home** as a bento: insight (span 2) · Add a report (1) · See my trends (1) · Habit score (span 2) · Latest report (span 2); max 6 tiles; reading order = visual order | P1 | M | Golden/behaviour test for populated and loading states |
| FR-H3 | **First-run Home** collapses to one hero tile: "Add your first report" with the Upload CTA; other tiles hidden until data exists | P1 | S | Test for empty account |
| FR-H4 | **Report summary tiles** (values read · need attention · date source) above "In plain words", from stored counts | P1 | S | Uses API `values_read`/`attention_count`; tests for 0, partial, all |
| FR-H5 | **Wellness** as a bento: progress (span 2) · Water (1) · Steps (1) · Movement (span 2) · Note (span 2) | P2 | M | Existing wellness tests green |
| FR-H6 | Tiles for automated content use the AI-surface treatment; plain tiles use `surface` | P1 | S | Guard test |

### 7.5 Footer and legal strip

| ID | Requirement | Pri | Size | Acceptance |
|---|---|---|---|---|
| FR-F1 | End of Settings: app version/build, Terms, Privacy, Support, and "MedAIx explains reports; it is not a diagnosis." | P0 | S | Widget test |
| FR-F2 | Report and Trends screens end with the one-line disclaimer (scrolls with content, not sticky) | P0 | S | Present on both |
| FR-F3 | `kTermsUrl`, `kPrivacyUrl` and the support address point to pages/mailboxes the owner controls (blocker for store release) | P0 | S | Verified by the owner; see open questions |

### 7.6 Public site (Track B)

| ID | Requirement | Pri | Size | Acceptance |
|---|---|---|---|---|
| FR-S1 | One static site in `site/`, hosted free (GitHub Pages): Home, `/privacy`, `/terms`, `/support` (contact + how to delete your data), `404.html` | P1 | M | Pages build locally; links valid |
| FR-S2 | Home: what MedAIx does in one sentence, "How it works" in 3 steps, a 4–6 tile bento of features, FAQ, one download CTA (store link when it exists, otherwise "Request the test build") | P1 | M | Content reviewed by the owner |
| FR-S3 | Footer: legal links, support, version, disclaimer (same wording as the app) | P1 | S | Matches FR-F1 |
| FR-S4 | SEO and quality: `lang`, semantic HTML, `sitemap.xml`, `robots.txt`, canonical, meta description, Open Graph, favicons/manifest, JSON-LD (`SoftwareApplication`); PageSpeed ≥ 95 mobile, accessibility ≥ 95 | P1 | S | Reports saved in `site/` notes |
| FR-S5 | No trackers, no third-party scripts, no cookies (so no consent banner), no autoplay media; honours `prefers-color-scheme` and `prefers-reduced-motion`; same palette tokens as the app | P1 | S | Network tab shows only first-party requests |
| FR-S6 | Privacy/Terms are **drafts written from what the app actually does** (collected data, storage location, processors, retention, deletion, contact) and are reviewed by the owner/advisor; no claims that cannot be verified in code or docs | P1 | M | Every statement traceable to code/docs |
| FR-S7 | Screenshots on the site and store listing use **synthetic data only** (no real names, emails, birth dates or reports) | P0 | S | Checklist before publishing |

## 8. Non-functional requirements

- **Accessibility:** WCAG 2.2 AA; contrast per the corrected token matrix; touch targets ≥ 48 dp; works at 200 % text and 320 dp;
  TalkBack reading order = visual order; banners use live regions; no information by colour alone.
- **Performance:** no new heavy assets; cold-start perceived latency handled by FR-E3, not hidden; site PageSpeed targets above.
- **Privacy:** no analytics or trackers added; screenshots synthetic; policy text matches behaviour; local health-data cache disclosed.
- **Cost:** no paid tools, templates or services; no new runtime dependencies in the app (ask before adding any).
- **Maintainability:** tokens only via `context.colors`; new components documented in the gallery; one source for copy rules.
- **Compatibility:** released `0.1.3` clients keep working — API changes additive only.

## 9. Success metrics and validation

| Metric | Target | How |
|---|---|---|
| Task success (5 participants): add a report · find a trend · recover from offline | ≥ 90 % unaided | Usability session using the existing Sprint 4 protocol |
| Taps to add a report from Home | ≤ 2 | Count in test |
| Perceived-wait complaints on first launch | 0 of 5 | Session notes (FR-E3) |
| SUS score | ≥ 80 | Questionnaire |
| `flutter analyze` / `flutter test` | 0 issues / all green | CI |
| Public site | PageSpeed mobile ≥ 95, accessibility ≥ 95 | Saved reports |
| Dead ends | 0 unhandled routes or errors in a manual walkthrough of the Appendix C list | Checklist |

## 10. Sequencing

| Milestone | Contents | Gate |
|---|---|---|
| M0 (prerequisite) | Sprint 5 corrections + palette migration merged and green | `design_system_test` green on new tokens |
| M1 (P0) | FR-N1/N2/N5, FR-C1–C4/C7, FR-E1–E5/E8, FR-F1–F3, FR-S7 | Appendix C walkthrough passes |
| M2 (P1) | FR-H1–H4/H6, FR-N3, FR-C5/C6, FR-E6/E7, Track B FR-S1–S6 | Usability session |
| M3 (P2) | FR-H5, FR-N4, polish from session findings | Final regression |

## 11. Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Scope vs. FYP deadline | Unfinished polish | P0 first; P2 is droppable; each milestone is shippable |
| Web gallery patterns misapplied to mobile | Cluttered or off-tone UI | Translation table in §6; reject list; tone rules |
| Bento density at large text | Overflow, unreadable tiles | Single-column reflow; tests at 2.0 scale |
| "Waking up" message hides a real slow backend | Users wait without cause | Keep the keep-alive job; message is honest and time-boxed |
| Legal text inaccurate | Policy mismatch, store rejection | Draft from code facts only; owner/advisor review; not legal advice |
| Real patient data in screenshots | Privacy breach | FR-S7 synthetic-data rule; review every image |
| Domain/mailbox not owned | Broken legal and support links | Open question Q1/Q2 before M1 ends |

## 12. Open questions

1. Do you own `medaix.app`? If not, host on GitHub Pages under your account and update `kTermsUrl`/`kPrivacyUrl`.
2. Is `support@medaix.app` a working mailbox? If not, which address should patients write to?
3. Should "Export my data" be built in this release or hidden until Sprint 13? (default: hidden)
4. Public site language: English only, or add an Urdu summary page?
5. Is a quick-add (+250 ml) on Home tiles wanted, or should tiles only navigate? (default: navigate only)

---

## Appendix A — CTA and copy changes

| Where | Current | Proposed | Why |
|---|---|---|---|
| Home tile | Upload report | Add a report | Matches the Upload screen title and the "Scan" action |
| Home tile | View trends | See my trends | Direct, first-person for personal data |
| Home insight card | See the trend | See Haemoglobin trend | Specific, not generic |
| Report detail (sticky) | View trend over time | See how this changes | Says the benefit |
| Reports | Upload report | Add a report | Consistent |
| Upload | Scan a report / Choose from gallery or files | unchanged | Already verb + object |
| Settings | Export my data (toast "coming soon") | hidden until built | No stubs |
| Sheets | Close | Got it | Closing is not the intent; acknowledging is |
| Errors | Try again | Try again | Keep |
| Sign out sheet | Stay signed in | Stay signed in | Keep |

Banned in UI copy: "Click here", "Submit", "Learn more", "Yes, I want this", "Hurry", "Limited", "Don't miss", exclamation marks, emoji.

## Appendix B — Home bento (phone, 2 columns, 12 dp gap)

```
┌───────────────────────────┐
│ Insight (span 2)          │  automated-content surface
├─────────────┬─────────────┤
│ Add a report│ See my      │
│ (1)         │ trends (1)  │
├─────────────┴─────────────┤
│ Habit score (span 2)      │
├───────────────────────────┤
│ Latest report (span 2)    │
└───────────────────────────┘
First run: a single hero tile "Add your first report".
Width < 340 dp or text scale ≥ 1.5: every tile spans the full width.
```

## Appendix C — Failure-state catalogue

| State | Trigger | Headline | Body | Primary | Secondary |
|---|---|---|---|---|---|
| Not found | Unknown route | We couldn't find that page | The link may be old. Your data is safe. | Go to Home | — |
| Report unavailable | 404/403 on a report id | This report isn't available | It may have been deleted, or it belongs to another account. | Back to reports | — |
| Waking up | Request > 8 s | Waking up MedAIx… | The server rests when it isn't used, so the first request can take up to a minute. Your report is safe. | (none; spinner) → after 25 s: Try again | — |
| Offline | No network | You're offline | Changes are saved on this device and sync when you're back online. | (banner; no blocker) | — |
| Server error | 5xx after retries | Something went wrong on our side | Your data is safe. Please try again. | Try again | Contact support |
| Permission denied | Camera/storage | MedAIx needs camera access to scan | You can also choose a photo from your gallery. | Open settings | Choose from gallery |
| Session expired | 401 | Please sign in again | Anything not yet synced is kept on this device. | Sign in | — |
| Parse failed | OCR unreadable | We couldn't read this report | Retake the photo in good light with the whole page in frame. | Scan again | Choose from gallery |
