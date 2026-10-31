"""Repeatable local OCR benchmark for the repository's synthetic sample panels.

Run from api/: ``.venv/Scripts/python scripts/benchmark_ocr.py --runs 5``.
These fixtures check regressions on clean, printed panels; they do not estimate
accuracy on arbitrary photographed reports.
"""

from __future__ import annotations

import argparse
import statistics
import sys
import time
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from ocr import OcrLanguage, extract_text
from trends import parse_lab_values

SAMPLES = Path(__file__).resolve().parents[1] / "samples"
EXPECTED = {
    "cbc_panel.png": {"Haemoglobin", "White Cell Count", "Platelet Count", "Neutrophils", "Lymphocytes"},
    "cbc_panel_skew3.png": {"Haemoglobin", "White Cell Count", "Platelet Count", "Neutrophils", "Lymphocytes"},
    "lipid_panel.png": {"Total cholesterol", "LDL", "HDL", "Triglycerides"},
    "lipid_panel_skew3.png": {"Total cholesterol", "LDL", "HDL", "Triglycerides"},
    "metabolic.png": {"Fasting glucose", "Blood Urea Nitrogen", "Creatinine", "Sodium", "Potassium"},
    "metabolic_skew3.png": {"Fasting glucose", "Blood Urea Nitrogen", "Creatinine", "Sodium", "Potassium"},
}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runs", type=int, default=5)
    args = parser.parse_args()
    if args.runs < 1:
        parser.error("--runs must be at least 1")

    elapsed_by_sample: dict[str, list[float]] = {name: [] for name in EXPECTED}
    found_by_sample: dict[str, set[str]] = {}
    for run in range(args.runs):
        for filename, expected in EXPECTED.items():
            with Image.open(SAMPLES / filename) as image:
                started = time.perf_counter()
                result = extract_text(image.copy(), OcrLanguage.ENGLISH)
                elapsed_by_sample[filename].append(time.perf_counter() - started)
            rows = parse_lab_values(result.text)
            found = {row.marker for row in rows}
            found_by_sample[filename] = found
            if run == 0:
                print(
                    f"{filename}: rows={len(rows)}, confidence={result.confidence:.1f}, "
                    f"recall={len(found & expected)}/{len(expected)}, "
                    f"missing={sorted(expected - found)}"
                )

    all_expected = sum(len(rows) for rows in EXPECTED.values())
    all_found = sum(
        len(found_by_sample[name] & expected)
        for name, expected in EXPECTED.items()
    )
    all_elapsed = [value for values in elapsed_by_sample.values() for value in values]
    print(
        f"overall marker recall={all_found}/{all_expected} "
        f"({all_found / all_expected:.1%}); runs={args.runs}; "
        f"median latency={statistics.median(all_elapsed):.3f}s; "
        f"p95 latency={_percentile(all_elapsed, 0.95):.3f}s"
    )
    for name, values in elapsed_by_sample.items():
        print(f"{name}: median={statistics.median(values):.3f}s")


def _percentile(values: list[float], fraction: float) -> float:
    ordered = sorted(values)
    return ordered[round((len(ordered) - 1) * fraction)]


if __name__ == "__main__":
    main()
