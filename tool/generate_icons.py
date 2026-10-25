"""Install the flat MedAIx brand pack into Android, iOS and in-app assets.

Source of truth: ``brand/`` (the zip at ``C:\\Users\\TahaSync\\Downloads\\medaix-brand.zip``).
This script only resizes those files. It never paints a gradient, glow or
shadow — a test in ``app/test/design_system_test.dart`` fails if one returns.

    uv run --with pillow python tool/generate_icons.py
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
BRAND = ROOT / "brand"

NAVY = (24, 35, 70, 255)  # #182346
INK = (14, 13, 21, 255)  # #0E0D15
PAPER = (247, 244, 242, 255)  # #F7F4F2
BLACK = (0, 0, 0, 255)

ANDROID = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}
ADAPTIVE = {
    "mipmap-mdpi": 108,
    "mipmap-hdpi": 162,
    "mipmap-xhdpi": 216,
    "mipmap-xxhdpi": 324,
    "mipmap-xxxhdpi": 432,
}
LAUNCH_DP = 128
LAUNCH_ANDROID = {
    "drawable-mdpi": LAUNCH_DP,
    "drawable-hdpi": LAUNCH_DP * 3 // 2,
    "drawable-xhdpi": LAUNCH_DP * 2,
    "drawable-xxhdpi": LAUNCH_DP * 3,
    "drawable-xxxhdpi": LAUNCH_DP * 4,
}
IOS = {
    "Icon-App-20x20@1x.png": 20,
    "Icon-App-20x20@2x.png": 40,
    "Icon-App-20x20@3x.png": 60,
    "Icon-App-29x29@1x.png": 29,
    "Icon-App-29x29@2x.png": 58,
    "Icon-App-29x29@3x.png": 87,
    "Icon-App-40x40@1x.png": 40,
    "Icon-App-40x40@2x.png": 80,
    "Icon-App-40x40@3x.png": 120,
    "Icon-App-60x60@2x.png": 120,
    "Icon-App-60x60@3x.png": 180,
    "Icon-App-76x76@1x.png": 76,
    "Icon-App-76x76@2x.png": 152,
    "Icon-App-83.5x83.5@2x.png": 167,
    "Icon-App-1024x1024@1x.png": 1024,
}


def _open(name: str) -> Image.Image:
    path = BRAND / name
    if not path.exists():
        raise SystemExit(f"missing brand file: {path}")
    return Image.open(path).convert("RGBA")


def _resize(img: Image.Image, px: int) -> Image.Image:
    return img.resize((px, px), Image.Resampling.LANCZOS)


def _save(img: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, "PNG")
    print(path.relative_to(ROOT))


def _on_solid(mark: Image.Image, size: int, colour: tuple[int, int, int, int]) -> Image.Image:
    canvas = Image.new("RGBA", (size, size), colour)
    fitted = _resize(mark, size)
    canvas.alpha_composite(fitted)
    return canvas.convert("RGB")


def _monochrome(foreground: Image.Image, size: int) -> Image.Image:
    """Android 13 themed layer: opaque black where the mark is, else transparent."""
    src = _resize(foreground, size)
    alpha = src.split()[-1]
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    black = Image.new("RGBA", (size, size), BLACK)
    out.paste(black, mask=alpha)
    return out


def main() -> None:
    parser = argparse.ArgumentParser(description="Install the flat MedAIx brand pack.")
    parser.parse_args()

    icon = _open("medaix-launcher-icon-1024.png")
    foreground = _open("medaix-launcher-foreground-1024.png")
    mark_light = _open("medaix-mark-512.png")
    mark_dark = _open("medaix-mark-dark-512.png")
    lockup = _open("medaix-lockup.png")
    lockup_dark = _open("medaix-lockup-dark.png")

    android = ROOT / "app/android/app/src/main/res"
    for folder, px in ANDROID.items():
        _save(_on_solid(icon, px, NAVY), android / folder / "ic_launcher.png")
        _save(_on_solid(icon, px, NAVY), android / folder / "ic_launcher_round.png")

    for folder, px in ADAPTIVE.items():
        _save(Image.new("RGBA", (px, px), NAVY), android / folder / "ic_launcher_background.png")
        _save(_resize(foreground, px), android / folder / "ic_launcher_foreground.png")
        _save(_monochrome(foreground, px), android / folder / "ic_launcher_monochrome.png")

    for folder, px in LAUNCH_ANDROID.items():
        _save(_resize(mark_light, px), android / folder / "launch_image.png")
        night = folder.replace("drawable-", "drawable-night-", 1)
        _save(_resize(mark_dark, px), android / night / "launch_image.png")

    ios = ROOT / "app/ios/Runner/Assets.xcassets/AppIcon.appiconset"
    for name, px in IOS.items():
        _save(_on_solid(icon, px, NAVY), ios / name)

    launch_ios = ROOT / "app/ios/Runner/Assets.xcassets/LaunchImage.imageset"
    _save(_resize(mark_light, LAUNCH_DP), launch_ios / "LaunchImage.png")
    _save(_resize(mark_light, LAUNCH_DP * 2), launch_ios / "LaunchImage@2x.png")
    _save(_resize(mark_light, LAUNCH_DP * 3), launch_ios / "LaunchImage@3x.png")
    _save(_resize(mark_dark, LAUNCH_DP), launch_ios / "LaunchImageDark.png")
    _save(_resize(mark_dark, LAUNCH_DP * 2), launch_ios / "LaunchImageDark@2x.png")
    _save(_resize(mark_dark, LAUNCH_DP * 3), launch_ios / "LaunchImageDark@3x.png")

    assets = ROOT / "app/assets"
    _save(lockup, assets / "logo.png")
    _save(lockup_dark, assets / "logo-dark.png")
    _save(_resize(mark_light, 512), assets / "mark.png")
    _save(_resize(mark_dark, 512), assets / "mark-dark.png")
    # Wordmark is the lockup minus the mark; keep the full lockup so a leftover
    # `BrandAssets.wordmark` reference still looks like MedAIx, not a gradient.
    _save(lockup, assets / "wordmark.png")

    brand_app = ROOT / "app/assets/brand"
    brand_app.mkdir(parents=True, exist_ok=True)
    for src in BRAND.iterdir():
        if src.is_file():
            target = brand_app / src.name
            target.write_bytes(src.read_bytes())

    print("installed flat brand pack (no gradients)")


if __name__ == "__main__":
    main()
