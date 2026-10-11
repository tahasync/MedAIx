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
4. **Upscale small images.** Tesseract wants roughly 300 DPI; anything narrower
   than ~1500px on the long edge loses small print.
"""

import logging
import os
from dataclasses import dataclass
from enum import StrEnum
from pathlib import Path

import numpy as np
import pytesseract
from PIL import Image, ImageOps
from pytesseract import Output

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

# Deskew search range. Real photos sit within a few degrees of level; widening
# this costs time and risks "correcting" a genuinely rotated document.
_MAX_SKEW_DEGREES = 7.0
_SKEW_STEP = 0.5


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

def _rotate_array(array: np.ndarray, angle: float) -> np.ndarray:
    """Nearest-neighbour rotation about the centre.

    Nearest-neighbour rather than bilinear on purpose: smoothing blurs thin
    strokes, and the projection profile is measuring stroke sharpness.

    Pixels rotated in from outside the source are filled with ``255`` (paper),
    never ``0``. A black fill would register as ink under the darkness
    threshold in [_projection_sharpness], adding a solid dark border that grows
    with the angle and swamps the text signal — every probe would then look
    "sharper" the further it rotated, pinning the estimate at the search limit.
    """
    radians = np.deg2rad(angle)
    cosine, sine = np.cos(radians), np.sin(radians)
    height, width = array.shape
    centre_y, centre_x = height / 2.0, width / 2.0

    y_coords, x_coords = np.ogrid[:height, :width]
    offset_y = y_coords - centre_y
    offset_x = x_coords - centre_x
    source_x = (offset_x * cosine - offset_y * sine + centre_x).astype(np.int32)
    source_y = (offset_x * sine + offset_y * cosine + centre_y).astype(np.int32)

    valid = (
        (source_x >= 0) & (source_x < width) & (source_y >= 0) & (source_y < height)
    )
    output = np.full_like(array, 255)
    output[valid] = array[source_y[valid], source_x[valid]]
    return output


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


def _deskew(image: Image.Image) -> tuple[Image.Image, float]:
    """Rotate to level using the projection-profile method.

    Returns the rotated image and the angle applied. Falls back to the original
    image if the array maths fails, since a slightly skewed read beats no read.
    """
    try:
        grayscale = np.asarray(image.convert("L"), dtype=np.float64)
    except (ValueError, OSError):
        return image, 0.0

    # Rotation is O(width x height) per candidate angle. Rotating the array by
    # -angle rather than rebuilding the image each time keeps this cheap enough
    # to sit in a request path.
    best_angle = 0.0
    best_score = _projection_sharpness(grayscale)
    if best_score == 0.0:
        return image, 0.0

    angle = -_MAX_SKEW_DEGREES
    while angle <= _MAX_SKEW_DEGREES:
        score = _projection_sharpness(_rotate_array(grayscale, angle))
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

    long_edge = max(levelled.size)
    if long_edge < _MIN_LONG_EDGE:
        scale = _MIN_LONG_EDGE / long_edge
        levelled = levelled.resize(
            (int(levelled.width * scale), int(levelled.height * scale)),
            Image.LANCZOS,
        )

    return levelled, skew


def extract_text(
    image: Image.Image,
    language: OcrLanguage = OcrLanguage.ENGLISH,
) -> OcrResult:
    """Run the full pipeline and return text plus mean confidence.

    Confidence comes from Tesseract's own word-level estimate, averaged over
    recognised words only. Tesseract reports -1 for layout/noise blobs, which
    carry no confidence and are excluded so they cannot drag the mean down.
    """
    _ensure_binary()

    prepared, skew = preprocess(image)
    tesseract_language = _TESSERACT_LANGUAGES[language]
    required_languages = set(tesseract_language.split("+"))
    try:
        installed_languages = set(pytesseract.get_languages(config=""))
    except pytesseract.TesseractNotFoundError as exc:
        raise OcrUnavailableError("Tesseract is not installed.") from exc
    missing_languages = required_languages - installed_languages
    if missing_languages:
        missing = ", ".join(sorted(missing_languages))
        raise OcrUnavailableError(
            f"OCR language data is missing ({missing}). Install the matching "
            "Tesseract traineddata files and try again."
        )

    data = pytesseract.image_to_data(
        prepared,
        lang=tesseract_language,
        config="--oem 3 --psm 6",
        output_type=Output.DICT,
    )

    words: list[str] = []
    confidences: list[float] = []
    for word, confidence in zip(data["text"], data["conf"]):
        stripped = word.strip()
        if not stripped:
            continue
        words.append(stripped)
        if confidence >= 0:
            confidences.append(float(confidence))

    mean_confidence = sum(confidences) / len(confidences) if confidences else 0.0

    return OcrResult(
        text=" ".join(words),
        confidence=round(mean_confidence, 2),
        width=prepared.width,
        height=prepared.height,
        skew_degrees=round(skew, 2),
    )

def _ensure_binary() -> None:
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
