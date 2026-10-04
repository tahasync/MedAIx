# MedAIx — Color System

**Canonical source for MedAIx visual design.** This file replaces the old
`AGENTS.md` §3a–§3b references, which pointed at a document that was deleted
from the repo. Code comments citing "the Color System" refer to this file.

Brand ramp + semantic states, light & dark.

## Brand source (fixed hexes)

These five hexes are locked before build start and must not drift.

| Token | Hex | Constant in `app/lib/src/theme.dart` |
| --- | --- | --- |
| Ink | `#0E0D15` | `AppTheme.ink` |
| Navy | `#182346` | `AppTheme.navy` |
| Steel | `#3D5387` | `AppTheme.steel` |
| Slate | `#7C83AD` | `AppTheme.slate` |
| Mauve | `#BFA9BA` | `AppTheme.mauve` |

## Theme roles (react to the light/dark toggle)

Light and dark are authored **independently**, not derived by inversion.

| Role | Light | Dark |
| --- | --- | --- |
| `primary` | Steel | Slate |
| `secondary` | Slate | Mauve |
| `tertiary` | Mauve | `#818FB1` (lightened Steel) |
| `surface` | `#F7F8FA` | `#121526` (Ink-based, never pure black) |
| `inverseSurface` | Navy | `#E2D8E0` |

Dark is the signature experience. Light stays calm and spacious — never pure
white. `surface` is the *elevated* tier, not the page background; the page
background is Ink in dark.

## Semantic — error / warning / success

`ColorScheme` has no `warning` or `success` roles, so these live in the
`AppSemanticColors` `ThemeExtension`. Read them via `context.semantic.<role>`
rather than casting the extension by hand.

| Role | Light | Dark |
| --- | --- | --- |
| `error` | `#B3261E` | `#D58883` |
| `warning` | `#8A5200` | `#BFA073` |
| `success` | `#1E6B3D` | `#83AE94` |

Dark values are desaturated and lightened to hold contrast against `#121526`.
Each role also ships `Container` / `onContainer` / `on*` variants.

## Representative screens

Design references for the states every screen must implement. **These are not
built yet** — `/health` is still the app's only route as of Week 0.

- **Home / Dashboard** — MedAIx, latest report (CBC Panel — Sep 18), wellness
  score 78/100, "Upload report", next reminder 8:00 AM meds
- **Report Result — Success** — "✓ Report processed. All values reviewed."
- **Simplified Report** — Hemoglobin Normal 14.2 g/dL, Cholesterol Normal
  180 mg/dL, plain-language mode
- **Risk Trend — Warning** — "⚠ Cholesterol trending up over 3 reports",
  suggested recheck in 4 weeks, view trend graph
- **Drug Interaction — Error** — "⛔ Interaction: Warfarin + Ibuprofen —
  bleeding risk", consult your doctor, remove Ibuprofen
- **Empty State** — "No reports yet", upload first lab report to get started,
  primary CTA "Upload report"
- **QR Share** — QR code, "Expires in 14:59", revoke access

## Rules this encodes

- **Status is never colour-only.** Every state pairs colour with an icon and
  text so it survives colour-blindness and greyscale.
- **Semantic colours are not brand colours.** Steel/Slate/Mauve never carry
  meaning; error/warning/success always come from the semantic set.
- **Elevation is intentional.** Cards sit at `elevation: 1` and the navigation
  bar at `elevation: 2` — a "selective glass + subtle elevation" direction, not
  a flat no-elevation look.
- **CTA labels are action-oriented** — "Try again", "View report", "Revoke
  access" rather than "OK" / "Submit" / "Done".