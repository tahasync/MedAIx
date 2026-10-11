"""Shared pytest fixtures for the MedAIx API tests."""

import pytest

import ocr as ocr_module


@pytest.fixture(autouse=True)
def _reset_ocr_caches() -> None:
    """Clear OCR process-lifetime caches before every test.

    ``ocr`` caches two facts that are stable in production but must not leak
    between tests: that the Tesseract binary is present (``_TESSERACT_READY``)
    and the set of installed traineddata languages (``_installed_languages``).
    ``test_urdu_upload_explains_when_language_data_is_missing`` fakes a missing
    ``urd`` model by monkeypatching ``pytesseract.get_languages``; a cache
    populated by an earlier test would hide that patch. Resetting both here
    restores per-test isolation without every test having to remember to.
    """
    ocr_module._TESSERACT_READY = False
    ocr_module._installed_languages.cache_clear()
