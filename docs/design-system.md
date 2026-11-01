# MedAIx — Design System

The app's UI follows a **flat, minimal, production** direction. The visual
source of truth is [`design/medaix-mockup.html`](../design/medaix-mockup.html);
the engineering rules are in [`engineering-guide.md`](engineering-guide.md) §3. This page
documents what is implemented in `app/lib/theme` and `app/lib/core/widgets`.
The shipped direction is flat and minimal: there are no gradients, glows, blurs
or decorative shadows outside the defined AI-surface and light-nav exceptions,
[`app/test/design_system_test.dart`](../app/test/design_system_test.dart)
fails the build if any come back.

## 1. Principles

- Depth from tone: `background` → `surface` → `surfaceModal`. Light cards use a
  1 px hairline. Dark mode has no black drop shadows.
- One colour source: `context.colors.<token>` (`AppColors` ThemeExtension).
  No hex literals or Material swatches outside `lib/theme/`.
- Status never by colour alone: `StatusLabel` / `CardTag` pair an icon and
  text with the colour.
- Plain, sentence-case copy; action-named CTAs; errors state data safety.
- Every screen ships its Normal, Empty, Loading, Error, Success, Offline,
  Permission-denied and Disabled states.
- Automated content uses the solid tint and 1.5 px border in
  `app/lib/theme/ai_surface.dart`; dark glow is limited to a busy automated
  action button. The skeleton shimmer is the only gradient.

## 2. Colour tokens (`AppColors`)

| Token | Dark | Light | Use |
| --- | --- | --- | --- |
| `background` | `#0E1726` | `#F8FAFC` | canvas |
| `surface` | `#1E293B` | `#FFFFFF` | cards; light cards have a 1 px hairline |
| `surface2` | `#273449` | `#E8EDF4` | raised tiles, inputs, ghost buttons, chips, nav |
| `surfaceModal` | `#334155` | `#FFFFFF` | dialogs and bottom sheets |
| `primary` / `onPrimary` | `#A8B0D5` / `#0E1726` | `#182346` / `#FFFFFF` | primary actions |
| `text` | `#F1F5F9` | `#0F172A` | body and headings |
| `muted` | `#A3B1C6` | `#475569` | secondary text |
| `ai` / `aiFill` / `onAiFill` | `#BDA7FF` / `#9333EA` / `#FFFFFF` | `#6D45E8` / `#6D45E8` / `#FFFFFF` | automated content |
| `ok` / `warn` / `error` | `#34D399` / `#FBBF24` / `#F87171` | `#047857` / `#92400E` / `#B91C1C` | status icon and word |
| `hairline` / `outlineStrong` | `#334155` / `#8A99AE` | `#E2E8F0` / `#64748B` | dividers and visible boundaries |
| `viewfinder` / `scanFrame` | `#05050A` / `#BFA9BA` | same | scanner |
| `qrPaper` / `qrInk` | `#FFFFFF` / `#0E0D15` | same | QR tile |

Depth uses tone: `background` → `surface` → `surfaceModal`. Automated cards use only `theme/ai_surface.dart`: solid `aiTint`, a 1.5 px `ai` border, and dark `aiGlow` on a busy AI action button. Dark mode has no black drop shadows. Status colour is paired with an icon; on modal surfaces only the icon uses a status colour and the word uses `text`.

Brand (logo only): Ink `#0E0D15`, Navy `#182346`, Steel `#3D5387`, Slate `#7C83AD`, Mauve `#BFA9BA`. `Brand` stays unchanged.
## 3. Spacing, radius, size (`AppSpace`, `AppRadius`, `AppSize`)

| Group | Values |
| --- | --- |
| Spacing | xxs 2 · xs 4 · sm 8 · md 12 · lg 16 · xl 20 · xxl 24 · huge 32; screen/card padding 18; card gap 12; chip gap 8; content max width 560 |
| Radius | card 24 · tile 22 · button 24 (pill) · chip 17 · icon tile 14 · nav 32 · input 16 · toast 18 · QR 20 |
| Hit targets | buttons / icon buttons 48 · chips 34 (44 as a main control) · nav 64 tall, inset 14, five equal full-height slots (≥ 56 wide) with a 64 × 32 primary indicator behind the active icon and the label beneath · switch 52 × 30 |
| Other | progress bar 8 · icon tile 40 · empty-state tile 64 · QR 200 · viewfinder 300 |

## 4. Typography (`AppType`, bundled Figtree)

| Role | Size / weight | Theme slot |
| --- | --- | --- |
| h1 | 28 / 700, −0.4 tracking | `headlineMedium` |
| h2 | 19 / 600 | `titleLarge` |
| h3 | 16 / 600 | `titleMedium` |
| body | 15 / 400, line-height 1.45 | `bodyMedium` |
| small | 13 / 400 | `bodySmall` |
| button | 16 / 600 | `labelLarge` |

Figtree is shipped under `app/assets/fonts` (OFL) so first launch and offline
use render correctly; google_fonts is deliberately not used. The UI is tested
at 200 % text scale and 320 dp width.

## 5. Motion (`AppMotion`)

fast 150 ms · normal 200 ms · slow 250 ms, `Curves.easeOut`; skeleton shimmer
1300 ms; toast 1800 ms. `AppMotion.of(context, d)` returns zero when the
platform asks for reduced motion.

## 6. Component kit (`app/lib/core/widgets/widgets.dart`)

| Area | Widgets |
| --- | --- |
| Frame | `AppScaffold`, `AppScreen` (padding, offline banner, nav clearance, pull-to-refresh), `ScreenHeader`, `SectionTitle`, `ScreenSkeleton` |
| Surfaces | `AppCard` (`CardTone.surface` / `raised`), `CardTag`, `AiInsightCard`, `SummaryRow`, `QrCard` |
| Actions | `PrimaryButton`, `GhostButton`, `LinkButton`, `AppIconButton`, `TileButton`, `Pressable` |
| Selection & status | `AppChip`, `StatusLabel` (`ValueStatus`), `AppSwitch`, `IconTile`, `ListRow` / `ListRows` |
| Feedback | `ProgressBar`, `ScoreRing`, `SkeletonBox` / `SkeletonCard`, `EmptyState`, `ErrorCard`, `OfflineBanner`, `showToast`, `FadeIn`, `StateSwitcher` |
| Navigation | `FloatingNav` (the current sprint's tabs — 3 at Sprint 3, 5 when every epic has shipped; hidden during onboarding and when the keyboard is open) |

The `/gallery` route (debug builds, Settings → Help → Component gallery)
renders every component in both themes as the visual regression reference.

## 7. Guards

`app/test/design_system_test.dart` checks: palette equals the table above,
contrast thresholds, 48 dp targets for buttons / icon buttons / switches,
chip heights, nav item size, and that `lib/` contains no `BackdropFilter`,
`ImageFilter.blur`, `BoxShadow` (outside `app_tokens.dart`), gradients
(outside the shimmer), hex colour literals or `Colors.*` swatches.
