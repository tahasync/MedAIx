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
        (r"\bt(?:otal)?\.?\s*cholesterol\s*/\s*hdl(?:\s+cholesterol)?", "Total cholesterol/HDL ratio"),
        (r"\bldl\s*/\s*hdl(?:\s+cholesterol)?", "LDL/HDL ratio"),
        (r"\bvldl(?:\s*-?\s*cholesterol)?\b", "VLDL"),
        (r"\balbumin\s*/\s*creatinine\s+ratio\b", "Albumin/creatinine ratio"),
        (r"\brisk\s*ii\b", "Risk II"),
        (r"\brisk\s*i\b", "Risk I"),
        (r"\bldl", "LDL"),
        (r"\bhdl", "HDL"),
        (r"\b(?:c-?reactive\s+protein|crp)(?:\s+.*)?", "CRP"),
        (r"\balpha\s+feto(?:protein)?|\bafp\b", "Alpha Feto Protein"),
        (r"\bck\s*(?:\(\s*total\s*\)|total)|\bcpk\b", "CK Total"),
        (r"\bcalprotectin\b", "Calprotectin"),
        (r"\bferritin\s+in\s+serum\b", "Ferritin"),
        (r"\bantistreptolysin\s*[- ]?o|\basot\b", "ASOT"),
        (r"\buric\s+acid|\burate\b", "Uric Acid"),
        (r"triglycerides?|\btg\b", "Triglycerides"),
        (r"prostatic\s+specific\s+antigen|prostate[- ]specific\s+antigen|\btotal\s+psa\b|\bpsa\b", "PSA"),
        (r"25[- ]?hydroxyvitamin\s*d3?\b|25[- ]?oh\s*vitamin\s*d3?\b|\bvitamin\s*d3?\b", "Vitamin D"),
        (r"cholesterol", "Total cholesterol"),
        (r"creatinine", "Creatinine"),
        (r"\btsh\b|thyroid[\s-]*stimulating[\s-]*hormone", "TSH"),
        (r"ha?emoglobin|\bhb\b|\bhgb\b", "Haemoglobin"),
    )
)

# A number that is not glued to letters, so the "1" in "HbA1c" or "B12" is
# skipped. An optional "<"/">" prefix is kept as part of the printed value.
_NUMBER = re.compile(
    r"(?<![A-Za-z0-9.])(?:[<>]\s*)?(\d+(?:\.\d+)?)(?![A-Za-z0-9]|\s*[-–]\s*[A-Za-z]|\s*\(\s*(?:oh|hydroxy)\b|\s+hydroxyvitamin\b|\s+oh\b)",
    re.IGNORECASE,
)
_VALUE_AT_LINE_START = re.compile(r"^\s*(?:[<>]\s*)?\d+(?:\.\d+)?\b")
_VALUE_NEAR_LINE_START = re.compile(r"^\s*(?:[A-Za-z]{1,3}[\s:|]*){0,4}(?:[<>]\s*)?\d+(?:\.\d+)?\b")
_RESULT_UNIT_TOKEN = re.compile(
    r"%|(?<![A-Za-z0-9])(?:[A-Za-zµμ]+|x?10(?:[*^]\d+)?)/[A-Za-zµμ0-9.*^]+",
    re.IGNORECASE,
)
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
    "phone", "printed", "received", "ref", "reg", "report", "reported", "result",
    "sample", "sex", "sno", "specimen", "sr", "tel", "time", "visit",
    "registered", "name", "age/sex", "collected", "call", "comments",
    "comment", "quantitative", "increased", "moderately", "severely",
}  # fmt: skip


def canonical_marker(name: str) -> str:
    """Map a printed test name to its canonical marker, else title-case it."""
    for pattern, canonical in _SYNONYMS:
        if pattern.search(name):
            return canonical
    return _title_case(name)


_REPORT_DATE_LABELS = (
    re.compile(
        r"\b(?:collection|collected|sampling|sampled|specimen|sample|test|exam(?:ination)?)\s*date\b|"
        r"\bdate\s+of\s+(?:collection|sampling|sample|specimen|test|exam(?:ination)?)\b|"
        r"\b(?:collected|sampled)\b",
        re.IGNORECASE,
    ),
    re.compile(
        r"\b(?:report|result|issued|printed)\s*date\b|"
        r"\bdate\s+of\s+(?:report|result|issue)\b",
        re.IGNORECASE,
    ),
    re.compile(r"^\s*date\s*[:=#-]", re.IGNORECASE),
)
_MONTH_DATE = re.compile(
    r"\b(?:Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|"
    r"Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:tember)?|Oct(?:ober)?|"
    r"Nov(?:ember)?|Dec(?:ember)?)\s+\d{1,2}(?:,)?\s+(?:19|20)\d{2}\b|"
    r"\b\d{1,2}\s+(?:Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|"
    r"Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:tember)?|Oct(?:ober)?|"
    r"Nov(?:ember)?|Dec(?:ember)?)\s+(?:19|20)\d{2}\b",
    re.IGNORECASE,
)
_NUMERIC_DATE = re.compile(
    r"(?<!\d)(?:(?:19|20)\d{2}[-/.]\d{1,2}[-/.]\d{1,2}|"
    r"\d{1,2}[-/]\d{1,2}[-/](?:19|20)\d{2})(?!\d)"
)


def _parse_report_date_token(token: str) -> date | None:
    """Parse only unambiguous, four-digit-year dates from a labelled field."""
    token = " ".join(token.strip().replace(",", " ").split())
    if re.fullmatch(r"(?:19|20)\d{2}-\d{1,2}-\d{1,2}", token):
        try:
            return date.fromisoformat(token)
        except ValueError:
            return None

    numeric = re.fullmatch(r"(\d{1,2})[-/](\d{1,2})[-/]((?:19|20)\d{2})", token)
    if numeric:
        first, second, year = (int(value) for value in numeric.groups())
        if first > 12 and second <= 12:
            day, month = first, second
        elif second > 12 and first <= 12:
            month, day = first, second
        else:
            # 03/04/2026 could mean either 3 April or March 4. Do not guess.
            return None
        try:
            return date(int(year), month, day)
        except ValueError:
            return None

    for pattern in ("%B %d %Y", "%b %d %Y", "%d %B %Y", "%d %b %Y"):
        try:
            return datetime.strptime(token, pattern).date()
        except ValueError:
            continue
    return None


def extract_report_date(text: str | None) -> date | None:
    """Return a report date only when OCR places it beside a date label.

    Unlabelled dates, dates of birth, and ambiguous numeric dates are ignored;
    a bad date is worse than showing the upload date with its source disclosed.
    """
    if not text:
        return None
    candidates: list[tuple[int, date]] = []
    for line in text.splitlines():
        if re.search(r"\b(?:dob|date\s+of\s+birth|birth\s+date)\b", line, re.I):
            continue
        for priority, label_pattern in enumerate(_REPORT_DATE_LABELS):
            label = label_pattern.search(line)
            if label is None:
                continue
            remainder = line[label.end():]
            token_match = _NUMERIC_DATE.search(remainder) or _MONTH_DATE.search(remainder)
            if token_match is None:
                break
            parsed = _parse_report_date_token(token_match.group(0))
            if parsed is not None:
                candidates.append((priority, parsed))
            break
    return min(candidates, key=lambda item: item[0])[1] if candidates else None


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
    if _SKIP_CANDIDATE.search(line):
        return None
    cleaned = _TIME.sub(" ", _DATE.sub(" ", line.replace("|", " ").replace("\t", " ")))
    cleaned = " ".join(cleaned.split())
    matches = list(_NUMBER.finditer(cleaned))
    match = matches[0] if matches else None
    if not match:
        return None

    # If OCR inserts a stray digit/flag before a result, prefer the last
    # number before the first result unit (e.g. ``LDL 5 151 H mg/dL``).
    first_unit = _RESULT_UNIT_TOKEN.search(cleaned, match.end())
    if first_unit is not None:
        before_unit = [candidate for candidate in matches if candidate.end() <= first_unit.start()]
        if before_unit:
            match = before_unit[-1]

    name = _EDGE_PUNCT.sub("", cleaned[: match.start()])
    letters = re.sub(r"[^A-Za-z]", "", name)
    words = re.findall(r"[A-Za-z]+", name)
    if len(letters) < 2:
        return None
    # Unknown analytes are allowed, but OCR headers and whole report titles
    # must not become chart markers. Known canonical markers bypass this cap.
    if not any(pattern.search(name) for pattern, _ in _SYNONYMS) and (
        len(name) > 36 or len(words) > 5 or any(len(word) > 16 for word in words)
    ):
        return None
    first_word = re.sub(r"[^a-z]", "", name.split()[0].lower())
    if first_word in _NOISE_FIRST_WORDS:
        return None

    raw_value = "".join(match.group(0).split())
    value = float(match.group(1))
    unit, rest = _unit_and_rest(cleaned[match.end() :])
    low, high, raw_low, raw_high = _reference_range(rest)
    known_marker = any(pattern.search(name) for pattern, _ in _SYNONYMS) or bool(
        re.search(
            r"\b(?:wbc|rbc|mcv|mch|mchc|rdw|sodium|potassium|calcium|"
            r"urea|albumin|protein|crp|ferritin|vitamin\s*d|vitamin\s*b12|"
            r"alt|ast|sgpt|sgot|bilirubin|alp|ggt)\b",
            name,
            re.IGNORECASE,
        )
    )
    # OCR often places phone fragments, ages, or page numbers on otherwise
    # unreadable lines. Unknown markers are useful only when the row has a
    # unit or a printed reference range to support that it is a lab result.
    if not known_marker and unit is None and low is None and high is None:
        return None
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
    lines = text.splitlines()
    values: list[ParsedValue] = []
    for index, line in enumerate(lines):
        parsed = _parse_line(line)
        if (
            parsed is None
            and index + 1 < len(lines)
            and not _MISSING_VALUE.search(line)
            and _looks_like_analyte_name(line)
            and _VALUE_NEAR_LINE_START.search(lines[index + 1])
        ):
            # Tesseract sometimes puts a long test name and its value on
            # separate visual rows (for example, 25-OH Vitamin D reports).
            # Join only a recognized analyte line to a following value-first
            # line; never bridge arbitrary lines or infer a value.
            parsed = _parse_line(f"{line} {lines[index + 1]}")
        if parsed is not None:
            values.append(parsed)
    return values


def _looks_like_analyte_name(line: str) -> bool:
    if _SKIP_CANDIDATE.search(line):
        return False
    letters = re.sub(r"[^A-Za-z]", "", line)
    if len(letters) < 2 or len(line) > 64:
        return False
    known = any(pattern.search(line) for pattern, _ in _SYNONYMS)
    known = known or bool(
        re.search(
            r"\b(?:wbc|rbc|mcv|mch|mchc|rdw|sodium|potassium|calcium|"
            r"urea|albumin|protein|crp|ferritin|alt|ast|sgpt|sgot|bilirubin|"
            r"alp|ggt)\b",
            line,
            re.IGNORECASE,
        )
    )
    return known


@dataclass(frozen=True)
class ParsedQualitativeValue:
    """A qualitative lab outcome kept separate from numeric trend values."""

    marker: str
    result: str


_QUALITATIVE_RESULT = re.compile(
    r"(?<!\w)(?P<result>normal\s+trace|slightly\s+turbid|not\s+detected|not\s+found|not\s+seen|none\s+found|"
    r"no\s+mutation|non[- ]?reactive|negative|positive|reactive|detected|"
    r"present|absent|abnormal|normal|trace|nil|no\s+growth|no\s+organisms|"
    r"no\s+ova|no\s+cysts|no\s+parasites|turbid|clear|yellow|straw|amber|some|few|rare)(?!\w)",
    re.IGNORECASE,
)
_ABO_GROUP_RESULT = re.compile(
    r"\bABO\s+(?:GROUP|GROUPING)\b.*\b(?P<result>AB|A|B|O)\s*$",
    re.IGNORECASE,
)


def _parse_qualitative_line(line: str) -> ParsedQualitativeValue | None:
    """Read a short ``test name + qualitative result`` row without guessing.

    This is deliberately separate from numeric values: qualitative outcomes
    must never enter numeric trends or reference-range comparisons.
    """
    if _SKIP_CANDIDATE.search(line):
        return None
    cleaned = _TIME.sub(" ", _DATE.sub(" ", line.replace("|", " ").replace("\t", " ")))
    cleaned = " ".join(cleaned.split())
    abo_match = _ABO_GROUP_RESULT.search(cleaned)
    match = abo_match or _QUALITATIVE_RESULT.search(cleaned)
    if match is None:
        return None
    name_end = match.start("result") if abo_match is not None else match.start()
    name = _EDGE_PUNCT.sub("", cleaned[:name_end]).strip()
    words = re.findall(r"[A-Za-z]+", name)
    if len(re.sub(r"[^A-Za-z]", "", name)) < 2:
        return None
    if len(name) > 64 or len(words) > 9:
        return None
    first_word = re.sub(r"[^a-z]", "", name.split()[0].lower())
    if first_word in _NOISE_FIRST_WORDS:
        return None
    return ParsedQualitativeValue(
        marker=canonical_marker(name),
        result=" ".join(match.group("result").lower().split()),
    )


def parse_qualitative_lab_values(text: str | None) -> list[ParsedQualitativeValue]:
    """Extract explicit qualitative outcomes while excluding narrative text."""
    if not text:
        return []
    values = []
    for line in text.splitlines():
        # Numeric parsing takes precedence so a reference range containing a
        # word such as "negative" cannot duplicate an already-read row.
        if _parse_line(line) is None:
            parsed = _parse_qualitative_line(line)
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
    r"patient|phone|mrn|\blab\s*id\b|\bage\b|\bsex\b|\bdate\b|\bpage\b|"
    r"\bresult\b|\bvisit\b|\bregistered\b|\bname\b|\bcollected\b|"
    r"\bcall\s*center\b|\btelephone\b|\bcontact\s*(?:no|number)\b",
    re.IGNORECASE,
)
_MISSING_VALUE = re.compile(r"(?:--+|—+|…+|\.{3,}|n/?a)\s*$", re.IGNORECASE)


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
    return any(name in normalized for name in _CBC) or any(
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
    if range_ is None:
        return "neutral"
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
        first_month=observations[0].at.date().isoformat(),
        last_date=observations[-1].at.date().isoformat(),
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
    def effective_date(report: _ReportLike) -> datetime:
        report_date = getattr(report, "report_date", None)
        if getattr(report, "report_date_source", None) == "report" and report_date:
            if isinstance(report_date, datetime):
                return report_date
            return datetime.combine(report_date, datetime.min.time(), tzinfo=report.uploaded_at.tzinfo)
        return report.uploaded_at

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
                    "report" if getattr(report, "report_date_source", None) == "report" and getattr(report, "report_date", None) else "upload",
                )
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
