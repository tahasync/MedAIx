# MedAIx color system

This is the canonical UI palette for Flutter. The values live in `app/lib/theme/app_colors.dart`; widgets read them through `context.colors`. `Brand` remains unchanged and is reserved for logos and launcher artwork. Project design rules are in [`engineering-guide.md`](engineering-guide.md) §3.

## UI tokens

| Token | Light | Dark |
|---|---|---|
| background | #F8FAFC | #0E1726 |
| surface | #FFFFFF | #1E293B |
| surface2 | #E8EDF4 | #273449 |
| surfaceModal | #FFFFFF | #334155 |
| text | #0F172A | #F1F5F9 |
| muted | #475569 | #A3B1C6 |
| primary / onPrimary | #182346 / #FFFFFF | #A8B0D5 / #0E1726 |
| ai | #6D45E8 | #BDA7FF |
| aiFill / onAiFill | #6D45E8 / #FFFFFF | #9333EA / #FFFFFF |
| ok | #047857 | #34D399 |
| warn | #92400E | #FBBF24 |
| error | #B91C1C | #F87171 |
| hairline | #E2E8F0 | #334155 |
| outlineStrong | #64748B | #8A99AE |

`aiTint` is `ai` at 4% over `surface` in light mode and 10% in dark mode. Scanner and QR tokens are unchanged.

The dark `primary` is slightly lighter than the initial proposal so it clears 4.5:1 against the modal layer too.

## Layers and use

- Layer 0: `background`.
- Layer 1: `surface`; light-mode cards use a 1 px `hairline` border.
- Layer 2: `surfaceModal` for dialogs and bottom sheets.
- Dark mode has no black drop shadows. The floating navigation uses `surface2` and a top hairline; the light navigation may use `AppShadow.nav`.
- Automated content uses only `app/lib/theme/ai_surface.dart`: a solid `aiTint`, a 1.5 px `ai` border, and a dark `aiGlow` on a busy AI action button. Purple is reserved for automated content and always appears with its label/icon.
- `ok`, `warn`, and `error` use icons and words. On modal surfaces, status color is icon-only and the word uses `text`.
- Inputs and unselected chips use a visible fill or `outlineStrong` border.

## Brand palette (unchanged)

| Brand token | Hex | Use |
|---|---|---|
| `Brand.ink` | #0E0D15 | Logo artwork |
| `Brand.navy` | #182346 | Logo artwork and launcher |
| `Brand.steel` | #3D5387 | Logo artwork |
| `Brand.slate` | #7C83AD | Logo artwork |
| `Brand.mauve` | #BFA9BA | Logo artwork |

Do not use `Brand` constants as application UI tokens. Do not add gradients, blur, or decorative shadows.
