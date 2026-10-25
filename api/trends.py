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
from datetime import datetime
from typing import Any, Protocol

from models import utc_now

# ---------------------------------------------------------------------------
# Parsing
# ---------------------------------------------------------------------------

MONTH_ABBR = (
    "Jan", "Feb", "Mar", "Apr", "May", "Jun",
    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
)  # fmt: skip
MONTH_NAMES = (
    "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December",
)  # fmt: skip


@dataclass(frozen=True)
class ParsedValue:
    marker: str
    value: float
    unit: str | None
    low: float | None
    high: float | None
    raw_value: str
    # The range bounds exactly as printed, for labels ("4.0–6.0" not "4-6").
    raw_low: str | None = None
    raw_high: str | None = None


# Ordered: the first pattern that matches the marker text wins, so the more
# specific names (HbA1c before Haemoglobin, LDL/HDL before cholesterol) go first.
_SYNONYMS: tuple[tuple[re.Pattern[str], str], ...] = tuple(
    (re.compile(pattern, re.IGNORECASE), canonical)
    for pattern, canonical in (
        (r"hb\s*a1c|glyc(?:at|osylat)ed\s+ha?emoglobin|\ba1c\b", "HbA1c"),
        (
            r"fasting\s+(?:blood\s+|plasma\s+)?(?:sugar|glucose)"
            r"|(?:blood\s+|plasma\s+)?(?:glucose|sugar)\s*[,(\-–]*\s*fasting"
            r"|\bfbs\b|\bfpg\b|\bfbg\b",
            "Fasting glucose",
        ),
        (r"\bldl", "LDL"),
        (r"\bhdl", "HDL"),
        (r"triglycerides?|\btg\b", "Triglycerides"),
        (r"cholesterol", "Total cholesterol"),
        (r"creatinine", "Creatinine"),
        (r"\btsh\b|thyroid[\s-]*stimulating[\s-]*hormone", "TSH"),
        (r"ha?emoglobin|\bhb\b|\bhgb\b", "Haemoglobin"),
    )
)

# A number that is not glued to letters, so the "1" in "HbA1c" or "B12" is
# skipped. An optional "<"/">" prefix is kept as part of the printed value.
_NUMBER = re.compile(r"(?<![A-Za-z0-9.])(?:[<>]\s*)?(\d+(?:\.\d+)?)(?![A-Za-z0-9])")
# Dates and clock times are OCR noise for our purposes; strip them first so
# "02/03/2026" never becomes a value of 2. The three-part date needs the same
# separator twice, so a range such as "4.0-6.0" is left alone.
_DATE = re.compile(r"\b\d{1,2}([/-])\d{1,2}\1\d{2,4}\b|\b\d{4}-\d{2}-\d{2}\b")
_TIME = re.compile(r"\b\d{1,2}:\d{2}(?::\d{2})?\s*(?:am|pm)?\b", re.IGNORECASE)
_EDGE_PUNCT = re.compile(r"^[\s:;,.\-–—=|*#()\[\]]+|[\s:;,.\-–—=|*#]+$")
_RANGE_PAIR = re.compile(r"(\d+(?:\.\d+)?)\s*(?:-|–|—|to)\s*(\d+(?:\.\d+)?)", re.IGNORECASE)
_RANGE_BELOW = re.compile(
    r"(?:<=|≤|<|less than|below|up\s*to|upto)\s*(\d+(?:\.\d+)?)", re.IGNORECASE
)
_RANGE_ABOVE = re.compile(r"(?:>=|≥|>|more than|above)\s*(\d+(?:\.\d+)?)", re.IGNORECASE)
_UNIT = re.compile(
    r"^\s*(?P<unit>%|x?10[*^]\d+/[A-Za-zµμ]+|[A-Za-zµμ][A-Za-zµμ0-9*^.]*(?:/[A-Za-zµμ0-9.*^]+)+|[A-Za-zµμ]+)"
)
# Unit words without a "/" or "%" that still count as units.
_BARE_UNITS = {"fl", "pg", "mmhg", "sec", "min", "mm", "ratio", "index", "iu", "u"}
# Header / administrative lines whose first word gives them away.
_NOISE_FIRST_WORDS = {
    "accession", "age", "bill", "collected", "contact", "date", "dob", "fax",
    "gender", "id", "invoice", "lab", "mobile", "mrn", "no", "page", "patient",
    "phone", "printed", "received", "ref", "reg", "report", "reported",
    "sample", "sex", "sno", "specimen", "sr", "tel", "time",
}  # fmt: skip


def canonical_marker(name: str) -> str:
    """Map a printed test name to its canonical marker, else title-case it."""
    for pattern, canonical in _SYNONYMS:
        if pattern.search(name):
            return canonical
    return _title_case(name)


def _title_case(name: str) -> str:
    words = []
    for word in name.split():
        # Keep short all-caps tokens as acronyms (WBC, RBC, MCV, B12).
        if word.isupper() and len(word) <= 5:
            words.append(word)
        else:
            words.append(word[:1].upper() + word[1:].lower())
    return " ".join(words)


def _unit_and_rest(rest: str) -> tuple[str | None, str]:
    match = _UNIT.match(rest)
    if not match:
        return None, rest
    unit = match.group("unit").rstrip(".")
    if "/" in unit or "%" in unit or unit.lower() in _BARE_UNITS:
        return unit, rest[match.end() :]
    return None, rest


def _reference_range(
    rest: str,
) -> tuple[float | None, float | None, str | None, str | None]:
    pair = _RANGE_PAIR.search(rest)
    if pair:
        return float(pair.group(1)), float(pair.group(2)), pair.group(1), pair.group(2)
    below = _RANGE_BELOW.search(rest)
    if below:
        return None, float(below.group(1)), None, below.group(1)
    above = _RANGE_ABOVE.search(rest)
    if above:
        return float(above.group(1)), None, above.group(1), None
    return None, None, None, None


def _parse_line(line: str) -> ParsedValue | None:
    cleaned = _TIME.sub(" ", _DATE.sub(" ", line.replace("|", " ").replace("\t", " ")))
    cleaned = " ".join(cleaned.split())
    match = _NUMBER.search(cleaned)
    if not match:
        return None

    name = _EDGE_PUNCT.sub("", cleaned[: match.start()])
    if len(re.sub(r"[^A-Za-z]", "", name)) < 2:
        return None
    first_word = re.sub(r"[^a-z]", "", name.split()[0].lower())
    if first_word in _NOISE_FIRST_WORDS:
        return None

    raw_value = "".join(match.group(0).split())
    value = float(match.group(1))
    unit, rest = _unit_and_rest(cleaned[match.end() :])
    low, high, raw_low, raw_high = _reference_range(rest)
    return ParsedValue(
        marker=canonical_marker(name),
        value=value,
        unit=unit,
        low=low,
        high=high,
        raw_value=raw_value,
        raw_low=raw_low,
        raw_high=raw_high,
    )


def parse_lab_values(text: str | None) -> list[ParsedValue]:
    """Extract ``marker value [unit] [range]`` rows from OCR text.

    Lines without a standalone number are ignored, as are obvious header rows
    (dates, patient details). Tolerant by design: OCR output is messy and a
    missed line costs less than a wrong number, so nothing is ever inferred.
    """
    if not text:
        return []
    values: list[ParsedValue] = []
    for line in text.splitlines():
        parsed = _parse_line(line)
        if parsed is not None:
            values.append(parsed)
    return values


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


@dataclass(frozen=True)
class _Observation:
    report_id: int
    at: datetime
    parsed: ParsedValue


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
_CBC = ("haemoglobin", "hemoglobin", "platelet", "wbc", "rbc", "mcv", "mchc", "mch", "haematocrit", "hematocrit")
_LIPID = ("ldl", "hdl", "triglycerid", "cholesterol")
_LIVER = ("alt", "ast", "sgpt", "sgot", "bilirubin", "alp", "ggt")
_SKIP_CANDIDATE = re.compile(
    r"patient|phone|mrn|\blab\s*id\b|\bage\b|\bsex\b|\bdate\b|\bpage\b",
    re.IGNORECASE,
)


def guess_panel_title(text: str, values: list[ParsedValue] | None = None) -> str:
    """A short list title: 'Complete blood count', 'Lipid profile', or 'Lab report'."""
    parsed = values if values is not None else parse_lab_values(text)
    blob = f"{text} {' '.join(v.marker for v in parsed)}".lower()
    hits = lambda words: sum(1 for word in words if word in blob)
    if hits(_LIPID) >= 2:
        return "Lipid profile"
    if hits(_CBC) >= 2:
        return "Complete blood count"
    if hits(_LIVER) >= 2:
        return "Liver function test"
    if "urine" in blob:
        return "Urine test"
    if "hba1c" in blob or "glycated" in blob:
        return "Blood sugar test"
    if "glucose" in blob or "fasting" in blob:
        return "Blood sugar test"
    if "tsh" in blob or "thyroid" in blob:
        return "Thyroid test"
    if hits(_CBC) == 1:
        return "Blood test"
    return "Lab report"


def _candidate_count(text: str) -> int:
    """How many lines look like a lab row, including ones the parser missed."""
    count = 0
    for line in text.splitlines():
        if _SKIP_CANDIDATE.search(line):
            continue
        cleaned = _TIME.sub(" ", _DATE.sub(" ", line))
        if _NUMBER.search(cleaned):
            count += 1
    return count


def summarise_report(text: str, sex: str | None = None) -> dict[str, object]:
    """Title, parse coverage and attention count for one report.

    A partial parse is not a failure: ``parse_note`` tells the patient how
    many rows were recovered so the original photo stays the source of truth.
    """
    values = parse_lab_values(text)
    expected = max(_candidate_count(text), len(values))
    attention = 0
    for parsed in values:
        range_ = _range_of_parsed(parsed, sex)
        if _status(parsed.value, range_) != STATUS_OK:
            attention += 1
    read = len(values)
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
    if range_ is None:
        return STATUS_OK
    outside = 0.0
    if range_.high is not None and value > range_.high:
        outside = value - range_.high
    elif range_.low is not None and value < range_.low:
        outside = range_.low - value
    if outside == 0.0:
        return STATUS_OK
    return STATUS_WARN if outside <= _WARN_BAND * _width(range_, value) else STATUS_ERROR


def _direction(values: list[float], width: float) -> str:
    if len(values) < 2:
        return "stable"
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
            "label": MONTH_ABBR[observation.at.month - 1],
            "value": observation.parsed.value,
            "status": status,
        }
        for observation, status in zip(observations, statuses, strict=True)
    ]
    code = _alert_code(values, statuses, range_)
    alert = _alert(code, statuses[-1]) if code else None
    payload: dict[str, object] = {
        "marker": marker,
        "unit": unit,
        "focus": focus,
        "range": range_.payload(unit) if range_ else None,
        "direction": _direction(values, _width(range_, values[-1])),
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
        first_month=MONTH_NAMES[observations[0].at.month - 1],
        points_count=len(observations),
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
        body = f"{marker} is outside its normal range in your latest report."
    else:
        body = (
            f"{chosen.first_raw} in {chosen.first_month} to {chosen.last_raw} now. "
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
    ordered = sorted(reports, key=lambda report: (report.uploaded_at, report.id))
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
                _Observation(report.id, report.uploaded_at, parsed)
            )

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
