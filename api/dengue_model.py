"""Offline MedAIx dengue dataset model inference.

This is a research/demo classifier only. It returns a model score, not a
diagnosis, severity tier, or treatment recommendation. It is disabled unless
``MEDAIX_DENGUE_SCREENING_ENABLED=true`` and a locally trained artifact exists.
"""

from __future__ import annotations

import json
import math
import os
from pathlib import Path
from typing import Any

MODEL_PATH = Path(__file__).resolve().parent / "local_models" / "dengue_screening.json"
GENDERS = ("Female", "Male", "Child")
NUMERIC_FEATURES = (
    "age",
    "hemoglobin_g_dl",
    "wbc_count",
    "platelet_count",
    "platelet_distribution_width",
)


class DengueModelUnavailable(RuntimeError):
    """The opt-in experimental classifier is disabled or not trained locally."""


def screening_enabled() -> bool:
    """Only opt in through the deployment environment; default is off."""
    return os.getenv("MEDAIX_DENGUE_SCREENING_ENABLED", "false").lower() == "true"


def load_model(path: Path = MODEL_PATH) -> dict[str, Any]:
    if not screening_enabled():
        raise DengueModelUnavailable("Experimental dengue screening is disabled.")
    try:
        with path.open("r", encoding="utf-8") as model_file:
            model = json.load(model_file)
    except FileNotFoundError as exc:
        raise DengueModelUnavailable(
            "No local dengue model is installed. Train it from the authorized dataset first."
        ) from exc
    if model.get("model_type") != "medaix_logistic_v1":
        raise DengueModelUnavailable("The local dengue model artifact is not supported.")
    return model


def predict_probability(payload: dict[str, Any], model: dict[str, Any]) -> float:
    """Return the model's positive-label probability for normalized inputs."""
    gender = payload.get("gender")
    if gender not in GENDERS:
        raise ValueError("gender must be Female, Male, or Child.")

    medians = model["numeric_medians"]
    means = model["numeric_means"]
    scales = model["numeric_scales"]
    numeric = [
        float(payload[name]) if payload.get(name) is not None else float(medians[name])
        for name in NUMERIC_FEATURES
    ]
    standardized = [
        (value - float(means[name])) / float(scales[name])
        for name, value in zip(NUMERIC_FEATURES, numeric, strict=True)
    ]
    features = [*standardized, *(1.0 if gender == item else 0.0 for item in GENDERS)]
    coefficients = model["coefficients"]
    score = float(coefficients[0]) + sum(
        float(coef) * feature
        for coef, feature in zip(coefficients[1:], features, strict=True)
    )
    # Stable sigmoid for both score signs.
    if score >= 0:
        return 1.0 / (1.0 + math.exp(-score))
    exp_score = math.exp(score)
    return exp_score / (1.0 + exp_score)


def out_of_training_range(payload: dict[str, Any], model: dict[str, Any]) -> list[str]:
    """Identify supplied numeric features outside the dataset's observed span."""
    warnings = []
    ranges = model.get("numeric_ranges", {})
    for name in NUMERIC_FEATURES:
        value = payload.get(name)
        bounds = ranges.get(name)
        if value is None or not bounds:
            continue
        if float(value) < float(bounds["minimum"]) or float(value) > float(bounds["maximum"]):
            warnings.append(name)
    return warnings
