"""OCR parsing primitives for lab markers, dates, ranges and qualitative values."""

from __future__ import annotations

import re
from dataclasses import dataclass
from datetime import date, datetime

# ---------------------------------------------------------------------------
# Parsing
# ---------------------------------------------------------------------------

MONTH_ABBR = (
    "Jan", "Feb", "Mar", "Apr", "May", "Jun",
    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
)  # fmt: skip
PARSER_VERSION = 3
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
    unit_corrected: bool = False


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
_SKIP_CANDIDATE = re.compile(
    r"patient|phone|mrn|\blab\s*id\b|\bage\b|\bsex\b|\bdate\b|\bpage\b|"
    r"\bresult\b|\bvisit\b|\bregistered\b|\bname\b|\bcollected\b|"
    r"\bcall\s*center\b|\btelephone\b|\bcontact\s*(?:no|number)\b",
    re.IGNORECASE,
)
_MISSING_VALUE = re.compile(r"(?:--+|—+|…+|\.{3,}|n/?a)\s*$", re.IGNORECASE)


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
    r"Nov(?:ember)?|Dec(?:ember)?)\s+(?:19|20)\d{2}\b|"
    r"\b\d{1,2}[- ](?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*[- ]\d{2}\b",
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

    two_digit = re.fullmatch(r"(\d{1,2})[- ]([A-Za-z]{3,9})[- ](\d{2})", token)
    if two_digit:
        day, month_name, year = two_digit.groups()
        year_num = int(year)
        year_num += 2000 if year_num <= 69 else 1900
        try:
            return datetime.strptime(f"{day} {month_name} {year_num}", "%d %b %Y").date()
        except ValueError:
            try:
                return datetime.strptime(f"{day} {month_name} {year_num}", "%d %B %Y").date()
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
    lines = text.splitlines()
    for index, line in enumerate(lines):
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

        # Some lab layouts put the date under a standalone RESULT heading
        # instead of printing "Result date". OCR can also split the heading,
        # an unreadable numeric artifact, and the printed date across lines.
        if re.match(r"^\s*results?\b", line, re.IGNORECASE):
            for nearby in lines[index : index + 3]:
                token_match = _MONTH_DATE.search(nearby)
                if token_match is None:
                    continue
                parsed = _parse_report_date_token(token_match.group(0))
                if parsed is not None:
                    candidates.append((1, parsed))
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
    # Tesseract can read the report's up/down arrows as a trailing ``1`` or
    # ``t`` and attach that artifact to the unit token (``g/dl1``, ``/uLt``).
    if unit.lower().endswith("/dl1") or unit.lower().endswith("/ult"):
        unit = unit[:-1]
    if "/" in unit or "%" in unit or unit.lower() in _BARE_UNITS:
        return unit, rest[match.end() :]
    return None, rest


_CANONICAL_UNITS: dict[str, dict[str, str]] = {
    "Haemoglobin": {"g/dl": "g/dL"}, "Haematocrit": {"%": "%"},
    "Hematocrit": {"%": "%"}, "WBC": {}, "WBC (TLC)": {}, "RBC": {}, "Total RBC": {}, "Platelets": {},
    "MCV": {"fl": "fL"}, "MCH": {"pg": "pg", "%": "pg"},
    "MCHC": {"g/dl": "g/dL", "%": "g/dL"},
    "LDL": {"mg/dl": "mg/dL"}, "HDL": {"mg/dl": "mg/dL"},
    "Total cholesterol": {"mg/dl": "mg/dL"}, "Triglycerides": {"mg/dl": "mg/dL"},
    "Fasting glucose": {"mg/dl": "mg/dL", "mmol/l": "mmol/L"},
    "HbA1c": {"%": "%"},
}


def _canonical_unit(marker: str, unit: str | None) -> tuple[str | None, bool]:
    if unit is None or marker not in _CANONICAL_UNITS:
        return unit, False
    normalized = unit.strip().replace("μ", "µ").replace("Μ", "µ")
    compact = normalized.casefold().replace(" ", "")
    if marker in ("WBC", "WBC (TLC)", "Platelets") and (
        re.fullmatch(r"x?10(?:\^|\*)?3/(?:u|µ)l", compact)
        or re.fullmatch(r"10(?:\^|\*)?9/l", compact)
        or compact == "10⁹/l"
    ):
        return "×10³/µL", normalized != "×10³/µL"
    if marker in ("RBC", "Total RBC") and (
        re.fullmatch(r"x?10(?:\^|\*)?6/(?:u|µ)l", compact)
        or re.fullmatch(r"10(?:\^|\*)?12/l", compact)
        or compact == "10¹²/l"
    ):
        return "×10⁶/µL", normalized != "×10⁶/µL"
    canonical = _CANONICAL_UNITS[marker].get(compact)
    return (canonical, canonical != unit) if canonical is not None else (unit, False)


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
    first_match = matches[0] if matches else None
    if not first_match:
        return None

    # Some South Asian CBC forms print columns as test, reference range, unit,
    # result. When the first numeric span is itself a range, the first number
    # is a reference bound, not the result. Select the final numeric token
    # after that range (the result column); if OCR did not capture one, omit
    # the row instead of presenting a reference bound as a patient result.
    leading_range = _RANGE_PAIR.match(cleaned[first_match.start() :])
    if leading_range is not None:
        range_end = first_match.start() + leading_range.end()
        unit_tail = cleaned[range_end:]
        unit_match = _UNIT.match(unit_tail)
        value_start = range_end
        if unit_match is not None:
            candidate_unit = unit_match.group("unit")
            if (
                "/" in candidate_unit
                or "%" in candidate_unit
                or candidate_unit.lower() in _BARE_UNITS
                or re.fullmatch(r"x?10[*^]\d+", candidate_unit, re.IGNORECASE)
            ):
                value_start += unit_match.end()
        after_range = [candidate for candidate in matches if candidate.start() >= value_start]
        if not after_range:
            return None
        match = after_range[-1]
    else:
        match = first_match
        # If OCR inserts a stray digit/flag before a result, prefer the last
        # number before the first result unit (e.g. ``LDL 5 151 H mg/dL``).
        first_unit = _RESULT_UNIT_TOKEN.search(cleaned, match.end())
        if first_unit is not None:
            before_unit = [candidate for candidate in matches if candidate.end() <= first_unit.start()]
            if before_unit:
                match = before_unit[-1]

    # The analyte name ends before either the result (ordinary layout) or the
    # leading reference range (range-first layout).
    name = _EDGE_PUNCT.sub("", cleaned[: first_match.start()])
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
    if leading_range is not None:
        raw_low, raw_high = leading_range.group(1), leading_range.group(2)
        low, high = float(raw_low), float(raw_high)
        unit_source = cleaned[first_match.start() + leading_range.end() : match.start()]
        unit, _ = _unit_and_rest("".join(unit_source.split()))
    else:
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
    marker = canonical_marker(name)
    unit, unit_corrected = _canonical_unit(marker, unit)
    return ParsedValue(
        marker=marker,
        value=value,
        unit=unit,
        low=low,
        high=high,
        raw_value=raw_value,
        raw_low=raw_low,
        raw_high=raw_high,
        unit_corrected=unit_corrected,
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
    reference: str | None = None


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
    trailing = cleaned[match.end():]
    reference_match = _QUALITATIVE_RESULT.search(trailing)
    result = " ".join(match.group("result").lower().split())
    result += re.match(r"\+{1,2}", trailing.lstrip()).group(0) if re.match(r"\+{1,2}", trailing.lstrip()) else ""
    reference = " ".join(reference_match.group("result").lower().split()) if reference_match else None
    return ParsedQualitativeValue(
        marker=canonical_marker(name),
        result=result,
        reference=reference,
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


