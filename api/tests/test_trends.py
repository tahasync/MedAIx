"""Unit tests for the Sprint 3 rule-based trend engine (``trends.py``).

Pure functions, no database: reports are plain namespaces with ``id``,
``uploaded_at`` and ``original_text``.
"""

from datetime import datetime
from types import SimpleNamespace

import pytest

from trends import (
    DEFAULT_RANGES,
    build_risk_trends,
    canonical_marker,
    focus_markers,
    guess_panel_title,
    parse_lab_values,
    summarise_report,
)

NOW = datetime(2026, 10, 25, 16, 0, 0)


def _report(report_id: int, month: int, text: str) -> SimpleNamespace:
    return SimpleNamespace(
        id=report_id,
        uploaded_at=datetime(2026, month, 2, 9, 30),
        original_text=text,
    )


def _user(sex: str | None = None, conditions: str = "") -> SimpleNamespace:
    return SimpleNamespace(sex_at_birth=sex, sex=None, conditions=conditions)


def _series(marker_line: str, *values: str) -> list[SimpleNamespace]:
    """One report per value, one month apart, e.g. ``_series("HbA1c {} %", "5.9", "6.1")``."""
    return [
        _report(index + 1, index + 1, marker_line.format(value))
        for index, value in enumerate(values)
    ]


def _trend(result: dict, marker: str) -> dict:
    return next(trend for trend in result["trends"] if trend["marker"] == marker)


# ---- parser ----------------------------------------------------------------


def test_parser_reads_marker_value_unit_and_range() -> None:
    [parsed] = parse_lab_values("Haemoglobin 14.2 g/dL 12.0 - 16.0")

    assert parsed.marker == "Haemoglobin"
    assert parsed.value == 14.2
    assert parsed.raw_value == "14.2"
    assert parsed.unit == "g/dL"
    assert (parsed.low, parsed.high) == (12.0, 16.0)
    assert (parsed.raw_low, parsed.raw_high) == ("12.0", "16.0")


@pytest.mark.parametrize(
    ("line", "low", "high"),
    [
        ("HbA1c 5.9 % 4.0-6.0", 4.0, 6.0),
        ("HbA1c 5.9 % 4.0 – 6.0", 4.0, 6.0),
        ("Fasting glucose 95 mg/dL 70-99", 70.0, 99.0),
        ("Total cholesterol 180 mg/dL < 200", None, 200.0),
        ("HDL cholesterol 48 mg/dL > 40", 40.0, None),
        ("Glucose, Fasting : 95 mg/dL (70 to 99)", 70.0, 99.0),
        ("Creatinine 1.0 mg/dL", None, None),
    ],
)
def test_parser_reads_reference_range_shapes(line: str, low: float | None, high: float | None) -> None:
    [parsed] = parse_lab_values(line)

    assert (parsed.low, parsed.high) == (low, high)


def test_parser_tolerates_ocr_noise() -> None:
    text = "\n".join(
        [
            "COMPLETE BLOOD COUNT",
            "Date: 02/03/2026   Time: 10:30",
            "Patient ID: 4471   Age: 45 Years",
            "TEST RESULT UNIT REFERENCE",
            "| Haemoglobin | 14.2 | g/dL | 12.0 - 16.0 |",
            "Platelets 245 10*9/L 150 - 400",
            "HbA1c (Glycated Hemoglobin) 5.9 % 4.0-6.0",
            "Vitamin B12 350 pg/mL 200 – 900",
            "- Sodium 140 mmol/L",
            "",
        ]
    )

    parsed = parse_lab_values(text)

    assert [row.marker for row in parsed] == [
        "Haemoglobin",
        "Platelets",
        "HbA1c",
        "Vitamin B12",
        "Sodium",
    ]
    assert [row.value for row in parsed] == [14.2, 245.0, 5.9, 350.0, 140.0]
    assert parsed[1].unit == "10*9/L"
    assert (parsed[3].low, parsed[3].high) == (200.0, 900.0)


def test_parser_ignores_lines_without_a_number() -> None:
    assert parse_lab_values("Haemoglobin g/dL\nNo value here") == []
    assert parse_lab_values("") == []
    assert parse_lab_values(None) == []


def test_parser_keeps_a_less_than_prefix_in_the_raw_value() -> None:
    [parsed] = parse_lab_values("CRP < 5 mg/L")

    assert parsed.value == 5.0
    assert parsed.raw_value == "<5"


@pytest.mark.parametrize(
    ("printed", "canonical"),
    [
        ("HbA1c", "HbA1c"),
        ("Glycated haemoglobin", "HbA1c"),
        ("Glycosylated Hemoglobin (A1c)", "HbA1c"),
        ("Fasting Blood Sugar", "Fasting glucose"),
        ("FBS", "Fasting glucose"),
        ("Glucose Fasting", "Fasting glucose"),
        ("Fasting Plasma Glucose", "Fasting glucose"),
        ("Total Cholesterol", "Total cholesterol"),
        ("Cholesterol", "Total cholesterol"),
        ("LDL Cholesterol", "LDL"),
        ("LDL-C", "LDL"),
        ("HDL Cholesterol", "HDL"),
        ("Triglycerides", "Triglycerides"),
        ("Serum Creatinine", "Creatinine"),
        ("TSH", "TSH"),
        ("Thyroid Stimulating Hormone", "TSH"),
        ("Hemoglobin", "Haemoglobin"),
        ("Hb", "Haemoglobin"),
        ("HGB", "Haemoglobin"),
        ("platelet count", "Platelet Count"),
        ("WBC", "WBC"),
    ],
)
def test_marker_synonyms(printed: str, canonical: str) -> None:
    assert canonical_marker(printed) == canonical


# ---- focus markers -----------------------------------------------------------


def test_focus_markers_follow_profile_conditions() -> None:
    assert focus_markers("Diabetes, Hypertension") == [
        "HbA1c",
        "Fasting glucose",
        "LDL",
        "Total cholesterol",
    ]
    assert focus_markers("kidney disease") == ["Creatinine"]
    assert focus_markers("Thyroid") == ["TSH"]
    assert focus_markers("Heart disease") == ["LDL", "Total cholesterol", "Triglycerides"]
    assert focus_markers("Asthma") == []
    assert focus_markers(None) == []


# ---- statuses and ranges -------------------------------------------------------


def test_point_status_uses_the_five_percent_warn_band() -> None:
    # Default HbA1c 4.0–6.0: width 2.0, warn band 0.1.
    result = build_risk_trends(_user(), _series("HbA1c {} %", "5.9", "6.1", "6.4"), now=NOW)

    statuses = [point["status"] for point in _trend(result, "HbA1c")["points"]]
    assert statuses == ["ok", "warn", "error"]


def test_report_range_wins_over_default() -> None:
    result = build_risk_trends(
        _user(),
        _series("HbA1c {} % 4.0 - 5.6", "5.9", "5.8"),
        now=NOW,
    )

    trend = _trend(result, "HbA1c")
    assert trend["range"] == {
        "low": 4.0,
        "high": 5.6,
        "label": "Normal range 4.0–5.6 %",
        "source": "report",
    }
    assert [point["status"] for point in trend["points"]] == ["error", "error"]


def test_default_range_label_and_source() -> None:
    result = build_risk_trends(_user(), _series("HbA1c {}", "5.5"), now=NOW)

    trend = _trend(result, "HbA1c")
    assert trend["unit"] == "%"
    assert trend["range"] == {
        "low": 4.0,
        "high": 6.0,
        "label": "Normal range 4.0–6.0 %",
        "source": "default",
    }


@pytest.mark.parametrize(
    ("marker", "sex", "low", "high"),
    [
        ("Haemoglobin", "female", 12.0, 15.5),
        ("Haemoglobin", "male", 13.5, 17.5),
        ("Haemoglobin", None, 13.5, 17.5),
        ("Creatinine", "female", 0.5, 1.1),
        ("Creatinine", "male", 0.6, 1.2),
        ("HDL", "female", 60.0, None),
        ("HDL", "male", 40.0, None),
        ("HDL", "prefer_not_to_say", 40.0, None),
    ],
)
def test_default_ranges_depend_on_sex_at_birth(
    marker: str, sex: str | None, low: float, high: float | None
) -> None:
    result = build_risk_trends(_user(sex), _series(marker + " {}", "1"), now=NOW)

    range_ = _trend(result, marker)["range"]
    assert (range_["low"], range_["high"]) == (low, high)
    assert range_["source"] == "default"


def test_every_contract_default_is_present() -> None:
    assert set(DEFAULT_RANGES) == {
        "HbA1c",
        "Fasting glucose",
        "Total cholesterol",
        "LDL",
        "HDL",
        "Triglycerides",
        "Creatinine",
        "TSH",
        "Haemoglobin",
    }
    assert DEFAULT_RANGES["Fasting glucose"]["general"].high == 99.0
    assert DEFAULT_RANGES["TSH"]["general"].unit == "mIU/L"


def test_hdl_only_flags_low_values() -> None:
    result = build_risk_trends(_user("male"), _series("HDL {} mg/dL", "75", "90"), now=NOW)

    trend = _trend(result, "HDL")
    assert trend["range"]["label"] == "Normal range above 40 mg/dL"
    assert [point["status"] for point in trend["points"]] == ["ok", "ok"]
    assert trend["alert"] is None


def test_unknown_marker_without_a_range_is_listed_but_never_flagged() -> None:
    result = build_risk_trends(_user(), _series("Sodium {} mmol/L", "140", "150", "160"), now=NOW)

    trend = _trend(result, "Sodium")
    assert trend["range"] is None
    assert trend["alert"] is None
    assert [point["status"] for point in trend["points"]] == ["ok", "ok", "ok"]


# ---- alerts ---------------------------------------------------------------------


def test_rising_streak_alert_and_insight() -> None:
    result = build_risk_trends(
        _user("female", "Diabetes"),
        _series("HbA1c {} %", "5.9", "6.1", "6.4"),
        now=NOW,
    )

    trend = _trend(result, "HbA1c")
    assert trend["focus"] is True
    assert trend["direction"] == "rising"
    assert trend["alert"] == {
        "level": "error",
        "code": "rising_streak",
        "title": "Rising 3 times in a row",
        "body": "Three readings up in a row usually means a change worth discussing.",
    }
    assert result["insight"] == {
        "marker": "HbA1c",
        "title": "Your HbA1c has risen across 3 reports",
        "body": "5.9 in January to 6.4 now. Worth raising with your doctor.",
    }
    assert [point["label"] for point in trend["points"]] == ["Jan", "Feb", "Mar"]
    assert trend["points"][0]["date"] == "2026-01-02"


def test_rising_streak_is_a_warning_when_latest_sits_on_the_line() -> None:
    result = build_risk_trends(_user(), _series("HbA1c {} %", "5.5", "5.8", "6.0"), now=NOW)

    alert = _trend(result, "HbA1c")["alert"]
    assert alert["code"] == "rising_streak"
    assert alert["level"] == "warn"


def test_rising_values_that_stay_in_range_do_not_alert() -> None:
    result = build_risk_trends(_user(), _series("HbA1c {} %", "5.0", "5.3", "5.6"), now=NOW)

    trend = _trend(result, "HbA1c")
    assert trend["direction"] == "rising"
    assert trend["alert"] is None


def test_falling_streak_alert() -> None:
    result = build_risk_trends(
        _user("male"),
        _series("Haemoglobin {} g/dL", "14.0", "13.0", "12.0"),
        now=NOW,
    )

    trend = _trend(result, "Haemoglobin")
    assert trend["direction"] == "falling"
    assert trend["alert"]["code"] == "falling_streak"
    assert trend["alert"]["level"] == "error"
    assert result["insight"]["title"] == "Your Haemoglobin has fallen across 3 reports"
    assert result["insight"]["body"] == "14.0 in January to 12.0 now. Worth raising with your doctor."


def test_crossed_high_alert() -> None:
    result = build_risk_trends(_user(), _series("Fasting glucose {} mg/dL", "92", "100"), now=NOW)

    trend = _trend(result, "Fasting glucose")
    assert trend["alert"]["code"] == "crossed_high"
    assert trend["alert"]["level"] == "warn"  # 1 over a width of 29 → within 5 %
    assert result["insight"] == {
        "marker": "Fasting glucose",
        "title": "Your Fasting glucose is now above its normal range",
        "body": "92 in January to 100 now. Worth raising with your doctor.",
    }


def test_crossed_low_alert() -> None:
    result = build_risk_trends(_user("female"), _series("Haemoglobin {} g/dL", "12.4", "11.0"), now=NOW)

    trend = _trend(result, "Haemoglobin")
    assert trend["alert"]["code"] == "crossed_low"
    assert trend["alert"]["level"] == "error"
    assert result["insight"]["title"] == "Your Haemoglobin is now below its normal range"


def test_out_of_range_alert_when_already_outside() -> None:
    result = build_risk_trends(_user(), _series("LDL {} mg/dL", "130", "128"), now=NOW)

    trend = _trend(result, "LDL")
    assert trend["alert"]["code"] == "out_of_range"
    assert trend["alert"]["level"] == "error"
    assert result["insight"] == {
        "marker": "LDL",
        "title": "Your LDL is outside its normal range",
        "body": "LDL is outside its normal range in your latest report.",
    }


def test_latest_warn_without_crossing_is_not_flagged() -> None:
    # Both points just outside: previous was not ok, latest is only a warn.
    result = build_risk_trends(_user(), _series("HbA1c {} %", "6.05", "6.08"), now=NOW)

    assert _trend(result, "HbA1c")["alert"] is None


def test_single_point_markers_never_alert() -> None:
    result = build_risk_trends(
        _user(),
        [_report(1, 3, "HbA1c 9.5 %"), _report(2, 4, "Creatinine 1.0 mg/dL")],
        now=NOW,
    )

    hba1c = _trend(result, "HbA1c")
    assert len(hba1c["points"]) == 1
    assert hba1c["points"][0]["status"] == "error"
    assert hba1c["alert"] is None
    assert hba1c["direction"] == "stable"
    assert result["insight"] is None


# ---- direction ------------------------------------------------------------------


@pytest.mark.parametrize(
    ("values", "direction"),
    [
        (("5.0", "5.5", "5.6"), "rising"),  # vs 2 back: +0.6 > 2 % of 2.0
        (("5.6", "5.5", "5.0"), "falling"),
        (("5.0", "5.9", "5.02"), "stable"),  # +0.02 is under the 0.04 band
        (("5.0", "5.3"), "rising"),  # two points: compare with 1 back
        (("5.0", "5.0"), "stable"),
    ],
)
def test_direction_compares_with_two_points_back(values: tuple[str, ...], direction: str) -> None:
    result = build_risk_trends(_user(), _series("HbA1c {} %", *values), now=NOW)

    assert _trend(result, "HbA1c")["direction"] == direction


# ---- insight selection and envelope -------------------------------------------------


def test_insight_prefers_focus_markers_at_the_same_level() -> None:
    reports = [
        _report(1, 1, "HbA1c 5.9 %\nLDL 95 mg/dL"),
        _report(2, 2, "HbA1c 6.1 %\nLDL 102 mg/dL"),
    ]

    result = build_risk_trends(_user(None, "Hypertension"), reports, now=NOW)

    assert _trend(result, "HbA1c")["alert"]["level"] == "warn"
    assert _trend(result, "LDL")["alert"]["level"] == "warn"
    assert result["insight"]["marker"] == "LDL"
    assert result["focus_markers"] == ["LDL", "Total cholesterol"]
    # Focus markers are listed first.
    assert result["trends"][0]["marker"] == "LDL"


def test_insight_picks_the_highest_level_over_focus() -> None:
    reports = [
        _report(1, 1, "HbA1c 5.9 %\nLDL 95 mg/dL"),
        _report(2, 2, "HbA1c 6.1 %\nLDL 140 mg/dL"),
    ]

    result = build_risk_trends(_user(None, "Diabetes"), reports, now=NOW)

    assert result["insight"]["marker"] == "LDL"


def test_needs_reports_until_two_reports_exist() -> None:
    result = build_risk_trends(_user(), [_report(1, 3, "HbA1c 9.5 %")], now=NOW)

    assert result["reports_count"] == 1
    assert result["needs_reports"] is True
    assert result["insight"] is None
    assert [trend["marker"] for trend in result["trends"]] == ["HbA1c"]

    empty = build_risk_trends(_user(), [], now=NOW)
    assert empty == {
        "reports_count": 0,
        "needs_reports": True,
        "generated_at": "2026-10-25T16:00:00",
        "focus_markers": [],
        "insight": None,
        "trends": [],
    }


def test_reports_are_ordered_by_upload_date_not_input_order() -> None:
    reports = [_report(3, 9, "HbA1c 6.4 %"), _report(1, 3, "HbA1c 5.9 %"), _report(2, 6, "HbA1c 6.1 %")]

    result = build_risk_trends(_user(), reports, now=NOW)

    assert [point["report_id"] for point in _trend(result, "HbA1c")["points"]] == [1, 2, 3]
    assert result["insight"]["body"].startswith("5.9 in March to 6.4 now.")


def test_values_are_echoed_exactly_as_printed() -> None:
    result = build_risk_trends(_user(), _series("HbA1c {} %", "5.90", "6.10", "6.40"), now=NOW)

    assert result["insight"]["body"] == "5.90 in January to 6.40 now. Worth raising with your doctor."
    assert [point["value"] for point in _trend(result, "HbA1c")["points"]] == [5.9, 6.1, 6.4]


def test_result_is_deterministic() -> None:
    reports = _series("HbA1c {} %", "5.9", "6.1", "6.4")

    assert build_risk_trends(_user(), reports, now=NOW) == build_risk_trends(_user(), reports, now=NOW)


def test_panel_title_comes_from_markers_not_the_letterhead() -> None:
    text = (
        "CITY LAB KARACHI\n"
        "Patient: SAMPLE PERSON\n"
        "Phone: 0300-0000000\n"
        "Haemoglobin 14.2 g/dL 12.0 - 16.0\n"
        "Platelets 245 10^9/L 150 - 400\n"
    )
    assert guess_panel_title(text) == "Complete blood count"


def test_lipid_and_hba1c_titles() -> None:
    assert guess_panel_title("LDL 118 mg/dL\nHDL 52 mg/dL\nTriglycerides 140 mg/dL") == "Lipid profile"
    assert guess_panel_title("HbA1c 6.4 % 4.0-6.0") == "Blood sugar test"


def test_partial_parse_explains_coverage_without_failing() -> None:
    text = (
        "Haemoglobin 14.2 g/dL 12.0 - 16.0\n"
        "Platelets 245\n"
        "Something unreadable ###\n"
        "WBC --\n"
        "RBC 4.8 10^12/L 4.0-5.5\n"
    )
    summary = summarise_report(text)
    assert summary["title"] == "Complete blood count"
    assert summary["values_read"] >= 2
    assert summary["values_expected"] > summary["values_read"]
    assert summary["parse_note"] == (
        f"We read {summary['values_read']} of {summary['values_expected']} values"
    )


# Synthetic OCR transcripts covering the panels a Pakistani lab typically
# prints. No names, phones or lab IDs. Tracked so a layout that stops
# parsing is a failing test, not a silent empty report.
_GOLDEN = {
    "cbc_1": ("Haemoglobin 13.8 g/dL 13.5-17.5\nPlatelets 210 10^9/L 150-400\nMCV 88 fL 80-96", "Complete blood count"),
    "cbc_2": ("Hemoglobin 12.1 g/dL 12.0-15.5\nHaematocrit 38 % 36-46\nRBC 4.4 10^12/L 4.0-5.2", "Complete blood count"),
    "cbc_3": ("Hb 14.0 g/dL 13.0-17.0\nPlatelet count 180\nWBC 6.2 10^9/L 4.0-11.0", "Complete blood count"),
    "lipid_1": ("Total cholesterol 198 mg/dL 0-200\nLDL 118 mg/dL 0-100\nHDL 52 mg/dL", "Lipid profile"),
    "lipid_2": ("LDL cholesterol 94 mg/dL\nHDL 61 mg/dL\nTriglycerides 130 mg/dL 0-150", "Lipid profile"),
    "lipid_3": ("Cholesterol 210 mg/dL\nTriglyceride 180 mg/dL\nHDL-C 40 mg/dL", "Lipid profile"),
    "liver_1": ("ALT 32 U/L 0-40\nAST 28 U/L 0-40\nBilirubin 0.8 mg/dL 0.2-1.2", "Liver function test"),
    "liver_2": ("SGPT 44 U/L\nSGOT 38 U/L\nALP 90 U/L 40-129", "Liver function test"),
    "hba1c_1": ("HbA1c 5.6 % 4.0-6.0", "Blood sugar test"),
    "hba1c_2": ("Glycated Haemoglobin 6.4 %", "Blood sugar test"),
    "glucose_1": ("Fasting glucose 92 mg/dL 70-99", "Blood sugar test"),
    "glucose_2": ("Fasting blood sugar 110 mg/dL 70-99", "Blood sugar test"),
    "thyroid_1": ("TSH 2.1 mIU/L 0.4-4.0", "Thyroid test"),
    "urine_1": ("Urine protein Negative\nUrine glucose Negative\nWBC 2 /HPF 0-5", "Urine test"),
    "urine_2": ("Complete urine examination\nRBC 0 /HPF\nEpithelial cells few", "Urine test"),
    "creatinine_1": ("Creatinine 0.9 mg/dL 0.6-1.2", "Lab report"),
}


@pytest.mark.parametrize("name,payload", list(_GOLDEN.items()))
def test_golden_transcripts_parse_and_title(name: str, payload: tuple[str, str]) -> None:
    text, title = payload
    values = parse_lab_values(text)
    assert guess_panel_title(text, values) == title, name
    if name.startswith("urine"):
        return
    assert values, f"{name} produced no values"
