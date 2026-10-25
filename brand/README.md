# MedAIx brand assets (flat, no gradients)

Mark: a rounded cross (care) with a four-point spark (AI). Colours come from the app palette: Navy `#182346`, Steel `#3D5387`, Mauve `#BFA9BA`, Ink `#0E0D15`, Paper `#F7F4F2`.

| File | Use |
|---|---|
| `medaix-launcher-icon-1024.png` / `.svg` | iOS icon and Android legacy icon (full bleed, no transparency) |
| `medaix-launcher-foreground-1024.png` / `.svg` | Android adaptive foreground (mark inside the 66% safe zone) |
| `medaix-launcher-background.svg` | Android adaptive background. Use the plain colour `#182346` |
| `medaix-launcher-monochrome.svg` | Android 13 themed icon |
| `medaix-mark.svg` / `medaix-mark-512.png` | Mark on light backgrounds (splash light, in-app) |
| `medaix-mark-dark.svg` | Mark on dark backgrounds (splash dark) |
| `medaix-lockup.svg` / `.png`, `medaix-lockup-dark.svg` / `.png` | `BrandLockup` (wordmark outlined from Figtree SemiBold, no font needed) |

`pubspec.yaml`:

```yaml
flutter_launcher_icons:
  android: true
  ios: true
  image_path: assets/brand/medaix-launcher-icon-1024.png
  adaptive_icon_background: "#182346"
  adaptive_icon_foreground: assets/brand/medaix-launcher-foreground-1024.png
  remove_alpha_ios: true

flutter_native_splash:
  color: "#F7F4F2"
  image: assets/brand/medaix-mark-512.png
  color_dark: "#0E0D15"
  image_dark: assets/brand/medaix-mark-dark-512.png   # export from medaix-mark-dark.svg
  android_12:
    color: "#F7F4F2"
    image: assets/brand/medaix-mark-512.png
    color_dark: "#0E0D15"
    image_dark: assets/brand/medaix-mark-dark-512.png
```

Rules: never add a gradient, glow or shadow to the mark. Keep clear space of at least half the cross width around it. Minimum size 24 px for the mark, 96 px wide for the lockup.
