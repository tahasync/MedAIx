# MedAIx — Flutter client

The Flutter client for MedAIx. The current integration baseline is Sprint 5.

- **Sprint 1:** camera capture with an explained runtime permission, report
  file selection, language selection (English, Urdu, and Roman Urdu), OCR
  progress, results, and recovery states, alongside the API health check.
- **Sprint 2:** Supabase sign-in (Google or email), a three-step onboarding
  questionnaire that gates the app until the profile is complete, a profile
  screen (view, edit, delete), and the simplified-report screen that lists
  scanned reports and rewrites a chosen one in plain language with a
  side-by-side original view.
- **Sprint 3–5:** numeric report values and trends, API-backed wellness logs,
  retry-safe report upload, profile-aware refresh, and data-deletion cleanup
  across server and local caches.
- **UI foundation:** a flat, token-driven five-tab design system with Home,
  Reports, Wellness and More enabled in the Sprint 5 build. Medicines, sharing,
  doctor matching and reminders remain gated until their roadmap sprints.

See the [root README](../README.md) for the full stack and deployment notes,
[`docs/color-system.md`](../docs/color-system.md) for the palette, and
[`docs/design-system.md`](../docs/design-system.md) for the UI/UX system
(type scale, spacing, radii, elevation, motion, component rules).

## Requirements

Flutter 3.x with Dart 3.12+. A Supabase project for sign-in; the publishable
(anon) key is passed at build time and is never committed.

## Setup

```bash
flutter pub get
```

## Run

Point the client at a local API and the Supabase project:

```bash
flutter run \
  --dart-define=API_BASE_URL=http://localhost:8000 \
  --dart-define=SUPABASE_URL=<project URL> \
  --dart-define=SUPABASE_ANON_KEY=<publishable key>
```

From the Android emulator the host PC is `10.0.2.2`, so use
`--dart-define=API_BASE_URL=http://10.0.2.2:8000`. On Windows, the repo-root
`run-app.bat` reads the key from `api/.env` and does this for you.

Or at production:

```bash
flutter run --dart-define=API_BASE_URL=https://medaix.onrender.com \
  --dart-define=SUPABASE_URL=<project URL> \
  --dart-define=SUPABASE_ANON_KEY=<publishable key>
```

`API_BASE_URL` defaults to `http://localhost:8000`, so it is only needed when
targeting something else. Release builds bake it in at compile time — see
`.github/workflows/app-build.yml`, which reads it from the `API_BASE_URL`
repository variable and fails the build if unset rather than shipping an APK
pointing at localhost.

### Build-time flags

| Flag | Default | Purpose |
| --- | --- | --- |
| `API_BASE_URL` | `http://localhost:8000` | API root |
| `MEDAIX_SPRINT` | `5` | Sprint this build represents; tabs, tiles, settings rows and routes from later sprints are hidden (`13` shows everything for a demo) |
| `MEDAIX_FAKE_DATA` | `false` | Use in-memory fakes for reports and profile too (no backend needed) |
| `SUPABASE_URL` | the hosted project | Supabase project URL |
| `SUPABASE_ANON_KEY` | *(empty — sign-in disabled)* | Supabase publishable key |
| `API_HEALTH_TIMEOUT` | `30` | Seconds to wait for one health probe |
| `API_HEALTH_ATTEMPTS` | `3` | Retries before reporting unreachable |
| `API_UPLOAD_ATTEMPTS` | `3` | Retries for upload / simplify / list calls |

The timeout is generous because the free Render instance can take ~50s to wake
from sleep. See `lib/data/api/api_client.dart`.

## Test

```bash
flutter analyze
flutter test
```

## Layout

| Path | Purpose |
| --- | --- |
| `lib/main.dart` | `ProviderScope` → `BootSplash` → `MaterialApp.router` (text scale clamped 0.8–2.0) |
| `lib/theme/app_colors.dart` | `AppColors` ThemeExtension — every colour token for dark and light — plus the locked `Brand` palette |
| `lib/theme/app_tokens.dart` | `AppSpace`, `AppRadius`, `AppSize`, `AppMotion`, `AppType`, `AppShadow` |
| `lib/theme/app_theme.dart` | `AppTheme.light` / `.dark` built from the tokens; flat Material 3 component themes |
| `lib/core/features.dart` | `FeatureFlags` / `featuresProvider`: sprint gating driven by `MEDAIX_SPRINT` |
| `lib/core/router.dart` | go_router: `StatefulShellRoute` with the tabs of the current sprint, nested sub-routes, short-path aliases, sign-in redirect and the onboarding gate (`AppShell`) |
| `lib/core/widgets/` | The component kit (`AppScreen`, `AppCard`, buttons, chips, `StatusLabel`, `ListRow`, `ProgressBar`, skeletons, `EmptyState`, `ErrorCard`, `OfflineBanner`, `AppSwitch`, `FloatingNav`, `QrCard`, `showToast`) |
| `lib/core/brand/brand.dart` | Brand lockup, tile mark, cold-start splash |
| `lib/core/connectivity.dart` | `isOfflineProvider` (connectivity_plus) behind the offline banner |
| `lib/core/update_checker.dart` | "Update available" check against GitHub releases; shown once per session from the shell |
| `lib/data/repositories.dart` | Riverpod providers wiring each repository interface to its implementation (`--dart-define=MEDAIX_FAKE_DATA=true` swaps reports/profile to fakes) |
| `lib/data/api/` | `ApiClient` (HTTP, retry/timeout) and the API-backed reports/profile repositories |
| `lib/data/fake/` | In-memory fakes: reports, meds, wellness, share, doctor match, insights, profile, settings |
| `lib/data/prefs/` | SharedPreferences-backed settings (theme mode, reminders, onboarding seen) |
| `lib/features/<feature>/{data,providers,ui}` | auth, onboarding, home, reports (list / upload / report / trends), meds (list / scan), wellness, doctor, share (QR / doctor portal), settings (settings / reminders), profile, gallery |
| `test/support/test_app.dart` | `testApp()`, `testAppAt(route)`, `testScreen(widget)` and zero-latency `fakeOverrides()` |
| `test/design_system_test.dart` | Palette / contrast / hit-target / no-blur-no-gradient guards |

## Design system

Flat, minimal and production-oriented; the visual source of truth is
[`design/medaix-mockup.html`](../design/medaix-mockup.html) and the rules are in
[`AGENTS.md`](../AGENTS.md) §3 with the implemented tokens documented in
[`docs/design-system.md`](../docs/design-system.md). In short:

- **No glass.** No `BackdropFilter`, blur, gradients, glow or decorative
  shadows; the only shadow is under the floating bottom nav. Depth comes from
  `background` → `surface` → `surface2` tone steps.
- **One colour source.** Widgets read `context.colors.<token>`; there are no
  hex literals or `Colors.*` swatches outside `lib/theme/`, and
  `test/design_system_test.dart` fails if any appear.
- **Fonts** are bundled under `assets/fonts/` (SIL OFL licences alongside):
  Figtree for all UI text, Noto Sans as the fallback. Bundling instead of
  `google_fonts` keeps first paint deterministic offline and avoids a runtime
  download on a health app.
- **Icons** are Lucide via `lucide_icons_flutter`; status is never conveyed by
  colour alone (`StatusLabel` / `CardTag` pair an icon with text).
- **States.** Every screen ships Normal, Empty, Loading (skeleton), Error,
  Success, Offline, Permission-denied and Disabled states; copy is sentence
  case with action-named CTAs and errors always say whether data is safe.
- **Theme mode** (System / Light / Dark) persists in SharedPreferences and is
  chosen in Settings. The `/gallery` route (debug builds) renders the whole
  kit in both themes.
## Branding

`assets/logo.png` is the complete lockup (gradient tile, "MedAIx" wordmark,
"SMARTER CARE. BETTER LIVES." tagline). It is shown by the Flutter-side splash,
the sign-in screen, and the profile-loading gate. The launcher icon is the tile
only: Android clips adaptive icons to a circle or squircle and the Android 12+
system splash draws that icon, so the wordmark cannot fit there. Every bitmap
(launcher icons, `launch_image.png`, iOS `LaunchImage`, `assets/*.png`) is
generated by `tool/generate_icons.py`; do not hand-edit them.
