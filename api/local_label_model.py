"""Tiny offline character n-gram model for recovering OCR lab labels.

This is a nearest-prototype classifier over an allowlist, not a text generator.
It can identify a noisy label but never edits values, units, ranges, or clinical
interpretation. The report summary remains a deterministic template.
"""

from __future__ import annotations

import math
import re
from collections import Counter

_LABELS = (
    "colour", "color", "appearance", "clarity", "odour", "odor",
    "consistency", "blood", "mucus", "food particles", "worms",
    "parasite eggs", "ova", "cysts", "pus cells", "red blood cells",
    "rbc", "white blood cells", "wbc", "epithelial cells", "bacteria",
    "yeast", "crystals", "casts", "protein", "glucose", "ketones",
    "bilirubin", "urobilinogen", "nitrite", "specific gravity", "ph",
    "trophozoite", "vegetables", "muscle fibres", "muscles", "starch",
    "fats", "undigested food", "undigestive food", "pus cell", "rbc cells",
)


def _normalize(text: str) -> str:
    return " ".join(re.findall(r"[a-z]+", text.lower()))


def _ngrams(text: str) -> Counter[str]:
    padded = f"  {_normalize(text)}  "
    return Counter(
        padded[start : start + size]
        for size in range(2, 5)
        for start in range(max(0, len(padded) - size + 1))
    )


_PROTOTYPES = tuple((label, _ngrams(label)) for label in _LABELS)
_DOCUMENT_FREQUENCY = Counter(
    gram for _, features in _PROTOTYPES for gram in features.keys()
)
_DOC_COUNT = len(_PROTOTYPES)


def _weighted(features: Counter[str]) -> tuple[dict[str, float], float]:
    weights = {
        gram: count * (math.log((_DOC_COUNT + 1) / (_DOCUMENT_FREQUENCY[gram] + 1)) + 1)
        for gram, count in features.items()
    }
    return weights, math.sqrt(sum(weight * weight for weight in weights.values()))


_WEIGHTED_PROTOTYPES = tuple(
    (label, *_weighted(features)) for label, features in _PROTOTYPES
)


def classify_label(text: str, *, minimum_score: float = 0.48) -> tuple[str, float] | None:
    """Return the closest allowlisted label when character overlap is strong."""
    query = _ngrams(text)
    if not query:
        return None
    query_weights, query_norm = _weighted(query)
    best_label, best_score = "", 0.0
    for label, prototype, norm in _WEIGHTED_PROTOTYPES:
        dot = sum(query_weights.get(gram, 0.0) * weight for gram, weight in prototype.items())
        score = dot / (query_norm * norm) if query_norm and norm else 0.0
        if score > best_score:
            best_label, best_score = label, score
    return (best_label, best_score) if best_score >= minimum_score else None
