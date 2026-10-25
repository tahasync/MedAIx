# MedAIx — Flutter client

The Flutter client for MedAIx.

- **Sprint 1:** camera capture with an explained runtime permission, report
  file selection, language selection (English, Urdu, and Roman Urdu), OCR
  progress, results, and recovery states, alongside the API health check.
- **Sprint 2:** Supabase sign-in (Google or email), a three-step onboarding
  questionnaire that gates the app until the profile is complete, a profile
  screen (view, edit, delete), and the simplified-report screen that lists
  scanned reports and rewrites a chosen one in plain language with a
  side-by-side original view.

See the [root README](../README.md) for the full stack and deployment notes, and
[`docs/color-system.md`](../docs/color-system.md) for the design spec.

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
  --dart-define=SUPABASE_ANON_KEY=<publishable key>
```

From the Android emulator the host PC is `10.0.2.2`, so use
`--dart-define=API_BASE_URL=http://10.0.2.2:8000`. On Windows, the repo-root
`run-app.bat` reads the key from `api/.env` and does this for you.

Or at production:

```bash
flutter run --dart-define=API_BASE_URL=https://medaix.onrender.com \
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
| `SUPABASE_URL` | the hosted project | Supabase project URL |
| `SUPABASE_ANON_KEY` | *(empty — sign-in disabled)* | Supabase publishable key |
| `API_HEALTH_TIMEOUT` | `30` | Seconds to wait for one health probe |
| `API_HEALTH_ATTEMPTS` | `3` | Retries before reporting unreachable |
| `API_UPLOAD_ATTEMPTS` | `3` | Retries for upload / simplify / list calls |

The timeout is generous because the free Render instance can take ~50s to wake
from sleep. See `lib/src/api_client.dart`.

## Test

```bash
flutter analyze
flutter test
```

## Layout

| Path | Purpose |
| --- | --- |
| `lib/src/api_client.dart` | HTTP wrapper with retry/timeout handling |
| `lib/src/auth.dart` | Supabase session gateway (faked in tests) |
| `lib/src/auth_screen.dart` | Sign-in / create account |
| `lib/src/onboarding_screen.dart` | Three-step profile questionnaire |
| `lib/src/profile_screen.dart` | View, edit, and delete the profile |
| `lib/src/providers.dart` | Riverpod providers: theme, auth, upload, simplify, reports, profile |
| `lib/src/router.dart` | Routing, the sign-in/onboarding gate, and the home screen |
| `lib/src/simplify_screen.dart` | Report history and the plain-language result page |
| `lib/src/upload_screen.dart` | Report upload, language selection, and OCR result states |
| `lib/src/theme.dart` | Brand palette, light/dark schemes, semantic colors |
