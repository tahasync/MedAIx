"""Medical-term simplification: raw OCR text -> plain language.

Dependency-free by design: spaCy and LLM calls add ~100 MB and a network hop,
both of which hurt Render's free tier (cold starts, egress, key management).
A term dictionary + sentence-aware replacement delivers the roadmap's intent
-- a medical-term simplification dictionary -- predictably, offline, and with
zero cold-start penalty. An LLM or spaCy stage can be swapped in behind
``simplify_text`` later without changing the endpoint contract.

Clinical-safety note: this rewords terms, it never changes values, units, or
reference ranges. Numbers are left untouched so a lab result cannot be
misread after simplification.
"""

import re
from dataclasses import dataclass

# Map medical jargon -> plain language. Keys are lower-case; matching is
# case-insensitive and uses word boundaries so "glucose" inside
# "blood-glucose" still matches but "glucosinolate" does not. Longer keys are
# tried first so "white blood cells" wins over "blood cells" where both apply.
_MEDICAL_TERMS: dict[str, str] = {
    # Blood components.
    "leukocytes": "white blood cells (fight infection)",
    "white blood cells": "white blood cells (fight infection)",
    "wbc": "white blood cells (fight infection)",
    "erythrocytes": "red blood cells (carry oxygen)",
    "red blood cells": "red blood cells (carry oxygen)",
    "rbc": "red blood cells (carry oxygen)",
    "thrombocytes": "platelets (help blood clot)",
    "platelets": "platelets (help blood clot)",
    "hemoglobin": "hemoglobin (the protein in red blood cells that carries oxygen)",
    "haemoglobin": "hemoglobin (the protein in red blood cells that carries oxygen)",
    "hct": "hematocrit (the share of your blood that is red blood cells)",
    "hematocrit": "hematocrit (the share of your blood that is red blood cells)",
    "haematocrit": "hematocrit (the share of your blood that is red blood cells)",
    "pcv": "hematocrit (the share of your blood that is red blood cells)",
    "rbcs": "red blood cells (carry oxygen)",
    "wbcs": "white blood cells (fight infection)",
    "red cell count": "red blood cell count (cells that carry oxygen)",
    "t.l.c": "total white blood cell count (cells that fight infection)",
    "tlc": "total white blood cell count (cells that fight infection)",
    "platelet count": "platelet count (cells that help blood clot)",
    "platelet": "platelets (help blood clot)",
    # Red-cell indices and the white-cell differential (every CBC lists these).
    "mcv": "MCV (average size of your red blood cells)",
    "mch": "MCH (average amount of hemoglobin per red blood cell)",
    "mchc": "MCHC (how concentrated the hemoglobin is in your red blood cells)",
    "rdw": "RDW (how much your red blood cells vary in size)",
    "neutrophils": "neutrophils (white blood cells that fight bacteria)",
    "segmented": "mature neutrophils (white blood cells that fight bacteria)",
    "stab": "young neutrophils (newly made infection-fighting cells)",
    "band cells": "young neutrophils (newly made infection-fighting cells)",
    "lymphocytes": "lymphocytes (white blood cells that fight viruses)",
    "monocytes": "monocytes (white blood cells that clear up infection)",
    "eosinophils": "eosinophils (white blood cells linked to allergy and parasites)",
    "basophils": "basophils (white blood cells involved in allergic reactions)",
    "differential count": "breakdown of white blood cell types",
    "esr": "ESR (how fast red cells settle; a general sign of inflammation)",
    "cbc": "CBC (complete blood count)",
    # Common analytes.
    "glucose": "blood sugar",
    "hba1c": "HbA1c (average blood sugar over the past 3 months)",
    "cholesterol": "cholesterol (a fat in your blood)",
    "triglycerides": "triglycerides (another fat in your blood)",
    "hdl": "HDL (the \"good\" cholesterol)",
    "ldl": "LDL (the \"bad\" cholesterol)",
    "vldl": "VLDL (a type of \"bad\" cholesterol)",
    "creatinine": "creatinine (a kidney-waste marker)",
    "urea": "urea (a kidney-waste marker)",
    "bun": "blood urea nitrogen (a kidney-waste marker)",
    "uric acid": "uric acid (a waste product; high levels can cause gout)",
    "sodium": "sodium (a salt in your blood)",
    "potassium": "potassium (a mineral in your blood)",
    "calcium": "calcium (a mineral in your blood)",
    "alt": "ALT (a liver enzyme)",
    "sgpt": "ALT (a liver enzyme)",
    "ast": "AST (a liver enzyme)",
    "sgot": "AST (a liver enzyme)",
    "alkaline phosphatase": "alkaline phosphatase (a liver and bone enzyme)",
    "ggt": "GGT (a liver enzyme)",
    "bilirubin": "bilirubin (a yellow pigment the liver clears)",
    "albumin": "albumin (the main protein made by your liver)",
    "total protein": "total protein (all the proteins in your blood)",
    "ferritin": "ferritin (your body's stored iron)",
    "tsh": "TSH (the hormone that controls your thyroid)",
    "free t4": "free T4 (a thyroid hormone)",
    "free t3": "free T3 (a thyroid hormone)",
    "crp": "CRP (a marker of inflammation)",
    "c-reactive protein": "CRP (a marker of inflammation)",
    "vitamin d": "vitamin D (needed for strong bones)",
    "vitamin b12": "vitamin B12 (needed for healthy blood and nerves)",
    "serum": "blood",
    # Urine and stool examinations.
    "pus cells": "pus cells (white blood cells; many can mean infection)",
    "epithelial cells": "epithelial cells (normal lining cells)",
    "specific gravity": "concentration of the urine",
    "ketones": "ketones (made when the body burns fat for energy)",
    "ova": "parasite eggs",
    "cysts": "parasite cysts",
    "nil": "none found",
    "absent": "none found",
    # Units.
    "mg/dl": "milligrams per decilitre",
    "mmol/l": "millimoles per litre",
    "g/dl": "grams per decilitre",
    "ng/ml": "nanograms per millilitre",
    "i.u./l": "international units per litre",
    "iu/l": "international units per litre",
    "u/l": "units per litre",
    # These two are glued to the number ("0-1/HPF"), hence the leading space.
    "/cmm": " per cubic millimetre",
    "/hpf": " per microscope field",
    # Result wording.
    "within normal limits": "normal",
    "w nl": "normal",
    "elevated": "higher than normal",
    "decreased": "lower than normal",
    "high": "higher than normal",
    "low": "lower than normal",
    "negative": "not detected",
    "positive": "detected",
    "borderline": "borderline (just outside the normal range)",
    "desirable": "ideal",
    "deficient": "too low",
    "insufficient": "a little low",
    "sufficient": "enough",
    "fasting": "measured after not eating",
    "non-fasting": "measured without fasting first",
    # Body / sample.
    "specimen": "sample",
    "venous": "from a vein",
    "capillary": "from a finger-prick",
}

# Phrases that contain a term above but must stay as written. "High" is a
# result flag on its own, yet "high risk" is a category label and "high
# density lipoprotein" is a name; rewording either would mislead.
_KEEP_PHRASES: frozenset[str] = frozenset(
    {
        "high risk",
        "higher risk",
        "low risk",
        "lower risk",
        "very high",
        "very low",
        "high density",
        "low density",
        "high power field",
        "low power field",
        "non-hdl",
        "non hdl",
    }
)

# Every word that appears in a dictionary key ("red", "cell", "count", "tlc"
# ...), plus the words of the most common report labels the dictionary does not
# reword. The OCR stage uses this as a safe list: a known lab word is kept even
# when Tesseract is unsure of it, because losing "Red cell count" from a report
# is worse than keeping one shaky header.
_REPORT_LABEL_WORDS = frozenset(
    {
        "test", "result", "results", "unit", "units", "ref", "reference",
        "range", "normal", "value", "values", "report", "name", "age", "sex",
        "gender", "date", "patient", "lab", "laboratory", "laboratories",
        "hematology", "haematology", "chemistry", "immunology", "hormones",
        "urine", "stool", "analysis", "examination", "microscopic",
        "macroscopic", "comments", "comment", "picture", "percentage",
        "absolute", "male", "female", "years", "year", "cell", "cells",
        "count", "total", "blood", "mean", "ratio", "index",
    }
)
KNOWN_LAB_WORDS: frozenset[str] = frozenset(
    word for term in _MEDICAL_TERMS for word in term.replace("/", " ").split()
) | _REPORT_LABEL_WORDS

# One alternation, longest term first so multi-word terms win over their
# substrings. A single ``re.sub`` pass scans the *original* text left to right
# exactly once, so text inserted by one replacement is never re-matched by a
# later one. The earlier per-term loop rescanned its own output, which is how
# "hemoglobin" could end up explained twice.
_TERM_PATTERN = re.compile(
    r"\b(?:"
    + "|".join(
        re.escape(term)
        for term in sorted(
            set(_MEDICAL_TERMS) | _KEEP_PHRASES, key=len, reverse=True
        )
    )
    + r")\b",
    re.IGNORECASE,
)


# Plain-language outputs, longest first. Spans of the input that already read
# as one of these are left untouched, so running ``simplify_text`` over text
# it produced earlier is a no-op rather than a second layer of explanation.
_PLAIN_PATTERN = re.compile(
    "|".join(
        re.escape(plain)
        for plain in sorted(set(_MEDICAL_TERMS.values()), key=len, reverse=True)
    ),
    re.IGNORECASE,
)


def _protected_spans(text: str) -> list[tuple[int, int]]:
    return [(m.start(), m.end()) for m in _PLAIN_PATTERN.finditer(text)]


def _plain_name(plain: str) -> str:
    """The bare name in a plain-language value, without its "(explanation)"."""
    return plain.partition(" (")[0]

# Split into sentences so simplification is reported per-sentence and the
# caller can show progress on long reports. Keeps the delimiter with its
# sentence so nothing is lost when reassembling.
_SENTENCE_SPLIT = re.compile(r"([.!?]+(?:\s+|$))")


@dataclass(frozen=True)
class SimplifyResult:
    """Outcome of simplifying one report's text."""

    simplified_text: str
    terms_simplified: int
    sentence_count: int
    note: str


def simplify_text(text: str) -> SimplifyResult:
    """Return ``text`` with medical jargon replaced by plain language.

    Numbers, units attached to numbers, and reference ranges are left verbatim
    so a result cannot be misread. Returns the simplified text, how many term
    replacements were made, the sentence count, and a short note for the UI.
    """
    if not text or not text.strip():
        return SimplifyResult(
            simplified_text="",
            terms_simplified=0,
            sentence_count=0,
            note="No text to simplify.",
        )

    sentences = [s for s in _SENTENCE_SPLIT.split(text) if s.strip()]
    sentence_count = len(sentences)

    # A term is explained the first time it appears in a report; later
    # mentions get the plain name only. A lipid panel names "cholesterol" six
    # times and reads badly with six copies of "(a fat in your blood)".
    # Seeded with explanations already present so a second pass adds none.
    explained = {
        _plain_name(text[start:end]).lower()
        for start, end in _protected_spans(text)
    }

    simplified_parts: list[str] = []
    terms_simplified = 0
    for sentence in sentences:
        simplified, count = _simplify_sentence(sentence, explained)
        simplified_parts.append(simplified)
        terms_simplified += count

    simplified_text = "".join(simplified_parts).strip()
    if terms_simplified == 0:
        note = "No medical terms found to simplify; text is already plain."
    else:
        note = f"{terms_simplified} medical term{'s' if terms_simplified != 1 else ''} reworded into plain language."

    return SimplifyResult(
        simplified_text=simplified_text,
        terms_simplified=terms_simplified,
        sentence_count=sentence_count,
        note=note,
    )


def _simplify_sentence(sentence: str, explained: set[str]) -> tuple[str, int]:
    """Replace medical terms in one sentence, returning text and replacement count.

    ``explained`` holds the plain names already given an explanation earlier
    in the same report; it is updated in place.
    """
    count = 0
    protected = _protected_spans(sentence)

    def _replace(match: re.Match[str]) -> str:
        nonlocal count
        original = match.group(0)
        key = original.lower()
        if key in _KEEP_PHRASES:
            return original
        if any(start <= match.start() < end for start, end in protected):
            return original
        plain = _MEDICAL_TERMS[key]
        name = _plain_name(plain)
        if name.lower() in explained:
            plain = name
        else:
            explained.add(name.lower())
        # "Cholesterol" after "cholesterol (a fat in your blood)" is already
        # plain: leave it and do not count it, so a second pass is a no-op.
        if plain.lower() == key:
            return original
        count += 1
        # Preserve the original capitalisation at sentence start.
        if original[:1].isupper():
            return plain[:1].upper() + plain[1:]
        return plain

    return _TERM_PATTERN.sub(_replace, sentence), count
