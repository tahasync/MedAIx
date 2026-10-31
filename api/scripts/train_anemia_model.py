"""Train and evaluate the local experimental anemia dataset classifier.

Only model coefficients, feature summaries, and aggregate evaluation metrics
are written. The supplied CSV stays outside version control. NumPy is already
used by MedAIx's OCR pipeline; this script adds no dependency.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import statistics
import sys
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

import numpy as np

API_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(API_DIR))
from anemia_model import NUMERIC_FEATURES  # noqa: E402

TARGET = "Result"
SOURCE_COLUMNS = {
    "hemoglobin": "Hemoglobin",
    "mch": "MCH",
    "mchc": "MCHC",
    "mcv": "MCV",
}


def _read_csv(path: Path) -> tuple[list[dict[str, str]], str]:
    raw = path.read_bytes()
    with path.open("r", encoding="utf-8-sig", newline="") as source:
        source_rows = list(csv.DictReader(source))
    required = {*SOURCE_COLUMNS.values(), TARGET}
    if not source_rows or not required.issubset(source_rows[0]):
        missing = sorted(required - set(source_rows[0] if source_rows else []))
        raise ValueError(f"Dataset is empty or missing required columns: {missing}")
    rows = [
        {
            **{feature: row[source_name] for feature, source_name in SOURCE_COLUMNS.items()},
            TARGET: row[TARGET],
        }
        for row in source_rows
    ]
    return rows, hashlib.sha256(raw).hexdigest()


def _xy(rows: list[dict[str, str]]) -> tuple[np.ndarray, np.ndarray]:
    matrix = []
    labels = []
    for line, row in enumerate(rows, start=2):
        try:
            matrix.append([float(row[name]) for name in NUMERIC_FEATURES])
            label = int(row[TARGET])
        except (TypeError, ValueError) as exc:
            raise ValueError(f"Invalid numeric value at CSV line {line}.") from exc
        if label not in (0, 1):
            raise ValueError(f"Invalid target at CSV line {line}; expected 0 or 1.")
        labels.append(label)
    x = np.asarray(matrix, dtype=float)
    y = np.asarray(labels, dtype=float)
    if not np.isfinite(x).all() or len(set(y)) != 2:
        raise ValueError("Features must be finite and the target must have both classes.")
    return x, y


def _scale_fit(x: np.ndarray) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    means = np.mean(x, axis=0)
    scales = np.std(x, axis=0)
    scales[scales == 0] = 1.0
    return (x - means) / scales, means, scales


def _fit(x: np.ndarray, y: np.ndarray, regularization: float = 0.1) -> np.ndarray:
    design = np.column_stack([np.ones(len(x)), x])
    weights = np.zeros(design.shape[1], dtype=float)
    for step_index in range(6000):
        probabilities = 1.0 / (1.0 + np.exp(-np.clip(design @ weights, -30, 30)))
        gradient = design.T @ (probabilities - y) / len(y)
        gradient[1:] += regularization * weights[1:]
        weights -= (0.15 / math.sqrt(1.0 + step_index / 200.0)) * gradient
    return weights


def _scores(x: np.ndarray, weights: np.ndarray) -> np.ndarray:
    design = np.column_stack([np.ones(len(x)), x])
    return 1.0 / (1.0 + np.exp(-np.clip(design @ weights, -30, 30)))


def _auc(y: np.ndarray, scores: np.ndarray) -> float:
    positives = int(np.sum(y == 1))
    negatives = len(y) - positives
    order = np.argsort(scores, kind="mergesort")
    ranks = np.empty(len(scores), dtype=float)
    start = 0
    while start < len(order):
        end = start + 1
        while end < len(order) and scores[order[end]] == scores[order[start]]:
            end += 1
        ranks[order[start:end]] = (start + 1 + end) / 2.0
        start = end
    return float(
        (np.sum(ranks[y == 1]) - positives * (positives + 1) / 2)
        / (positives * negatives)
    )


def _metrics(y: np.ndarray, scores: np.ndarray) -> dict[str, float | int]:
    predicted = scores >= 0.5
    actual = y == 1
    tp = int(np.sum(predicted & actual))
    tn = int(np.sum(~predicted & ~actual))
    fp = int(np.sum(predicted & ~actual))
    fn = int(np.sum(~predicted & actual))
    precision = tp / (tp + fp) if tp + fp else 0.0
    recall = tp / (tp + fn) if tp + fn else 0.0
    return {
        "threshold": 0.5,
        "accuracy": (tp + tn) / len(y),
        "precision": precision,
        "recall": recall,
        "specificity": tn / (tn + fp) if tn + fp else 0.0,
        "f1": 2 * precision * recall / (precision + recall) if precision + recall else 0.0,
        "roc_auc": _auc(y, scores),
        "brier_score": float(np.mean((scores - y) ** 2)),
        "true_positive": tp,
        "true_negative": tn,
        "false_positive": fp,
        "false_negative": fn,
    }


def _stratified_folds(y: np.ndarray, folds: int, seed: int) -> list[np.ndarray]:
    random = np.random.default_rng(seed)
    buckets: list[list[int]] = [[] for _ in range(folds)]
    for label in (0, 1):
        indexes = np.flatnonzero(y == label)
        random.shuffle(indexes)
        for index, chunk in enumerate(np.array_split(indexes, folds)):
            buckets[index].extend(int(value) for value in chunk)
    return [np.asarray(sorted(bucket), dtype=int) for bucket in buckets]


def _evaluate(x: np.ndarray, y: np.ndarray) -> dict[str, Any]:
    holdout_indexes = _stratified_folds(y, folds=5, seed=31)[0]
    holdout_set = set(holdout_indexes.tolist())
    train_indexes = np.asarray([index for index in range(len(y)) if index not in holdout_set])
    train_x, means, scales = _scale_fit(x[train_indexes])
    test_x = (x[holdout_indexes] - means) / scales
    holdout = _metrics(y[holdout_indexes], _scores(test_x, _fit(train_x, y[train_indexes])))

    folds = []
    for validation_indexes in _stratified_folds(y, folds=5, seed=2026):
        validation_set = set(validation_indexes.tolist())
        fit_indexes = np.asarray([index for index in range(len(y)) if index not in validation_set])
        fit_x, fold_means, fold_scales = _scale_fit(x[fit_indexes])
        valid_x = (x[validation_indexes] - fold_means) / fold_scales
        folds.append(_metrics(y[validation_indexes], _scores(valid_x, _fit(fit_x, y[fit_indexes]))))
    cross_validation = {
        name: {
            "mean": statistics.mean(float(fold[name]) for fold in folds),
            "standard_deviation": statistics.stdev(float(fold[name]) for fold in folds),
        }
        for name in ("roc_auc", "recall", "specificity", "brier_score")
    }
    return {"stratified_holdout": holdout, "five_fold_cv": cross_validation}


def train(dataset: Path, output: Path) -> dict[str, Any]:
    rows, digest = _read_csv(dataset)
    x, y = _xy(rows)
    evaluation = _evaluate(x, y)
    scaled, means, scales = _scale_fit(x)
    weights = _fit(scaled, y)
    artifact = {
        "model_type": "medaix_anemia_logistic_v1",
        "model_version": "anemia-logistic-v1",
        "trained_at_utc": datetime.now(UTC).isoformat(),
        "dataset_sha256": digest,
        "dataset_rows": len(rows),
        "positive_rows": int(np.sum(y == 1)),
        "negative_rows": int(np.sum(y == 0)),
        "numeric_features": list(NUMERIC_FEATURES),
        "coefficients": [float(value) for value in weights],
        "numeric_means": {name: float(value) for name, value in zip(NUMERIC_FEATURES, means, strict=True)},
        "numeric_scales": {name: float(value) for name, value in zip(NUMERIC_FEATURES, scales, strict=True)},
        "numeric_ranges": {
            name: {"minimum": float(np.min(x[:, index])), "maximum": float(np.max(x[:, index]))}
            for index, name in enumerate(NUMERIC_FEATURES)
        },
        "excluded_features": {"Gender": "binary encoding and intended use are undocumented"},
        "evaluation": evaluation,
        "intended_use": "local research/demo classification only; not for patient diagnosis or treatment",
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(artifact, indent=2) + "\n", encoding="utf-8")
    return artifact


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("dataset", type=Path)
    parser.add_argument("--output", type=Path, default=API_DIR / "local_models" / "anemia_screening.json")
    args = parser.parse_args()
    artifact = train(args.dataset, args.output)
    print(f"Rows: {artifact['dataset_rows']}; positive: {artifact['positive_rows']}; negative: {artifact['negative_rows']}")
    print(json.dumps(artifact["evaluation"], indent=2))
    print(f"Local artifact written to: {args.output.resolve()}")
    print("These metrics apply only to this supplied dataset and are not clinical validation.")


if __name__ == "__main__":
    main()
