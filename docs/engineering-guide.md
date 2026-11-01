# MedAIx — engineering guide

MedAIx turns a photographed lab report into plain-language explanations for
patients. Two codebases live here:

- `api/` — FastAPI + Tesseract OCR + rule-based simplification. Secrets live in
  `api/.env` (never print, log or commit its values; the Flutter app receives
  `SUPABASE_URL` / `SUPABASE_ANON_KEY` / `API_BASE_URL` only via `--dart-define`).
- `app/` — Flutter 3.44 / Dart 3.12 client. This file is mostly about `app/`.

Changes stay local until the owner decides to publish.

## 1. App architecture

```
app/lib/
  main.dart                 ProviderScope → BootSplash → MaterialApp.router
  theme/   app_colors.dart  AppColors ThemeExtension (all colour tokens) + Brand
           app_tokens.dart  AppSpace / AppRadius / AppSize / AppMotion / AppType / AppShadow
           app_theme.dart   AppTheme.light / .dark built from AppColors
           ai_surface.dart automated-content surface exceptions
  core/    router.dart      go_router: StatefulShellRoute (tabs per sprint) + AppShell gate
           features.dart    FeatureFlags / featuresProvider — sprint gating (MEDAIX_SPRINT)
           widgets/         the component kit (import `core/widgets/widgets.dart`)
           brand/           BrandLockup / BrandMark / BootSplash
           connectivity.dart isOfflineProvider
           update_checker.dart "Update available" dialog
  data/    repositories.dart  Riverpod providers wiring interfaces → implementations
           api/             ApiClient + ApiReportsRepository / ApiProfileRepository
           fake/            in-memory fakes (meds, wellness, share, doctor, insights, …)
           prefs/           SharedPreferences-backed settings
  features/<feature>/{data,providers,ui}
```

- Screens read only from repository providers (`lib/data/repositories.dart`).
  Never call `ApiClient` or Supabase from a widget.
- Reports and profile use the real backend behind `ReportsRepository` /
  `ProfileRepository`; `--dart-define=MEDAIX_FAKE_DATA=true` swaps in fakes.
  Medicines, wellness, share, doctor match and insights are in-memory fakes.
- Auth is Supabase (email/password + Google) via `AuthGateway`; the router
  redirects to `/sign-in` without a session. `AppShell` shows onboarding until
  the profile is complete or the user skipped.
- **Sprint gating.** Delivery follows `docs/roadmap.md` one epic per sprint.
  `core/features.dart` reads `MEDAIX_SPRINT` (default 5 = the current sprint)
  and `featuresProvider` hides every tab, Home tile, Settings row and route
  from a later sprint (wellness 4, meds 9, scan 10, doctor match 11, share 12,
  portal + reminders 13). New screens must check the flag the same way. Bump
  the default only when that sprint's backend is wired;
  `--dart-define=MEDAIX_SPRINT=13` shows everything for a demo.
  `test/feature_gate_test.dart` pins the current sprint; the test harness
  enables all features so screen tests can reach any screen.
- Routes: tabs `/`, `/reports`, `/meds`, `/wellness`, `/settings`; nested
  `/reports/upload`, `/reports/trends`, `/reports/:id`, `/meds/scan`,
  `/settings/{profile,reminders,share,doctor-portal}`; top-level `/sign-in`,
  `/onboarding`, `/doctor`, `/gallery`. Short aliases (`/upload`, `/scan`,
  `/share`, …) redirect to the nested paths so Back lands on the parent tab.

## 2. Workflow and quality gates

From `app/` after every change:

```powershell
dart format lib test
flutter analyze          # must be clean, zero infos
flutter test             # all green
```

- `test/design_system_test.dart` is the design guard: palette drift, WCAG
  contrast, 48 dp hit targets, and source scans for `BackdropFilter`, blur,
  gradients, `BoxShadow`, hex literals and `Colors.*` swatches. `ai_surface.dart` is the only additional allow-listed visual exception. Keep it green;
  do not add exemptions without a token-level reason.
- `test/support/test_app.dart` gives `testApp()`, `testAppAt(route)`,
  `testScreen(widget)` and `fakeOverrides(...)` with zero-latency fakes.
- Windows/PowerShell: curly quotes break here-strings; use `adb pull` for
  screenshots (never `>` redirection); `flutter test` on a single file ≈ 20 s.
- Emulator smoke test: `emulator-5554`, package `com.tahasync.medaix`, local
  API at `http://10.0.2.2:8000`, sample report `/sdcard/Download/lab-cbc.jpg`.

## 3. Design direction — flat, minimal, production

The visual source of truth is `design/medaix-mockup.html`. Where this file and
the mockup disagree, the mockup wins.

### 3a. Surfaces and depth

- No `BackdropFilter`, no `ImageFilter.blur`, no translucent cards, and no
  frosted sheets.
- **No gradients, blur, or decorative shadows.** The skeleton shimmer is the
  only gradient. `AppShadow.nav` is light-mode only; dark navigation uses a
  top hairline. Automated content has three exceptions, all implemented in
  `theme/ai_surface.dart`: a solid `aiTint`, a 1.5 px `ai` border, and a dark
  `aiGlow` on a busy automated action button only.
- Depth comes from tone: `background` → `surface` (cards) → `surfaceModal`
  (dialogs and bottom sheets). Light cards use a 1 px `hairline` border. Dark
  mode has no black shadows.
- Radii: card 24, tile 22, button 24 (pill), chip 17, icon tile 14, nav 32.
  Screen and card padding 18, card gap 12.

### 3b. Colour and type tokens

- Every colour comes from `context.colors.<token>` (`AppColors`). No hex
  literals or `Colors.*` outside `lib/theme/`. Status is never colour alone:
  use `StatusLabel` / `CardTag` so an icon and text accompany the colour.
- Dark: bg `#0E1726`, surface `#1E293B`, surface2 `#273449`, modal `#334155`,
  primary `#A8B0D5`, onPrimary `#0E1726`, text `#F1F5F9`, muted `#A3B1C6`,
  ai `#BDA7FF`, aiFill `#9333EA`, ok `#34D399`, warn `#FBBF24`, error
  `#F87171`, hairline `#334155`, outlineStrong `#8A99AE`.
- Light: bg `#F8FAFC`, surface/modal `#FFFFFF`, surface2 `#E8EDF4`, primary
  `#182346`, onPrimary `#FFFFFF`, text `#0F172A`, muted `#475569`, ai `#6D45E8`,
  ok `#047857`, warn `#92400E`, error `#B91C1C`, hairline `#E2E8F0`,
  outlineStrong `#64748B`.
- Theme mode System / Light / Dark persisted in SharedPreferences and
  selectable in Settings.
- Type is Figtree (bundled in `assets/fonts`, not google_fonts): h1 28/700
  (−0.4), h2 19/600, h3 16/600, body 15/400 lh 1.45, small 13. The app must
  survive 200 % text scale and a 320 dp wide screen without overflow.

### 3c. Components, copy and states

- Use the kit, don't fork it: `AppScreen`/`ScreenHeader`, `AppCard`,
  `AiInsightCard`, `PrimaryButton`/`GhostButton`/`LinkButton`/`AppIconButton`,
  `AppChip`, `StatusLabel`, `IconTile`, `TileButton`, `ListRow(s)`,
  `ProgressBar`, `SkeletonBox`, `EmptyState`, `ErrorCard`, `OfflineBanner`,
  `AppSwitch`, `FloatingNav`, `QrCard`, `showToast`.
- Icons are Lucide (`package:lucide_icons_flutter`), never emoji. Decorative
  icons are excluded from semantics; every icon button has a label.
- Copy is sentence case and plain. CTAs name the action ("Try again",
  "View report"), never "OK" / "Submit". Errors never show raw exceptions and
  always say whether the user's data is safe.
- Every screen has Normal, Empty, Loading (skeleton at real size), Error,
  Success, Offline, Permission-denied (explain first, offer a fallback) and
  Disabled states.
- Hit targets ≥ 48 dp (chips 34, or 44 as a main control). Switches use
  `AppSwitch` (52 × 30, `Semantics(toggled:)`). Motion 150–250 ms ease-out
  via `AppMotion`, honouring `disableAnimations`.
- Sample/fake data must read as obviously fake; numbers from OCR are never
  altered client-side.

## 4. Dependencies

Discuss before adding anything not already in `app/pubspec.yaml`. Current UI
stack: flutter_riverpod, go_router, lucide_icons_flutter, shared_preferences,
fl_chart, connectivity_plus, supabase_flutter, http, file_picker,
image_picker, package_info_plus, url_launcher.
