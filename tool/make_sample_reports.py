"""Generate synthetic lab-report images for local OCR accuracy checks.

Not part of the app or the test suite — this is a dev utility for measuring
real OCR quality on something that looks like a lab report, since Sprint 1's
target is >=85% accuracy and a passing unit test says nothing about that.

Usage:
    python tool/make_sample_reports.py            # writes 3 samples to api/samples/
    python tool/make_sample_reports.py --skew 3.0 # rotate each by N degrees
"""

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

OUTPUT_DIR = Path(__file__).resolve().parent.parent / "api" / "samples"

# Mixed case, digits, units and a reference range — the four things OCR mangles.
REPORTS = [
    {
        "name": "cbc_panel",
        "title": "COMPLETE BLOOD COUNT",
        "rows": [
            ("Haemoglobin", "14.2", "g/dL", "12.0 - 16.0"),
            ("White Cell Count", "6.8", "10*9/L", "4.0 - 11.0"),
            ("Platelet Count", "245", "10*9/L", "150 - 400"),
            ("Neutrophils", "58.4", "%", "40.0 - 75.0"),
            ("Lymphocytes", "27.1", "%", "20.0 - 45.0"),
        ],
    },
    {
        "name": "lipid_panel",
        "title": "LIPID PROFILE",
        "rows": [
            ("Total Cholesterol", "180", "mg/dL", "< 200"),
            ("Triglycerides", "124", "mg/dL", "< 150"),
            ("HDL Cholesterol", "52", "mg/dL", "> 40"),
            ("LDL Cholesterol", "98", "mg/dL", "< 100"),
        ],
    },
    {
        "name": "metabolic",
        "title": "METABOLIC PANEL",
        "rows": [
            ("Glucose (Fasting)", "96", "mg/dL", "70 - 99"),
            ("Blood Urea Nitrogen", "15", "mg/dL", "7 - 20"),
            ("Serum Creatinine", "0.9", "mg/dL", "0.6 - 1.3"),
            ("Sodium", "139", "mmol/L", "135 - 145"),
            ("Potassium", "4.1", "mmol/L", "3.5 - 5.1"),
        ],
    },
]


def _font(size: int) -> ImageFont.FreeTypeFont:
    for candidate in ("arial.ttf", "segoeui.ttf", "calibri.ttf"):
        try:
            return ImageFont.truetype(candidate, size)
        except OSError:
            continue
    return ImageFont.load_default()


def render(report: dict, skew_degrees: float = 0.0) -> Image.Image:
    width, height = 1400, 820
    image = Image.new("L", (width, height), color=255)
    draw = ImageDraw.Draw(image)

    draw.text((60, 50), report["title"], fill=0, font=_font(42))
    draw.line([(60, 110), (width - 60, 110)], fill=0, width=3)

    headers = ("TEST", "RESULT", "UNIT", "REFERENCE")
    columns = (60, 620, 820, 1010)
    for header, column in zip(headers, columns):
        draw.text((column, 140), header, fill=0, font=_font(24))

    for index, row in enumerate(report["rows"]):
        y = 200 + index * 70
        for value, column in zip(row, columns):
            draw.text((column, y), value, fill=0, font=_font(30))

    draw.line(
        [(60, 190), (width - 60, 190)],
        fill=0,
        width=1,
    )
    draw.text(
        (60, height - 90),
        "Sample collected 04/10/2026   Reported by MedAIx Laboratory",
        fill=0,
        font=_font(22),
    )

    if skew_degrees:
        image = image.rotate(
            skew_degrees,
            resample=Image.BICUBIC,
            expand=True,
            fillcolor=255,
        )
    return image


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--skew",
        type=float,
        default=0.0,
        help="rotate each sample by this many degrees (default: 0)",
    )
    args = parser.parse_args()

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    for report in REPORTS:
        suffix = "" if not args.skew else f"_skew{args.skew:g}"
        path = OUTPUT_DIR / f"{report['name']}{suffix}.png"
        render(report, args.skew).save(path)
        print(f"wrote {path}")


if __name__ == "__main__":
    main()