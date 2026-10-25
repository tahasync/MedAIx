"""Term sets for the Sprint 2 simplification check.

Each case is one report phrase. The expected fragment must appear after
replacement, and any lab number in the phrase must survive unchanged. The
later cases come from real Egyptian lab-report photos (CBC indices, the
white-cell differential, lipid and liver panels, urine and stool exams).
"""

import pytest

import simplify as simplify_module

_TERM_SETS = [
    ("Leukocytes 11.2", "white blood cells (fight infection)", "11.2"),
    ("Erythrocytes 4.8", "red blood cells (carry oxygen)", "4.8"),
    ("Thrombocytes 245", "platelets (help blood clot)", "245"),
    ("Haemoglobin 14.2 g/dL", "carries oxygen", "14.2"),
    ("Hematocrit 42", "share of your blood", "42"),
    ("Glucose 98 mg/dL", "blood sugar", "98"),
    ("Cholesterol was elevated", "higher than normal", None),
    ("Creatinine 1.1", "kidney-waste marker", "1.1"),
    ("Sodium 140 mmol/L", "a salt in your blood", "140"),
    ("Potassium is decreased", "lower than normal", None),
    ("Fasting specimen", "measured after not eating", None),
    ("Result negative", "not detected", None),
    ("MCV 87.5 fL", "average size of your red blood cells", "87.5"),
    ("MCHC 33.5 g/dL", "how concentrated the hemoglobin", "33.5"),
    ("Lymphocytes 29 %", "fight viruses", "29"),
    ("Segmented 60 %", "mature neutrophils", "60"),
    ("LDL 80 mg/dL", '"bad" cholesterol', "80"),
    ("SGPT (ALT) 32 U/L", "liver enzyme", "32"),
    ("Ferritin in Serum 53.0 ng/mL", "stored iron", "53.0"),
    ("Pus Cells 5-6 /HPF", "many can mean infection", "5-6"),
    ("Ova : Nil", "none found", None),
    ("Vitamin D 10.9 ng/mL Deficient", "too low", "10.9"),
]


@pytest.mark.parametrize(("raw", "expected", "number"), _TERM_SETS)
def test_term_set_is_rewritten_without_changing_numbers(
    raw: str,
    expected: str,
    number: str | None,
) -> None:
    result = simplify_module.simplify_text(raw)

    assert expected in result.simplified_text.lower()
    assert result.terms_simplified >= 1
    if number is not None:
        assert number in result.simplified_text


def test_each_term_is_explained_exactly_once() -> None:
    """A replacement must never be re-matched by a later term.

    Regression: "hemoglobin" expands to text containing "red blood cells",
    which is itself a term. Rescanning produced a double explanation.
    """
    result = simplify_module.simplify_text("Hemoglobin 14.1 g/dL, RBC 4.8")

    assert result.simplified_text.count("carries oxygen") == 1
    assert result.simplified_text.count("carry oxygen") == 1
    assert result.terms_simplified == 3  # hemoglobin, g/dL, RBC


def test_simplifying_twice_is_a_no_op() -> None:
    """Already-simplified text passes through unchanged."""
    first = simplify_module.simplify_text("Hemoglobin 14.1, hematocrit 42, glucose 98.")
    second = simplify_module.simplify_text(first.simplified_text)

    assert second.simplified_text == first.simplified_text
    assert second.terms_simplified == 0


def test_multi_word_term_beats_its_substring() -> None:
    result = simplify_module.simplify_text("White blood cells 7.2")

    assert result.terms_simplified == 1
    assert result.simplified_text == "White blood cells (fight infection) 7.2"


def test_a_term_is_explained_once_per_report() -> None:
    """A lipid panel names cholesterol many times; explain it on first use only."""
    result = simplify_module.simplify_text(
        "Serum Cholesterol 191 mg/dL. HDL-Cholesterol 45 mg/dL. "
        "T.Cholesterol / HDL Cholesterol 4.24"
    )

    assert result.simplified_text.count("(a fat in your blood)") == 1
    assert result.simplified_text.count('(the "good" cholesterol)') == 1
    assert "191" in result.simplified_text
    assert "4.24" in result.simplified_text
    # Running it again changes nothing.
    again = simplify_module.simplify_text(result.simplified_text)
    assert again.simplified_text == result.simplified_text
    assert again.terms_simplified == 0


def test_category_labels_and_names_containing_high_or_low_are_kept() -> None:
    """"High risk" is a category and "high density" is a name, not a flag."""
    result = simplify_module.simplify_text(
        "Over 240 High Risk. Very High. High Density Lipoprotein. Result: High"
    )

    assert "High Risk" in result.simplified_text
    assert "Very High" in result.simplified_text
    assert "High Density Lipoprotein" in result.simplified_text
    assert result.simplified_text.endswith("Result: Higher than normal")
    assert result.terms_simplified == 1
