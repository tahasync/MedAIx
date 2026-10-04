"""Generate the MedAIx brand marks: launcher icons, adaptive layers and the
full wordmark lockup.

Design language
---------------
2027-style professional minimal, following the brand reference:

* Background is a single diagonal sweep through the brand spectrum --
  deep royal blue -> azure -> cyan -> teal. The hues are anchored on the
  locked Navy/Steel pair in ``lib/src/theme.dart`` and extended with the
  cyan/teal that carries the "AI + care" meaning.
* The mark is a single rounded medical cross with an ECG trace knocked out
  of it, so the gradient reads through the pulse. One shape, one idea, and it
  still resolves at 48px.
* Depth is restrained: one soft drop shadow under the cross and a faint
  specular wash in the top-left of the tile. No skeuomorphism, no clutter.

Everything is rendered at 4x and downsampled with LANCZOS so small densities
stay crisp instead of being a shrunken 1024px.

Run with:
    uv run --with pillow python tool/generate_icons.py

Add ``--preview`` to also write ``tool/out/preview.png``, a contact sheet used
while iterating on the design.
"""

from __future__ import annotations

import argparse
import math
from functools import lru_cache
from pathlib import Path

from PIL import (
    Image,
    ImageChops,
    ImageDraw,
    ImageEnhance,
    ImageFilter,
    ImageFont,
)

# --------------------------------------------------------------------------
# Palette
# --------------------------------------------------------------------------
# Gradient stops for the brand sweep. Anchored on the app's locked
# Navy (#182346) / Steel (#3D5387) and extended with the cyan-teal range.
GRADIENT = [
    (0.00, (9, 40, 112)),  # #092870  deep royal blue
    (0.50, (18, 80, 190)),  # #1250BE  royal
    (0.76, (26, 134, 224)),  # #1A86E0  azure
    (0.91, (24, 180, 222)),  # #18B4DE  cyan
    (1.00, (22, 208, 182)),  # #16D0B6  teal
]

NAVY = (24, 35, 70)  # #182346 locked brand navy
STEEL = (61, 83, 135)  # #3D5387 locked brand steel
SLATE = (124, 131, 173)  # #7C83AD locked brand slate
WHITE = (255, 255, 255)

# Flat trace colour for the adaptive foreground, where the layer may sit on any
# background. Deep enough to read against white or a pale wallpaper.
TRACE_ON_LIGHT = (16, 74, 168)  # #104AA8

# Tagline tone: a touch deeper than Slate so the letterspaced caps hold up when
# the lockup is printed or scaled down.
TAGLINE_INK = (86, 96, 142)  # #56608E

ROOT = Path(__file__).resolve().parent.parent
FONT_DIR = Path(__file__).resolve().parent / "fonts"
SUPERSAMPLE = 4

# Variable-font instances (weight axis 100-900).
WORDMARK_FONT = FONT_DIR / "Montserrat-var.ttf"
TAGLINE_FONT = FONT_DIR / "Montserrat-var.ttf"

# Android launcher densities (px).
ANDROID = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}

# Adaptive-icon foreground: 108dp canvas, inner 72dp safe zone.
ADAPTIVE_FOREGROUND = {
    "mipmap-mdpi": 108,
    "mipmap-hdpi": 162,
    "mipmap-xhdpi": 216,
    "mipmap-xxhdpi": 324,
    "mipmap-xxxhdpi": 432,
}

# iOS icon filenames -> pixel size (matches the Xcode appiconset).
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
    "Icon-App-1024x1024@1x.png": 1024,
}


# --------------------------------------------------------------------------
# Colour helpers
# --------------------------------------------------------------------------


def sample_gradient(t: float) -> tuple[int, int, int]:
    """Interpolate the brand gradient at ``t`` in [0, 1]."""
    t = max(0.0, min(1.0, t))
    for (t0, c0), (t1, c1) in zip(GRADIENT, GRADIENT[1:]):
        if t0 <= t <= t1:
            span = t1 - t0
            f = 0.0 if span == 0 else (t - t0) / span
            # Smoothstep between stops keeps the sweep from banding.
            f = f * f * (3 - 2 * f)
            return tuple(round(a + (b - a) * f) for a, b in zip(c0, c1))
    return GRADIENT[-1][1]


def gradient(size: int, angle_deg: float = 35.0) -> Image.Image:
    """Diagonal brand gradient.

    Built as a small image and upscaled: the ramp is perfectly smooth so
    nothing is lost, and this stays fast even at the 4096px supersampled
    working size used for the 1024px store icon.
    """
    small = 256
    rad = math.radians(angle_deg)
    dx, dy = math.cos(rad), math.sin(rad)
    denom = abs(dx) + abs(dy) or 1.0
    offset = (abs(dx) + abs(dy)) / 2

    img = Image.new("RGB", (small, small))
    put = img.load()
    n = small - 1
    for y in range(small):
        base = (y / n * dy + offset) / denom
        row = [
            sample_gradient(base + x / n * dx / denom)
            for x in range(small)
        ]
        for x, colour in enumerate(row):
            put[x, y] = colour
    return img.resize((size, size), Image.BICUBIC)


def add_specular(img: Image.Image, strength: float = 0.16) -> Image.Image:
    """Faint top-left light wash + bottom vignette for a little dimension."""
    w, h = img.size
    light = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(light)
    d.ellipse([-w * 0.35, -h * 0.55, w * 0.85, h * 0.62], fill=int(255 * strength))
    light = light.filter(ImageFilter.GaussianBlur(w * 0.12))

    out = img.convert("RGBA")
    wash = Image.new("RGBA", (w, h), WHITE + (0,))
    wash.putalpha(light)
    out = Image.alpha_composite(out, wash)

    # Vignette keeps the mark legible against the brightest gradient corner.
    vign = Image.new("L", (w, h), 0)
    ImageDraw.Draw(vign).ellipse(
        [-w * 0.25, -h * 0.25, w * 1.25, h * 1.25], fill=255
    )
    vign = vign.filter(ImageFilter.GaussianBlur(w * 0.18)).point(lambda v: 255 - v)
    dark = Image.new("RGBA", (w, h), (4, 18, 48, 0))
    dark.putalpha(vign.point(lambda v: int(v * 0.14)))
    return Image.alpha_composite(out, dark)


# --------------------------------------------------------------------------
# The mark
# --------------------------------------------------------------------------

# Normalised cross geometry (fractions of the tile edge).
CROSS_SPAN = 0.640  # outer edge to outer edge
CROSS_ARM = 0.250  # bar thickness
CROSS_RADIUS = 0.062  # corner softening

# ECG trace, normalised (x, y) with y measured downward from centre.
# A single confident spike reads as "vitals" at 48px; extra detail does not.
PULSE_POINTS = [
    (0.000, 0.000),
    (0.285, 0.000),
    (0.355, -0.300),
    (0.430, 0.330),
    (0.500, 0.000),
    (0.640, 0.000),
    (0.720, -0.105),
    (0.800, 0.000),
    (1.000, 0.000),
]


def cross_mask(size: int) -> Image.Image:
    """Alpha mask of the rounded medical cross, centred on the canvas."""
    mask = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mask)
    span = size * CROSS_SPAN
    arm = size * CROSS_ARM
    radius = size * CROSS_RADIUS
    lo, hi = (size - span) / 2, (size + span) / 2
    d.rounded_rectangle(
        [lo, (size - arm) / 2, hi, (size + arm) / 2], radius=radius, fill=255
    )
    d.rounded_rectangle(
        [(size - arm) / 2, lo, (size + arm) / 2, hi], radius=radius, fill=255
    )
    return mask


def pulse_mask(size: int, stroke: float) -> Image.Image:
    """Alpha mask of the ECG trace spanning the cross horizontally."""
    mask = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mask)
    span = size * 0.78
    left = (size - span) / 2
    cy = size / 2
    amp = size * 0.185
    pts = [(left + x * span, cy + y * amp) for x, y in PULSE_POINTS]
    w = max(2, round(stroke))
    d.line(pts, fill=255, width=w, joint="curve")
    # Round caps: PIL's polyline ends are square.
    r = w / 2
    for px, py in (pts[0], pts[-1]):
        d.ellipse([px - r, py - r, px + r, py + r], fill=255)
    return mask


def draw_mark(size: int, scale: float = 1.0, knock_pulse: bool = True) -> Image.Image:
    """White rounded cross with a soft drop shadow.

    The cross is drawn solid; [render_tile] paints the ECG trace on top in the
    brand gradient. Keeping the two as separate layers means the horizontal bar
    is never sliced through, which reads far cleaner at small sizes.
    """
    body = Image.new("RGBA", (size, size), WHITE + (255,))
    mask = cross_mask(size)
    body.putalpha(mask)

    shadow = Image.new("RGBA", (size, size), (5, 22, 58, 0))
    shadow.putalpha(
        mask.filter(ImageFilter.GaussianBlur(size * 0.020)).point(
            lambda v: int(v * 0.30)
        )
    )
    shadow = ImageChops.offset(shadow, int(size * 0.010), int(size * 0.018))
    return Image.alpha_composite(shadow, body)


def draw_trace(size: int, stroke_scale: float = 1.0, colour=None) -> Image.Image:
    """ECG trace filled with the brand gradient, centred on the cross.

    ``colour`` overrides the gradient with a flat colour (used for the
    adaptive foreground, which must stay legible on any themed background).
    """
    mask = pulse_mask(size, size * 0.040 * stroke_scale)
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    if colour is None:
        bbox = mask.getbbox()
        gw, gh = bbox[2] - bbox[0], bbox[3] - bbox[1]
        grad = ImageEnhance.Color(
            gradient(max(gw, gh), 12.0).resize((gw, gh), Image.BICUBIC)
        ).enhance(1.25)
        grad = grad.convert("RGBA")
        grad.putalpha(mask.crop(bbox))
        layer.alpha_composite(grad, (bbox[0], bbox[1]))
    else:
        fill = Image.new("RGBA", (size, size), colour + (255,))
        fill.putalpha(mask)
        layer = fill
    layer.putalpha(ImageChops.multiply(layer.getchannel("A"), mask))
    return layer


def rounded_mask(size: int, radius_ratio: float = 0.2237) -> Image.Image:
    """Legacy launcher squircle mask (~22.4% == Android adaptive corner)."""
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, size - 1, size - 1], radius=round(size * radius_ratio), fill=255
    )
    return mask


@lru_cache(maxsize=32)
def render_tile(size: int, scale: float = 1.0) -> Image.Image:
    """Full-bleed gradient tile: white cross + gradient ECG trace.

    Cached because the legacy squircle, the round variant and the contact sheet
    all render the same tile at the same size.
    """
    big = size * SUPERSAMPLE
    base = add_specular(gradient(big))
    base.alpha_composite(draw_mark(big, scale))
    base.alpha_composite(draw_trace(big))
    return base.resize((size, size), Image.LANCZOS)


def render_icon(size: int, scale: float = 1.0) -> Image.Image:
    """Legacy (pre-adaptive) launcher icon: tile clipped to the squircle."""
    out = render_tile(size, scale).convert("RGBA")
    out.putalpha(rounded_mask(size))
    return out


def render_round(size: int) -> Image.Image:
    """Legacy round variant for launchers that ask for ``roundIcon``."""
    out = render_tile(size).convert("RGBA")
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, size - 1, size - 1], fill=255)
    out.putalpha(mask)
    return out


def render_ios(size: int) -> Image.Image:
    """Store icon: opaque and square (Apple applies its own mask)."""
    return render_tile(size).convert("RGB")


def _safe_zone_mask(big: int) -> Image.Image:
    """Cross mask sized to 62% of the canvas, centred (fits the 72dp zone)."""
    inner = int(big * 0.62)
    off = (big - inner) // 2
    mask = Image.new("L", (big, big), 0)
    mask.paste(cross_mask(inner), (off, off))
    return mask


def render_adaptive_background(size: int) -> Image.Image:
    """Full-bleed 108dp background layer for the adaptive icon.

    This is the layer the launcher actually shows on Android 8+, so it is
    rendered from the same gradient, specular wash and vignette as
    :func:`render_tile`. Generating it as a bitmap (rather than the 3-stop
    ``ic_launcher_background.xml`` shape drawable it replaces) is what makes
    the home-screen icon match ``logo.png`` instead of approximating it.

    No mark is drawn here: the foreground layer supplies the cross and trace,
    which is the whole point of the adaptive split.
    """
    big = size * SUPERSAMPLE
    return add_specular(gradient(big)).resize((size, size), Image.LANCZOS)


def render_adaptive_foreground(size: int) -> Image.Image:
    """Transparent 108dp layer with the mark inside the 72dp safe zone.

    The trace is a flat brand azure rather than the tile gradient: an adaptive
    foreground is composited over an arbitrary background (including user
    wallpapers and Android 13 themed icons), so it cannot rely on the tile.
    """
    big = size * SUPERSAMPLE
    layer = Image.new("RGBA", (big, big), (0, 0, 0, 0))

    body = Image.new("RGBA", (big, big), WHITE + (255,))
    body.putalpha(_safe_zone_mask(big))
    layer.alpha_composite(body)

    # Re-render the trace on the reduced cross so it spans the arms rather
    # than overhanging them on the themed-icon layer.
    inner = int(big * 0.62)
    off = (big - inner) // 2
    trace = Image.new("RGBA", (inner, inner), (0, 0, 0, 0))
    trace.alpha_composite(draw_trace(inner, stroke_scale=0.95, colour=TRACE_ON_LIGHT))
    layer.alpha_composite(trace, (off, off))
    return layer.resize((size, size), Image.LANCZOS)


def render_monochrome(size: int) -> Image.Image:
    """Android 13 themed-icon layer: flat white silhouette, no gradient."""
    big = size * SUPERSAMPLE
    layer = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    layer.putalpha(_safe_zone_mask(big))
    return layer.resize((size, size), Image.LANCZOS)


# --------------------------------------------------------------------------
# Typography / lockup
# --------------------------------------------------------------------------


def font(path: Path, px: int, weight: int) -> ImageFont.FreeTypeFont:
    """Load a variable font at a given weight (ignored for static fonts)."""
    f = ImageFont.truetype(str(path), px)
    try:
        f.set_variation_by_axes([weight])
    except OSError:
        pass
    return f


def text_width(draw: ImageDraw.ImageDraw, s: str, f: ImageFont.FreeTypeFont) -> float:
    return draw.textlength(s, font=f)


def gradient_text(
    img: Image.Image,
    xy: tuple[float, float],
    text: str,
    f: ImageFont.FreeTypeFont,
    angle_deg: float = 15.0,
) -> float:
    """Draw ``text`` filled with the brand gradient.

    Uses the same top-left anchoring as ``ImageDraw.text`` so a gradient run
    lines up exactly with the flat-coloured runs beside it; the glyph mask is
    rendered on a padded canvas and composited back at the matching offset.

    Returns the advance width so callers can lay out mixed-colour runs.
    """
    advance = text_width(ImageDraw.Draw(img), text, f)
    pad = 48
    canvas = (int(advance) + pad * 2, int(f.size * 2) + pad * 2)
    mask = Image.new("L", canvas, 0)
    ImageDraw.Draw(mask).text((pad, pad), text, font=f, fill=255)

    bbox = mask.getbbox()
    if bbox is None:
        return advance

    # Colour only the inked region, but composite the full canvas so the
    # glyphs land at precisely the position plain text would use.
    tint = Image.new("RGBA", canvas, (0, 0, 0, 0))
    gw, gh = bbox[2] - bbox[0], bbox[3] - bbox[1]
    grad = ImageEnhance.Color(
        gradient(max(gw, gh), angle_deg).resize((gw, gh), Image.BICUBIC)
    ).enhance(1.08)
    grad = grad.convert("RGBA")
    grad.putalpha(mask.crop(bbox))
    tint.alpha_composite(grad, (bbox[0], bbox[1]))
    tint.putalpha(ImageChops.multiply(tint.getchannel("A"), mask))

    img.alpha_composite(tint, (int(xy[0]) - pad, int(xy[1]) - pad))
    return advance


def draw_ecg_rule(img: Image.Image, y: int, left: int, right: int, weight: float) -> None:
    """Thin gradient ECG rule, used under the tagline."""
    big = img.width
    w = max(2, int(big * weight))
    amp = big * 0.016
    span = right - left
    pts = [
        (left, y),
        (left + span * 0.30, y),
        (left + span * 0.36, y - amp * 1.5),
        (left + span * 0.42, y + amp * 1.5),
        (left + span * 0.47, y),
        (right, y),
    ]
    rule = Image.new("RGBA", (big, img.height), (0, 0, 0, 0))
    rd = ImageDraw.Draw(rule)
    rd.line(pts, fill=WHITE + (255,), width=w, joint="curve")
    r = w / 2
    for px, py in (pts[0], pts[-1]):
        rd.ellipse([px - r, py - r, px + r, py + r], fill=WHITE + (255,))
    grad = gradient(big, 20.0).convert("RGBA")
    tint = Image.composite(
        grad, Image.new("RGBA", grad.size, (0, 0, 0, 0)), rule.getchannel("A")
    )
    img.alpha_composite(tint)


def draw_wordmark(img: Image.Image, y: int, px: int) -> None:
    """Centre the "MedAIx" wordmark: navy "Med"/"x", gradient "AI"."""
    d = ImageDraw.Draw(img)
    wf = font(WORDMARK_FONT, px, 800)
    w_med = text_width(d, "Med", wf)
    w_ai = text_width(d, "AI", wf)
    w_x = text_width(d, "x", wf)
    # Optically tighten the Med|AI and AI|x joins.
    gap = -px * 0.012
    x = (img.width - (w_med + w_ai + w_x + gap * 2)) / 2
    d.text((x, y), "Med", font=wf, fill=NAVY + (255,))
    gradient_text(img, (x + w_med + gap, y), "AI", wf, 15.0)
    d.text((x + w_med + w_ai + gap * 2, y), "x", font=wf, fill=NAVY + (255,))


def render_logo(px: int = 1600) -> Image.Image:
    """Full brand lockup: mark + wordmark + tagline + ECG rule."""
    big = px * 2
    # Soft light plate, echoing the reference's presentation.
    plate = gradient(big, 40.0).convert("L").point(lambda v: 255 - int(v * 0.08))
    img = Image.new("RGBA", (big, big), WHITE + (255,))
    img.putalpha(plate)
    d = ImageDraw.Draw(img)

    # --- Mark -------------------------------------------------------------
    tile = int(big * 0.455)
    img.alpha_composite(
        render_icon(tile), (int((big - tile) / 2), int(big * 0.075))
    )

    # --- Wordmark: "Med" + gradient "AI" + "x" ---------------------------
    draw_wordmark(img, int(big * 0.605), int(big * 0.135))

    # --- Tagline: letterspaced caps --------------------------------------
    tf = font(TAGLINE_FONT, int(big * 0.0335), 500)
    tagline = "SMARTER CARE. BETTER LIVES."
    tracking = big * 0.0125
    widths = [text_width(d, ch, tf) for ch in tagline]
    tx = (big - (sum(widths) + tracking * (len(tagline) - 1))) / 2
    for ch, cw in zip(tagline, widths):
        d.text((tx, int(big * 0.760)), ch, font=tf, fill=TAGLINE_INK + (255,))
        tx += cw + tracking

    # --- ECG rule ---------------------------------------------------------
    draw_ecg_rule(img, int(big * 0.848), int(big * 0.20), int(big * 0.80), 0.0055)
    return img.resize((px, px), Image.LANCZOS)


def render_wordmark(px: int = 1400) -> Image.Image:
    """Wordmark-only lockup (no mark) on transparency, for headers/splash."""
    h = int(px * 0.30)
    img = Image.new("RGBA", (px * 2, h * 2), (0, 0, 0, 0))
    draw_wordmark(img, int(h * 0.20), int(h * 0.80))
    return img.resize((px, h), Image.LANCZOS)


def build_contact_sheet(cell: int = 300) -> Image.Image:
    """Side-by-side of the key outputs, for eyeballing during design."""
    pad = 36
    items = [
        render_ios(512),
        render_adaptive_foreground(216),
        render_icon(96),
        render_monochrome(216),
        render_adaptive_foreground(108),
    ]
    w = pad + len(items) * (cell + pad)
    sheet = Image.new("RGB", (w, cell + pad * 2), (247, 248, 250))
    x = pad
    for im in items:
        # Neutral backdrop so transparent layers are visible.
        bg = Image.new("RGBA", (cell, cell), (225, 228, 236, 255))
        thumb = Image.alpha_composite(bg, im.convert("RGBA").resize(
            (cell, cell), Image.LANCZOS
        ))
        sheet.paste(thumb.convert("RGB"), (x, pad))
        x += cell + pad
    return sheet


def validate() -> list[str]:
    """Check every generated asset: size, colour mode and alpha behaviour.

    Returns a list of problems; empty means the set is consistent.
    """
    problems: list[str] = []
    res = ROOT / "app/android/app/src/main/res"

    def check(path: Path, px: int, mode: str, transparent: bool) -> None:
        if not path.exists():
            problems.append(f"missing: {path.relative_to(ROOT)}")
            return
        with Image.open(path) as im:
            if im.size != (px, px):
                problems.append(f"{path.name}@{path.parent.name}: {im.size} != {(px, px)}")
            if im.mode != mode:
                problems.append(f"{path.name}@{path.parent.name}: mode {im.mode} != {mode}")
            if transparent:
                lo, _ = im.getchannel("A").getextrema()
                if lo != 0:
                    problems.append(f"{path.name}@{path.parent.name}: corners not transparent")

    for folder, px in ANDROID.items():
        check(res / folder / "ic_launcher.png", px, "RGBA", True)
        check(res / folder / "ic_launcher_round.png", px, "RGBA", True)
    for folder, px in ADAPTIVE_FOREGROUND.items():
        check(res / folder / "ic_launcher_background.png", px, "RGBA", False)
        check(res / folder / "ic_launcher_foreground.png", px, "RGBA", True)
        check(res / folder / "ic_launcher_monochrome.png", px, "RGBA", True)
    for name, px in IOS.items():
        ios = ROOT / "app/ios/Runner/Assets.xcassets/AppIcon.appiconset" / name
        check(ios, px, "RGB", False)

    return problems


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate MedAIx brand icons.")
    parser.add_argument(
        "--preview",
        action="store_true",
        help="also write tool/out/preview.png (design contact sheet)",
    )
    args = parser.parse_args()

    written = 0

    android_res = ROOT / "app/android/app/src/main/res"
    for folder, px in ANDROID.items():
        target = android_res / folder / "ic_launcher.png"
        target.parent.mkdir(parents=True, exist_ok=True)
        render_icon(px).save(target, "PNG")
        written += 1
        print(f"android    {target.relative_to(ROOT)}")

        rnd = android_res / folder / "ic_launcher_round.png"
        render_round(px).save(rnd, "PNG")
        written += 1
        print(f"android-r  {rnd.relative_to(ROOT)}")

    for folder, px in ADAPTIVE_FOREGROUND.items():
        bg = android_res / folder / "ic_launcher_background.png"
        render_adaptive_background(px).save(bg, "PNG")
        written += 1
        print(f"adaptivebg {bg.relative_to(ROOT)}")

        fg = android_res / folder / "ic_launcher_foreground.png"
        fg.parent.mkdir(parents=True, exist_ok=True)
        render_adaptive_foreground(px).save(fg, "PNG")
        written += 1
        print(f"adaptive   {fg.relative_to(ROOT)}")

        mono = android_res / folder / "ic_launcher_monochrome.png"
        render_monochrome(px).save(mono, "PNG")
        written += 1
        print(f"monochrome {mono.relative_to(ROOT)}")

    ios_dir = ROOT / "app/ios/Runner/Assets.xcassets/AppIcon.appiconset"
    ios_dir.mkdir(parents=True, exist_ok=True)
    for name, px in IOS.items():
        target = ios_dir / name
        render_ios(px).save(target, "PNG")
        written += 1
        print(f"ios        {target.relative_to(ROOT)}")

    assets = ROOT / "app/assets"
    assets.mkdir(parents=True, exist_ok=True)
    render_logo(1024).save(assets / "logo.png", "PNG")
    print(f"logo       {assets / 'logo.png'}")
    render_wordmark(1024).save(assets / "wordmark.png", "PNG")
    print(f"wordmark   {assets / 'wordmark.png'}")
    written += 2

    if args.preview:
        out = ROOT / "tool/out"
        out.mkdir(parents=True, exist_ok=True)
        build_contact_sheet().save(out / "preview.png", "PNG")
        render_logo(1024).save(out / "logo-preview.png", "PNG")
        print(f"preview    {out / 'preview.png'}")

    problems = validate()
    if problems:
        print("\nVALIDATION FAILED:")
        for p in problems:
            print(f"  - {p}")
        raise SystemExit(1)
    print("validation  all assets sized, coloured and alpha-correct")
    print(f"\n{written} icons written.")


if __name__ == "__main__":
    main()
