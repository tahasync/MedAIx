"""Report OCR: preprocessing plus Tesseract extraction.

Kept separate from the route so the pipeline can be exercised directly in tests
without going through HTTP or a real upload.

Preprocessing order matters and is not arbitrary:

1. **EXIF transpose** first. Phone cameras record orientation in metadata, not
   pixels. Without this a portrait photo of a sideways page OCRs as garbage.
2. **Grayscale + autocontrast.** Lab reports are photographed under uneven
   lighting; autocontrast stretches the histogram so faint pencil text survives
   the binarisation Tesseract does internally.
3. **Deskew.** A few degrees of rotation tanks Tesseract's accuracy far more
   than noise does, and phone shots are routinely a couple of degrees off.
   This uses the projection-profile method: rotate, measure how peaked the
   horizontal ink histogram is, and keep the angle that maximises it. Sampling
   at 0.5 degree steps keeps it fast enough to run per-request.
4. **Resize to Tesseract's efficient range.** Tesseract's accuracy plateaus at
   roughly 300 DPI, so the long edge is clamped to [_MIN_LONG_EDGE, _MAX_LONG_EDGE]:
   small images are upscaled (narrower than ~1500px loses small print) and large
   ones are downscaled (past ~3000px only adds runtime and memory — both scarce
   on the free tier — with no accuracy gain).
5. **Noise filter after OCR.** Bilingual reports carry Arabic or Urdu headers
   that the English model reads as Latin soup at near-zero confidence. Those
   tokens are dropped (see :func:`_is_noise`); numbers and known lab words are
   always kept. The reported confidence is the mean over the words returned.
"""

import logging
import os
import re
from dataclasses import dataclass
from enum import StrEnum
from functools import lru_cache
from pathlib import Path

import numpy as np
import pytesseract
from PIL import Image, ImageOps
from pytesseract import Output

from simplify import KNOWN_LAB_WORDS

logger = logging.getLogger(__name__)

# Tesseract's data files live outside the Python env. On Windows the installer
# does not add it to PATH for the current session, so try the default location
# before giving up — otherwise every OCR call raises TesseractNotFoundError.
_WINDOWS_TESSERACT = r"C:\Program Files\Tesseract-OCR\tesseract.exe"
_LOCAL_TESSDATA = Path(__file__).resolve().parent / ".tessdata"
if _LOCAL_TESSDATA.is_dir():
    # The setup script uses a project-local copy so students can add Urdu data
    # without administrator access to Program Files. Production installations
    # use the system tessdata path unless it is explicitly configured.
    os.environ.setdefault("TESSDATA_PREFIX", str(_LOCAL_TESSDATA))

# Below this the print is too small for Tesseract to segment reliably.
_MIN_LONG_EDGE = 1500

# Ceiling for the long edge before OCR. ~300 DPI for a page is where Tesseract's
# accuracy plateaus; beyond that, extra pixels only add time and memory — both
# scarce on Render's ~512 MB free tier. 3000px is roughly 300 DPI on a portrait
# page and twice the floor above, so small print still survives while a 12 MP
# phone photo (~4000px long edge) is reined in instead of being fed straight to
# the OCR engine at full resolution.
_MAX_LONG_EDGE = 3000

# Deskew searches a downscaled probe, not the full image. The projection
# profile's peak angle is scale-invariant, but every candidate rotation costs
# O(pixels), so probing at ~1000px on the long edge removes the dominant cost of
# this pipeline while still resolving sub-degree skew. The correction itself is
# applied to the full-resolution image.
_DESKEW_PROBE_LONG_EDGE = 1000

# Deskew search range. Real photos sit within a few degrees of level; widening
# this costs time and risks "correcting" a genuinely rotated document.
_MAX_SKEW_DEGREES = 7.0
_SKEW_STEP = 0.5

# Page segmentation mode 4: "a single column of text of variable sizes".
# Lab reports are rows (test, result, unit, range); mode 6 ("uniform block")
# assumed one font size and merged columns. Measured on the Train split of the
# Mendeley report photos: mean word confidence 77.4 -> 78.9, fewer low-confidence
# numbers (26 -> 24 of ~500), fewer garbage tokens, +0.05 s per image.
_TESSERACT_CONFIG = "--oem 3 --psm 4"

# Tokens Tesseract scores below this are usually not text at all: on bilingual
# reports the Arabic header, read with the English model, comes out as Latin
# soup ("Saytall", "Baagll", "oayyall") at 0-25% confidence, while genuine
# English words on the same page sit above 60%. Anything containing a digit is
# always kept: a shaky result value must reach the user (who is told to check
# it against the original), never be silently dropped. Single characters are
# kept too ("+", "F", "-") since they carry meaning and cost nothing.
_NOISE_CONFIDENCE = 25.0

# Set once the Tesseract binary has answered a version probe. The binary's
# presence does not change while the server runs, so this latches the one
# successful check and removes a subprocess spawn from every later upload.
_TESSERACT_READY = False


class OcrUnavailableError(RuntimeError):
    """Tesseract is not installed or not reachable.

    Distinct from a failed extraction: the caller should say the feature is
    unavailable rather than "we could not read your report".
    """


class OcrLanguage(StrEnum):
    """Language style selected by the user for a report upload."""

    ENGLISH = "english"
    URDU = "urdu"
    ROMAN_URDU = "roman_urdu"


_TESSERACT_LANGUAGES = {
    OcrLanguage.ENGLISH: "eng",
    # Most Pakistani lab reports mix English test names and units with Urdu
    # notes, so Urdu mode includes both trained data files.
    OcrLanguage.URDU: "urd+eng",
    # Roman Urdu is written in the Latin alphabet and uses the English model.
    OcrLanguage.ROMAN_URDU: "eng",
}


@dataclass(frozen=True)
class OcrResult:
    """Extraction outcome for one report image."""

    text: str
    confidence: float
    width: int
    height: int
    skew_degrees: float

def _rotate_probe(probe: Image.Image, angle: float) -> np.ndarray:
    """Nearest-neighbour rotation of the deskew probe, as an array.

    Nearest-neighbour rather than bilinear on purpose: smoothing blurs thin
    strokes, and the projection profile is measuring stroke sharpness.

    Pixels rotated in from outside the source are filled with ``255`` (paper),
    never ``0``. A black fill would register as ink under the darkness
    threshold in [_projection_sharpness], adding a solid dark border that grows
    with the angle and swamps the text signal — every probe would then look
    "sharper" the further it rotated, pinning the estimate at the search limit.

    Pillow's C rotation replaces an earlier NumPy fancy-indexing version. Same
    output, ~17x faster: the 29-angle search fell from ~0.45 s to ~0.03 s per
    upload, which was half of the whole OCR request on real report photos.
    """
    return np.asarray(
        probe.rotate(angle, resample=Image.NEAREST, fillcolor=255),
        dtype=np.uint8,
    )


def _projection_sharpness(array: np.ndarray) -> float:
    """Sum of squared row sums — high when text forms sharp horizontal lines.

    Rotated text smears each row across many pixels and flattens this; level
    text concentrates ink into few rows and spikes it.

    Ink is DARK on a light page, so the threshold is ``< 128``, not ``> 128``.
    Inverting that selects the white background instead of the text and
    measures how *evenly* the page is blanked — which peaks on a skewed scan,
    i.e. it reports the opposite of the truth.
    """
    ink = array < 128
    if not ink.any():
        return 0.0
    row_sums = ink.sum(axis=1).astype(np.float64)
    return float(np.square(row_sums).sum())


def _deskew_probe(image: Image.Image) -> Image.Image:
    """Downscale a copy for the deskew search without changing the angle.

    The projection profile's peak angle is the same at any scale, but each
    candidate rotation costs O(pixels). Probing a ~1000px-long-edge copy keeps
    the search cheap on full-resolution phone photos; [_deskew] applies the
    winning angle to the original, full-resolution image.
    """
    long_edge = max(image.size)
    if long_edge <= _DESKEW_PROBE_LONG_EDGE:
        return image
    scale = _DESKEW_PROBE_LONG_EDGE / long_edge
    return image.resize(
        (max(1, int(image.width * scale)), max(1, int(image.height * scale))),
        Image.BILINEAR,
    )


def _deskew(image: Image.Image) -> tuple[Image.Image, float]:
    """Rotate to level using the projection-profile method.

    Returns the rotated image and the angle applied. Falls back to the original
    image if the array maths fails, since a slightly skewed read beats no read.
    """
    probe = _deskew_probe(image)
    try:
        grayscale = np.asarray(probe, dtype=np.uint8)
    except (ValueError, OSError):
        return image, 0.0

    # Rotation is O(width x height) per candidate angle, and it runs once per
    # step across the whole search. Probing the downscaled copy from
    # [_deskew_probe] is what keeps that affordable on full-resolution photos.
    best_angle = 0.0
    best_score = _projection_sharpness(grayscale)
    if best_score == 0.0:
        return image, 0.0

    angle = -_MAX_SKEW_DEGREES
    while angle <= _MAX_SKEW_DEGREES:
        score = _projection_sharpness(_rotate_probe(probe, angle))
        if score > best_score:
            best_score = score
            best_angle = angle
        angle += _SKEW_STEP

    if abs(best_angle) < _SKEW_STEP:
        return image, 0.0

    return (
        image.rotate(best_angle, resample=Image.BICUBIC, fillcolor="white"),
        best_angle,
    )


def preprocess(source: Image.Image) -> tuple[Image.Image, float]:
    """Normalise an uploaded image for OCR. Returns the image and applied skew."""
    image = ImageOps.exif_transpose(source)
    if image.mode not in ("L", "RGB"):
        image = image.convert("RGB")

    grayscale = ImageOps.autocontrast(image.convert("L"), cutoff=1)
    levelled, skew = _deskew(grayscale)

    return _resize_to_bounds(levelled), skew


def _resize_to_bounds(image: Image.Image) -> Image.Image:
    """Scale the long edge into Tesseract's efficient range before OCR.

    Two bounds, applied to the same axis so aspect ratio is preserved:

    * Up to :data:`_MIN_LONG_EDGE` when small — Tesseract loses fine print below
      roughly 300 DPI.
    * Down to :data:`_MAX_LONG_EDGE` when large — Tesseract's runtime and memory
      both grow with pixel count, and a 12 MP phone photo (~4000px) costs the
      free tier dearly for no accuracy gain past ~300 DPI.

    Within the range the image is returned untouched, so an already-well-sized
    scan is never needlessly resampled.
    """
    long_edge = max(image.size)
    if _MIN_LONG_EDGE <= long_edge <= _MAX_LONG_EDGE:
        return image

    target = min(max(long_edge, _MIN_LONG_EDGE), _MAX_LONG_EDGE)
    scale = target / long_edge
    return image.resize(
        (max(1, int(image.width * scale)), max(1, int(image.height * scale))),
        Image.LANCZOS,
    )


def extract_text(
    image: Image.Image,
    language: OcrLanguage = OcrLanguage.ENGLISH,
) -> OcrResult:
    """Run the full pipeline and return text plus mean confidence.

    Confidence comes from Tesseract's own word-level estimate, averaged over
    the words that make it into ``text`` (noise tokens are dropped first, see
    :func:`_is_noise`). Tesseract reports -1 for layout/noise blobs, which
    carry no confidence and are excluded so they cannot drag the mean down.
    """
    _ensure_binary()

    prepared, skew = preprocess(image)
    tesseract_language = _TESSERACT_LANGUAGES[language]
    required_languages = set(tesseract_language.split("+"))
    installed_languages = _installed_languages()
    missing_languages = required_languages - installed_languages
    if missing_languages:
        missing = ", ".join(sorted(missing_languages))
        raise OcrUnavailableError(
            f"OCR language data is missing ({missing}). Install the matching "
            "Tesseract traineddata files and try again."
        )

    primary = _read_pass(prepared, tesseract_language, _TESSERACT_CONFIG)
    result_text, mean_confidence = primary

    # Sparse or uncertain pages often have a table/layout that PSM 4 segments
    # poorly. Retry those pages with Tesseract's single-block layout and keep
    # the pass that yields more supported lab rows, using confidence as a tie
    # breaker. Dense, clear reports still pay for only one OCR pass.
    if mean_confidence < 65 or _recognized_row_count(result_text) < 2:
        alternate = _read_pass(prepared, tesseract_language, "--oem 3 --psm 6")
        if _pass_score(alternate) > _pass_score(primary):
            result_text, mean_confidence = alternate

    return OcrResult(
        # Keep each Tesseract line intact: the trend parser expects a marker,
        # result, units and range to stay on their printed report row.
        text=result_text,
        confidence=round(mean_confidence, 2),
        width=prepared.width,
        height=prepared.height,
        skew_degrees=round(skew, 2),
    )


def _read_pass(
    image: Image.Image, language: str, config: str
) -> tuple[str, float]:
    data = pytesseract.image_to_data(
        image, lang=language, config=config, output_type=Output.DICT
    )
    lines: dict[tuple[int, int, int], list[str]] = {}
    confidences: list[float] = []
    for index, (word, confidence) in enumerate(zip(data["text"], data["conf"], strict=True)):
        stripped = word.strip()
        if not stripped or _is_noise(stripped, float(confidence)):
            continue
        line_key = (
            int(data["block_num"][index]),
            int(data["par_num"][index]),
            int(data["line_num"][index]),
        )
        lines.setdefault(line_key, []).append(stripped)
        if confidence >= 0:
            confidences.append(float(confidence))
    text = "\n".join(" ".join(words) for words in lines.values())
    confidence = sum(confidences) / len(confidences) if confidences else 0.0
    return text, round(confidence, 2)


def _recognized_row_count(text: str) -> int:
    # Local import avoids loading the trend engine unless a sparse page needs
    # a fallback pass. Numeric and qualitative lab rows both count as useful
    # extraction; qualitative values are kept out of numeric trend analysis.
    from trends import parse_lab_values, parse_qualitative_lab_values

    return len(parse_lab_values(text)) + len(parse_qualitative_lab_values(text))


def _pass_score(result: tuple[str, float]) -> tuple[int, float]:
    text, confidence = result
    return _recognized_row_count(text), confidence

_HAS_DIGIT = re.compile(r"\d")


def _is_noise(token: str, confidence: float) -> bool:
    """True for a low-confidence token that carries no number and is not a known lab word.

    See :data:`_NOISE_CONFIDENCE`. Tesseract reports ``-1`` for layout blobs it
    did not classify; those are not words and are dropped here as well when
    they are longer than one character.
    """
    if confidence >= _NOISE_CONFIDENCE:
        return False
    if len(token) == 1 or _HAS_DIGIT.search(token):
        return False
    return token.lower().strip(".,:;()[]") not in KNOWN_LAB_WORDS


@lru_cache(maxsize=1)
def _installed_languages() -> frozenset[str]:
    """Installed Tesseract traineddata codes, cached for the process lifetime.

    ``pytesseract.get_languages`` shells out to ``tesseract --list-langs``; the
    set of traineddata files does not change while the server runs, so probing
    it once and caching removes a subprocess spawn from every upload. A missing
    binary raises (and lru_cache does not cache exceptions), so a broken install
    keeps failing loudly rather than being frozen as an empty set.
    """
    try:
        return frozenset(pytesseract.get_languages(config=""))
    except pytesseract.TesseractNotFoundError as exc:
        raise OcrUnavailableError("Tesseract is not installed.") from exc


def _ensure_binary() -> None:
    global _TESSERACT_READY
    if _TESSERACT_READY:
        return
    try:
        pytesseract.get_tesseract_version()
    except pytesseract.TesseractNotFoundError:
        try:
            pytesseract.pytesseract.tesseract_cmd = _WINDOWS_TESSERACT
            pytesseract.get_tesseract_version()
        except Exception as exc:  # noqa: BLE001 - re-raised as a clear error
            raise OcrUnavailableError(
                "Tesseract is not installed. Install it with "
                "`winget install UB-Mannheim.TesseractOCR`."
            ) from exc
    else:
        # Latch success only. A failure leaves the flag false so the next call
        # re-probes: a binary installed mid-session is picked up, and a broken
        # one keeps failing instead of being frozen as ready.
        _TESSERACT_READY = True
