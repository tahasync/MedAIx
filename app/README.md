# MedAIx — Flutter client

The Android client for MedAIx. Week 0: providers, routing, and the brand theme
are in place; the only screen so far is a health check against the API.

See the [root README](../README.md) for the full stack and deployment notes, and
[`docs/color-system.md`](../docs/color-system.md) for the design spec.

## Requirements

Flutter 3.x with Dart 3.12+. No Firebase project is wired up yet — auth arrives
in Sprint 2.

## Setup

```bash
flutter pub get
```

## Run

Point the client at a local API:

```bash
flutter run --dart-define=API_BASE_URL=http://localhost:8000
```

Or at production:

```bash
flutter run --dart-define=API_BASE_URL=https://medaix.onrender.com
```

`API_BASE_URL` defaults to `http://localhost:8000`, so it is only needed when
targeting something else. Release builds bake it in at compile time — see
`.github/workflows/app-build.yml`, which reads it from the `API_BASE_URL`
repository variable and fails the build if unset rather than shipping an APK
pointing at localhost.

### Other build-time flags

| Flag | Default | Purpose |
| --- | --- | --- |
| `API_BASE_URL` | `http://localhost:8000` | API root |
| `API_HEALTH_TIMEOUT` | `30` | Seconds to wait for one health probe |
| `API_HEALTH_ATTEMPTS` | `3` | Retries before reporting unreachable |

The timeout is generous because the free Render instance can take ~50s to wake
from sleep. See `lib/src/api_client.dart`.

## Test

```bash
flutter test
```

## Layout

| Path | Purpose |
| --- | --- |
| `lib/src/api_client.dart` | HTTP wrapper with retry/timeout handling |
| `lib/src/providers.dart` | Riverpod providers, incl. theme mode |
| `lib/src/router.dart` | Routing and the health-check screen |
| `lib/src/theme.dart` | Brand palette, light/dark schemes, semantic colors |
