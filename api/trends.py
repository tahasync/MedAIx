"""Rule-based risk and trend detection over a patient's lab reports (Sprint 3).

Two pure, deterministic steps:

1. ``parse_lab_values`` pulls ``marker value [unit] [reference range]`` rows
   out of OCR text with a tolerant regex and canonicalises marker names
   (``"Glycated Hemoglobin"`` → ``"HbA1c"``).
2. ``build_risk_trends`` groups those values per marker across reports, works
   out each point's status against the printed or default range, and applies
   the contract's alert / direction / insight rules.

Numbers are never altered: the ``value`` is the parsed float and the text the
user sees (``raw_value``, range labels) is the string as printed on the report.
No LLM, no network: the same reports always give the same answer.
"""

from __future__ import annotations

import re
from collections.abc import Iterable
from dataclasses import dataclass
from datetime import date, datetime
from typing import Any, Protocol

from models import utc_now

from trend_parsing import (
    PARSER_VERSION,
    ParsedQualitativeValue,
    ParsedValue,
    _MISSING_VALUE,
    _SKIP_CANDIDATE,
    _SYNONYMS,
    _parse_line,
    _parse_qualitative_line,
    canonical_marker,
    extract_report_date,
    parse_lab_values,
    parse_qualitative_lab_values,
)

# ---------------------------------------------------------------------------
# Rules
# ---------------------------------------------------------------------------

STATUS_OK = "ok"
STATUS_WARN = "warn"
STATUS_ERROR = "error"
# Outside the range by at most this share of its width is a warning.
_WARN_BAND = 0.05
# A move of more than this share of the range width counts as a direction.
_DIRECTION_BAND = 0.02

_LEVEL_RANK = {STATUS_WARN: 1, STATUS_ERROR: 2}


@dataclass(frozen=True)
class _Default:
    unit: str
    low: float | None
    high: float | None
    raw_low: str | None
    raw_high: str | None


def _default(unit: str, low: str | None, high: str | None) -> _Default:
    return _Default(
        unit=unit,
        low=float(low) if low is not None else None,
        high=float(high) if high is not None else None,
        raw_low=low,
        raw_high=high,
    )


# Used when the report prints no reference range. "female" entries apply when
# ``sex_at_birth`` is female; everyone else gets the general row.
DEFAULT_RANGES: dict[str, dict[str, _Default]] = {
    "HbA1c": {"general": _default("%", "4.0", "6.0")},
    "Fasting glucose": {"general": _default("mg/dL", "70", "99")},
    "Total cholesterol": {"general": _default("mg/dL", "0", "200")},
    "LDL": {"general": _default("mg/dL", "0", "100")},
    "HDL": {
        "general": _default("mg/dL", "40", None),
        "female": _default("mg/dL", "60", None),
    },
    "Triglycerides": {"general": _default("mg/dL", "0", "150")},
    "Creatinine": {
        "general": _default("mg/dL", "0.6", "1.2"),
        "female": _default("mg/dL", "0.5", "1.1"),
    },
    "TSH": {"general": _default("mIU/L", "0.4", "4.0")},
    "Haemoglobin": {
        "general": _default("g/dL", "13.5", "17.5"),
        "female": _default("g/dL", "12.0", "15.5"),
    },
}

# Profile condition keyword → markers to highlight (contract §2).
_CONDITION_MARKERS: tuple[tuple[str, tuple[str, ...]], ...] = (
    ("diabetes", ("HbA1c", "Fasting glucose")),
    ("hypertension", ("LDL", "Total cholesterol")),
    ("blood pressure", ("LDL", "Total cholesterol")),
    ("kidney", ("Creatinine",)),
    ("thyroid", ("TSH",)),
    ("heart", ("LDL", "Total cholesterol", "Triglycerides")),
)

_ALERT_TEXT = {
    "rising_streak": (
        "Rising 3 times in a row",
        "Three readings up in a row usually means a change worth discussing.",
    ),
    "falling_streak": (
        "Falling 3 times in a row",
        "Three readings down in a row usually means a change worth discussing.",
    ),
    "crossed_high": (
        "Now above the normal range",
        "Your latest reading moved above the normal range. Worth raising with your doctor.",
    ),
    "crossed_low": (
        "Now below the normal range",
        "Your latest reading moved below the normal range. Worth raising with your doctor.",
    ),
    "out_of_range": (
        "Outside the normal range",
        "Your latest reading is outside the normal range. Worth raising with your doctor.",
    ),
}


class _ReportLike(Protocol):
    id: int
    uploaded_at: datetime
    original_text: str | None
    report_date: date | None
    report_date_source: str | None


@dataclass(frozen=True)
class _Observation:
    report_id: int
    at: datetime
    parsed: ParsedValue
    date_source: str


@dataclass(frozen=True)
class _Range:
    low: float | None
    high: float | None
    raw_low: str | None
    raw_high: str | None
    source: str

    def label(self, unit: str | None) -> str:
        suffix = f" {unit}" if unit else ""
        if self.low is not None and self.high is not None:
            return f"Normal range {self.raw_low}–{self.raw_high}{suffix}"
        if self.high is not None:
            return f"Normal range below {self.raw_high}{suffix}"
        return f"Normal range above {self.raw_low}{suffix}"

    def payload(self, unit: str | None) -> dict[str, object]:
        return {
            "low": self.low,
            "high": self.high,
            "raw_low": self.raw_low,
            "raw_high": self.raw_high,
            "label": self.label(unit),
            "source": self.source,
        }


def focus_markers(conditions: str | None) -> list[str]:
    """Markers worth highlighting for the conditions in the profile."""
    text = (conditions or "").lower()
    markers: list[str] = []
    for keyword, marker_names in _CONDITION_MARKERS:
        if keyword in text:
            for marker in marker_names:
                if marker not in markers:
                    markers.append(marker)
    return markers


def _sex_of(user: Any) -> str | None:
    value = getattr(user, "sex_at_birth", None) or getattr(user, "sex", None)
    return value.strip().lower() if isinstance(value, str) else None


# Panel titles come from the detected markers, never the first OCR line
# (that is usually a letterhead or a patient name).
_CBC = ("haemoglobin", "hemoglobin", "platelets?", "wbc", "rbc", "mcv", "mchc", "mch", "haematocrit", "hematocrit")
_LIPID = ("ldl", "hdl", "triglycerides?", "cholesterol")
_LIVER = ("alt", "ast", "sgpt", "sgot", "bilirubin", "alp", "ggt")
def guess_panel_title(text: str, values: list[ParsedValue] | None = None) -> str:
    """A short list title: 'Complete blood count', 'Lipid profile', or 'Lab report'."""
    parsed = values if values is not None else parse_lab_values(text)
    blob = f"{text} {' '.join(v.marker for v in parsed)}".lower()
    hits = lambda words: sum(1 for word in words if re.search(rf"\b{word}\b", blob))
    if hits(_LIPID) >= 2:
        return "Lipid profile"
    if hits(_CBC) >= 2:
        return "Complete blood count"
    if "urine" in blob:
        return "Urine test"
    if "stool" in blob:
        return "Stool test"
    if "thyroid" in blob or re.search(r"\btsh\b", blob):
        return "Thyroid test"
    if "hba1c" in blob or "glycated" in blob:
        return "Blood sugar test"
    if "glucose" in blob or "fasting" in blob:
        return "Blood sugar test"
    if hits(_LIVER) >= 2:
        return "Liver function test"
    if hits(_CBC) == 1:
        return "Blood test"
    return "Lab report"


def _candidate_count(text: str) -> int:
    """Count recognized result rows, including known rows with unreadable values.

    Arbitrary numbers are not candidate lab values: OCR frequently turns
    phone numbers, dates and stray page fragments into numbers.
    """
    count = 0
    for line in text.splitlines():
        if _SKIP_CANDIDATE.search(line):
            continue
        if (
            _parse_line(line) is not None
            or _parse_qualitative_line(line) is not None
            or _is_missing_lab_value(line)
        ):
            count += 1
    return count


def _is_missing_lab_value(line: str) -> bool:
    """Count a recognized result row whose value OCR marked as missing."""
    missing = _MISSING_VALUE.search(line)
    if missing is None:
        return False
    marker = line[: missing.start()].strip(" :;,.-–—=|*#()[]")
    normalized = marker.lower()
    return any(re.search(rf"\b{name}\b", normalized) for name in _CBC) or any(
        pattern.search(marker) for pattern, _ in _SYNONYMS
    )


def summarise_report(text: str, sex: str | None = None) -> dict[str, object]:
    """Title, parse coverage and attention count for one report.

    A partial parse is not a failure: ``parse_note`` tells the patient how
    many rows were recovered so the original photo stays the source of truth.
    """
    values = parse_lab_values(text)
    qualitative_values = parse_qualitative_lab_values(text)
    expected = max(_candidate_count(text), len(values) + len(qualitative_values))
    attention = 0
    for parsed in values:
        range_ = _range_of_parsed(parsed, sex)
        if _status(parsed.value, range_) != STATUS_OK:
            attention += 1
    attention += sum(
        1 for parsed in qualitative_values
        if parsed.reference is not None and parsed.result != parsed.reference
    )
    read = len(values) + len(qualitative_values)
    note = None
    if expected > read:
        note = f"We read {read} of {expected} values"
    return {
        "title": guess_panel_title(text, values),
        "values_read": read,
        "values_expected": expected,
        "attention_count": attention,
        "parse_note": note,
    }


def _range_of_parsed(parsed: ParsedValue, sex: str | None) -> _Range | None:
    if parsed.low is not None or parsed.high is not None:
        return _Range(parsed.low, parsed.high, parsed.raw_low, parsed.raw_high, "report")
    defaults = DEFAULT_RANGES.get(parsed.marker)
    if defaults is None:
        return None
    default = defaults.get(sex or "", defaults["general"])
    return _Range(default.low, default.high, default.raw_low, default.raw_high, "default")


def _resolve_range(marker: str, observations: list[_Observation], sex: str | None) -> _Range | None:
    # The most recent printed range wins: labs revise their references.
    for observation in reversed(observations):
        parsed = observation.parsed
        if parsed.low is not None or parsed.high is not None:
            return _Range(parsed.low, parsed.high, parsed.raw_low, parsed.raw_high, "report")
    defaults = DEFAULT_RANGES.get(marker)
    if defaults is None:
        return None
    default = defaults.get(sex or "", defaults["general"])
    return _Range(default.low, default.high, default.raw_low, default.raw_high, "default")


def _resolve_unit(marker: str, observations: list[_Observation], sex: str | None) -> str | None:
    for observation in reversed(observations):
        if observation.parsed.unit:
            return observation.parsed.unit
    defaults = DEFAULT_RANGES.get(marker)
    if defaults is None:
        return None
    return defaults.get(sex or "", defaults["general"]).unit


def _width(range_: _Range | None, fallback: float) -> float:
    """Range width used for the warn band and direction threshold.

    Open-ended ranges (HDL ``≥ 40``) have no width, so the bound itself is
    used; a marker with no range at all falls back to the latest value.
    """
    if range_ is not None:
        if range_.low is not None and range_.high is not None:
            return abs(range_.high - range_.low) or 1.0
        bound = range_.high if range_.high is not None else range_.low
        return abs(bound or 0.0) or 1.0
    return abs(fallback) or 1.0


def _status(value: float, range_: _Range | None) -> str:
    severity = _severity(value, range_)
    if severity == "normal":
        return STATUS_OK
    if severity in ("slightly_low", "slightly_high"):
        return STATUS_WARN
    return STATUS_ERROR if severity != "unknown" else "neutral"


def _severity(value: float, range_: _Range | None) -> str:
    if range_ is None:
        return "unknown"
    direction = "high" if range_.high is not None and value > range_.high else "low"
    outside = 0.0
    if range_.high is not None and value > range_.high:
        outside = value - range_.high
    elif range_.low is not None and value < range_.low:
        outside = range_.low - value
    else:
        return "normal"
    share = outside / _width(range_, value)
    if share <= _WARN_BAND:
        return f"slightly_{direction}"
    if share > 0.5:
        return "critical"
    return direction


def _direction(values: list[float], width: float) -> str | None:
    if len(values) < 2:
        return None
    back = 2 if len(values) >= 3 else 1
    delta = values[-1] - values[-1 - back]
    if delta > _DIRECTION_BAND * width:
        return "rising"
    if delta < -_DIRECTION_BAND * width:
        return "falling"
    return "stable"


def _alert_code(values: list[float], statuses: list[str], range_: _Range | None) -> str | None:
    if len(values) < 2 or range_ is None:
        return None
    latest, latest_status = values[-1], statuses[-1]
    if len(values) >= 3:
        a, b = values[-3], values[-2]
        if a < b < latest and range_.high is not None and latest >= range_.high:
            return "rising_streak"
        if a > b > latest and range_.low is not None and latest <= range_.low:
            return "falling_streak"
    if statuses[-2] == STATUS_OK and latest_status != STATUS_OK:
        if range_.high is not None and latest > range_.high:
            return "crossed_high"
        return "crossed_low"
    if latest_status == STATUS_ERROR:
        return "out_of_range"
    return None


def _alert(code: str, latest_status: str) -> dict[str, object]:
    title, body = _ALERT_TEXT[code]
    level = STATUS_ERROR if latest_status == STATUS_ERROR else STATUS_WARN
    return {"level": level, "code": code, "title": title, "body": body}


@dataclass
class _Trend:
    marker: str
    focus: bool
    payload: dict[str, object]
    alert: dict[str, object] | None
    first_raw: str
    last_raw: str
    first_month: str
    last_date: str
    points_count: int


def _build_trend(marker: str, observations: list[_Observation], sex: str | None, focus: bool) -> _Trend:
    range_ = _resolve_range(marker, observations, sex)
    unit = _resolve_unit(marker, observations, sex)
    values = [observation.parsed.value for observation in observations]
    statuses = [_status(value, range_) for value in values]
    points = [
        {
            "report_id": observation.report_id,
            "date": observation.at.date().isoformat(),
            "date_source": observation.date_source,
            "label": observation.at.date().isoformat(),
            "value": observation.parsed.value,
            "raw_value": observation.parsed.raw_value,
            "status": status,
            "severity": _severity(observation.parsed.value, range_),
        }
        for observation, status in zip(observations, statuses, strict=True)
    ]
    code = _alert_code(values, statuses, range_)
    alert = _alert(code, statuses[-1]) if code else None
    distinct_dates = {observation.at.date() for observation in observations}
    payload: dict[str, object] = {
        "marker": marker,
        "unit": unit,
        "unit_corrected": any(observation.parsed.unit_corrected for observation in observations),
        "focus": focus,
        "range": range_.payload(unit) if range_ else None,
        "direction": _direction(values, _width(range_, values[-1])) if len(distinct_dates) >= 2 else None,
        "points": points,
        "alert": alert,
    }
    return _Trend(
        marker=marker,
        focus=focus,
        payload=payload,
        alert=alert,
        first_raw=observations[0].parsed.raw_value,
        last_raw=observations[-1].parsed.raw_value,
        first_month=observations[0].at.date().isoformat(),
        last_date=observations[-1].at.date().isoformat(),
        points_count=len(distinct_dates),
    )


def _insight(trends: list[_Trend]) -> dict[str, object] | None:
    flagged = [trend for trend in trends if trend.alert]
    if not flagged:
        return None
    # Highest level first, then focus markers, then the trend order.
    chosen = max(
        enumerate(flagged),
        key=lambda pair: (_LEVEL_RANK[str(pair[1].alert["level"])], pair[1].focus, -pair[0]),
    )[1]
    code = str(chosen.alert["code"])
    marker = chosen.marker
    if code in ("rising_streak", "falling_streak"):
        verb = "risen" if code == "rising_streak" else "fallen"
        title = f"Your {marker} has {verb} across {chosen.points_count} reports"
    elif code == "crossed_high":
        title = f"Your {marker} is now above its normal range"
    elif code == "crossed_low":
        title = f"Your {marker} is now below its normal range"
    else:
        title = f"Your {marker} is outside its normal range"
    if code == "out_of_range":
        latest = chosen.payload["points"][-1]
        day_value = datetime.fromisoformat(str(latest["date"]))
        day = f"{day_value.day} {day_value:%b}"
        range_payload = chosen.payload.get("range") or {}
        low, high = range_payload.get("raw_low"), range_payload.get("raw_high")
        unit = chosen.payload.get("unit") or ""
        if low is not None and high is not None:
            body = f"{latest.get('raw_value', latest['value'])} {unit} on {day}. Your report's range is {low}–{high}. Worth raising with your doctor."
        else:
            body = f"{latest['value']} {unit} on {day}. This is outside your report's stated range. Worth raising with your doctor."
    else:
        body = (
            f"{chosen.first_raw} on {chosen.first_month} to {chosen.last_raw} "
            f"on {chosen.last_date}. "
            "Worth raising with your doctor."
        )
    return {"marker": marker, "title": title, "body": body}


def build_risk_trends(
    user: Any,
    reports: Iterable[_ReportLike],
    *,
    now: datetime | None = None,
) -> dict[str, object]:
    """Trend and alert summary for ``reports`` (any object with ``id``,
    ``uploaded_at`` and ``original_text``), following contract §2.

    ``user`` supplies ``sex_at_birth`` (default ranges) and ``conditions``
    (focus markers). ``now`` pins ``generated_at`` in tests.
    """
    def report_date_for(report: _ReportLike) -> date | datetime | None:
        report_date = getattr(report, "report_date", None)
        if getattr(report, "report_date_source", None) == "report" and report_date:
            return report_date
        # Existing report rows may predate the current date parser. Recover
        # the date from their saved OCR text so Trends is correct immediately;
        # /reports also re-stamps those rows under the bumped parser version.
        return extract_report_date(report.original_text)

    def effective_date(report: _ReportLike) -> datetime:
        report_date = report_date_for(report)
        if report_date is None:
            return report.uploaded_at
        if isinstance(report_date, datetime):
            return report_date
        return datetime.combine(
            report_date,
            datetime.min.time(),
            tzinfo=report.uploaded_at.tzinfo,
        )

    ordered = sorted(reports, key=lambda report: (effective_date(report), report.uploaded_at, report.id))
    sex = _sex_of(user)
    focus = focus_markers(getattr(user, "conditions", None))

    series: dict[str, list[_Observation]] = {}
    for report in ordered:
        seen: set[str] = set()
        for parsed in parse_lab_values(report.original_text):
            if parsed.marker in seen:
                continue  # first row of a marker on a report wins
            seen.add(parsed.marker)
            series.setdefault(parsed.marker, []).append(
                _Observation(
                    report.id,
                    effective_date(report),
                    parsed,
                    "report" if report_date_for(report) is not None else "upload",
                )
            )

    # Identical values on the same effective date are duplicate observations,
    # even if they came from separate uploaded copies of one report.
    for marker, observations in series.items():
        unique: list[_Observation] = []
        seen: set[tuple[date, float]] = set()
        for observation in observations:
            key = (observation.at.date(), observation.parsed.value)
            if key not in seen:
                seen.add(key)
                unique.append(observation)
        series[marker] = unique

    trends = [
        _build_trend(marker, observations, sex, marker in focus)
        for marker, observations in series.items()
    ]
    trends.sort(key=lambda trend: not trend.focus)  # stable: keeps first-seen order

    reports_count = len(ordered)
    needs_reports = reports_count < 2
    return {
        "reports_count": reports_count,
        "needs_reports": needs_reports,
        "generated_at": (now or utc_now()).isoformat(),
        "focus_markers": focus,
        "insight": None if needs_reports else _insight(trends),
        "trends": [trend.payload for trend in trends],
    }
