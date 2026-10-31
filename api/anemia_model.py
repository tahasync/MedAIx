"""Opt-in local inference for the experimental anemia dataset classifier.

The score is a dataset-model output only. It is not a diagnosis, clinical
interpretation, or replacement for a clinician reviewing the report.
"""

from __future__ import annotations

import json
import math
import os
from pathlib import Path
from typing import Any

MODEL_PATH = Path(__file__).resolve().parent / "local_models" / "anemia_screening.json"
NUMERIC_FEATURES = ("hemoglobin", "mch", "mchc", "mcv")


class AnemiaModelUnavailable(RuntimeError):
    """Raised when the experimental model is disabled or unavailable."""


def screening_enabled() -> bool:
    return os.getenv("MEDAIX_ANEMIA_SCREENING_ENABLED", "false").lower() == "true"


def load_model(path: Path = MODEL_PATH) -> dict[str, Any]:
    if not screening_enabled():
        raise AnemiaModelUnavailable("Experimental anemia screening is disabled.")
    try:
        with path.open("r", encoding="utf-8") as model_file:
            model = json.load(model_file)
    except FileNotFoundError as exc:
        raise AnemiaModelUnavailable(
            "No local anemia model is installed. Train it from the authorized dataset first."
        ) from exc
    if model.get("model_type") != "medaix_anemia_logistic_v1":
        raise AnemiaModelUnavailable("The local anemia model artifact is not supported.")
    return model


def predict_probability(payload: dict[str, Any], model: dict[str, Any]) -> float:
    numeric = [float(payload[name]) for name in NUMERIC_FEATURES]
    standardized = [
        (value - float(model["numeric_means"][name]))
        / float(model["numeric_scales"][name])
        for name, value in zip(NUMERIC_FEATURES, numeric, strict=True)
    ]
    features = [1.0, *standardized]
    score = sum(
        float(coefficient) * feature
        for coefficient, feature in zip(model["coefficients"], features, strict=True)
    )
    if score >= 0:
        return 1.0 / (1.0 + math.exp(-score))
    exp_score = math.exp(score)
    return exp_score / (1.0 + exp_score)


def out_of_training_range(payload: dict[str, Any], model: dict[str, Any]) -> list[str]:
    warnings = []
    for name in NUMERIC_FEATURES:
        value = float(payload[name])
        bounds = model["numeric_ranges"][name]
        if value < float(bounds["minimum"]) or value > float(bounds["maximum"]):
            warnings.append(name)
    return warnings
