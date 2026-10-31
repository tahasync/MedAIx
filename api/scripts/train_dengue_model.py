"""Train and evaluate the local, experimental dengue dataset classifier.

This uses NumPy already required by the OCR pipeline. It writes only model
coefficients and aggregate evaluation metrics; no source rows are copied.
The supplied CSV should remain outside version control.
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
from dengue_model import GENDERS, NUMERIC_FEATURES  # noqa: E402

TARGET = "dengue_label"
EXCLUDED = {
    "differential_count": "binary 0/1 values with unclear definition in the dataset",
    "rbc_count": "binary 0/1 values with unclear definition in the dataset",
}


def _read_csv(path: Path) -> tuple[list[dict[str, str]], str]:
    raw = path.read_bytes()
    with path.open("r", encoding="utf-8-sig", newline="") as csv_file:
        rows = list(csv.DictReader(csv_file))
        headers = set(rows[0]) if rows else set()
    required = {*NUMERIC_FEATURES, "gender", TARGET}
    if not rows or not required.issubset(headers):
        missing = sorted(required - headers)
        raise ValueError(f"Dataset is empty or missing required columns: {missing}")
    return rows, hashlib.sha256(raw).hexdigest()


def _prepare(
    rows: list[dict[str, str]],
    fit: bool,
    preprocessing: dict[str, Any] | None = None,
) -> tuple[np.ndarray, np.ndarray, dict[str, Any]]:
    labels: list[int] = []
    raw_numeric: dict[str, list[float | None]] = {name: [] for name in NUMERIC_FEATURES}
    genders: list[str] = []
    for line, row in enumerate(rows, start=2):
        label = row[TARGET].strip()
        if label not in {"0", "1"}:
            raise ValueError(f"Invalid target at CSV line {line}; expected 0 or 1.")
        gender = row["gender"].strip()
        if gender not in GENDERS:
            raise ValueError(f"Invalid gender category at CSV line {line}.")
        labels.append(int(label))
        genders.append(gender)
        for name in NUMERIC_FEATURES:
            text = row[name].strip()
            try:
                value = float(text) if text else None
            except ValueError as exc:
                raise ValueError(f"Non-numeric {name} at CSV line {line}.") from exc
            raw_numeric[name].append(value)

    y = np.asarray(labels, dtype=float)
    if fit:
        medians = {
            name: float(np.median([value for value in values if value is not None]))
            for name, values in raw_numeric.items()
        }
        filled = {
            name: np.asarray(
                [medians[name] if value is None else value for value in values],
                dtype=float,
            )
            for name, values in raw_numeric.items()
        }
        means = {name: float(np.mean(values)) for name, values in filled.items()}
        scales = {
            name: float(np.std(values)) or 1.0 for name, values in filled.items()
        }
        preprocessing = {
            "numeric_medians": medians,
            "numeric_means": means,
            "numeric_scales": scales,
        }
    assert preprocessing is not None
    numeric = []
    for name, values in raw_numeric.items():
        filled = np.asarray(
            [preprocessing["numeric_medians"][name] if v is None else v for v in values],
            dtype=float,
        )
        numeric.append(
            (filled - preprocessing["numeric_means"][name])
            / preprocessing["numeric_scales"][name]
        )
    category_columns = [
        np.asarray([1.0 if gender == category else 0.0 for gender in genders])
        for category in GENDERS
    ]
    x = np.column_stack([*numeric, *category_columns])
    return x, y, preprocessing


def _fit(x: np.ndarray, y: np.ndarray, regularization: float = 0.1) -> np.ndarray:
    design = np.column_stack([np.ones(len(x)), x])
    weights = np.zeros(design.shape[1], dtype=float)
    for _ in range(6000):
        logits = np.clip(design @ weights, -30.0, 30.0)
        probabilities = 1.0 / (1.0 + np.exp(-logits))
        gradient = design.T @ (probabilities - y) / len(y)
        gradient[1:] += regularization * weights[1:]
        step = 0.15 / math.sqrt(1.0 + _ / 200.0)
        weights -= step * gradient
    return weights


def _probabilities(x: np.ndarray, weights: np.ndarray) -> np.ndarray:
    logits = np.clip(np.column_stack([np.ones(len(x)), x]) @ weights, -30.0, 30.0)
    return 1.0 / (1.0 + np.exp(-logits))


def _auc(y: np.ndarray, scores: np.ndarray) -> float:
    positives = int(np.sum(y == 1))
    negatives = len(y) - positives
    if positives == 0 or negatives == 0:
        return float("nan")
    order = np.argsort(scores, kind="mergesort")
    ranks = np.empty(len(scores), dtype=float)
    start = 0
    while start < len(order):
        end = start + 1
        while end < len(order) and scores[order[end]] == scores[order[start]]:
            end += 1
        ranks[order[start:end]] = (start + 1 + end) / 2.0
        start = end
    positive_rank_sum = float(np.sum(ranks[y == 1]))
    return (positive_rank_sum - positives * (positives + 1) / 2) / (positives * negatives)


def _metrics(y: np.ndarray, probability: np.ndarray, threshold: float = 0.5) -> dict[str, float | int]:
    predicted = probability >= threshold
    actual = y == 1
    tp = int(np.sum(predicted & actual))
    tn = int(np.sum(~predicted & ~actual))
    fp = int(np.sum(predicted & ~actual))
    fn = int(np.sum(~predicted & actual))
    precision = tp / (tp + fp) if tp + fp else 0.0
    recall = tp / (tp + fn) if tp + fn else 0.0
    specificity = tn / (tn + fp) if tn + fp else 0.0
    return {
        "threshold": threshold,
        "accuracy": (tp + tn) / len(y),
        "precision": precision,
        "recall": recall,
        "specificity": specificity,
        "f1": 2 * precision * recall / (precision + recall) if precision + recall else 0.0,
        "roc_auc": _auc(y, probability),
        "brier_score": float(np.mean((probability - y) ** 2)),
        "true_positive": tp,
        "true_negative": tn,
        "false_positive": fp,
        "false_negative": fn,
    }


def _stratified_splits(y: np.ndarray, folds: int, seed: int) -> list[np.ndarray]:
    random = np.random.default_rng(seed)
    fold_buckets: list[list[int]] = [[] for _ in range(folds)]
    for label in (0, 1):
        indexes = np.flatnonzero(y == label)
        random.shuffle(indexes)
        for bucket_index, chunk in enumerate(np.array_split(indexes, folds)):
            fold_buckets[bucket_index].extend(int(index) for index in chunk)
    return [np.asarray(sorted(bucket), dtype=int) for bucket in fold_buckets]


def _evaluate(rows: list[dict[str, str]]) -> dict[str, Any]:
    y = np.asarray([int(row[TARGET]) for row in rows], dtype=float)
    test_indexes = _stratified_splits(y, folds=5, seed=31)[0]
    train_indexes = np.asarray([i for i in range(len(y)) if i not in set(test_indexes)])
    train_rows = [rows[index] for index in train_indexes]
    test_rows = [rows[index] for index in test_indexes]
    train_x, train_y, preprocessing = _prepare(train_rows, fit=True)
    test_x, test_y, _ = _prepare(test_rows, fit=False, preprocessing=preprocessing)
    holdout = _metrics(test_y, _probabilities(test_x, _fit(train_x, train_y)))

    fold_metrics: list[dict[str, float | int]] = []
    for fold_index, validation_indexes in enumerate(_stratified_splits(y, folds=5, seed=2026)):
        fit_indexes = np.asarray([i for i in range(len(y)) if i not in set(validation_indexes)])
        fit_rows = [rows[index] for index in fit_indexes]
        validation_rows = [rows[index] for index in validation_indexes]
        fit_x, fit_y, fold_preprocessing = _prepare(fit_rows, fit=True)
        validation_x, validation_y, _ = _prepare(
            validation_rows, fit=False, preprocessing=fold_preprocessing
        )
        fold_metrics.append(
            _metrics(validation_y, _probabilities(validation_x, _fit(fit_x, fit_y)))
        )
    cross_validation = {
        key: {
            "mean": statistics.mean(float(fold[key]) for fold in fold_metrics),
            "standard_deviation": statistics.stdev(float(fold[key]) for fold in fold_metrics),
        }
        for key in ("roc_auc", "recall", "specificity", "brier_score")
    }
    return {"holdout_test": holdout, "five_fold_cv": cross_validation}


def train(dataset: Path, output: Path) -> dict[str, Any]:
    rows, digest = _read_csv(dataset)
    evaluation = _evaluate(rows)
    features, labels, preprocessing = _prepare(rows, fit=True)
    weights = _fit(features, labels)
    artifact: dict[str, Any] = {
        "model_type": "medaix_logistic_v1",
        "model_version": "dengue-logistic-v1",
        "trained_at_utc": datetime.now(UTC).isoformat(),
        "dataset_sha256": digest,
        "dataset_rows": len(rows),
        "positive_rows": int(np.sum(labels)),
        "negative_rows": int(np.sum(labels == 0)),
        "numeric_features": list(NUMERIC_FEATURES),
        "gender_categories": list(GENDERS),
        "coefficients": [float(value) for value in weights],
        "numeric_medians": preprocessing["numeric_medians"],
        "numeric_means": preprocessing["numeric_means"],
        "numeric_scales": preprocessing["numeric_scales"],
        "numeric_ranges": {
            name: {
                "minimum": min(float(row[name]) for row in rows if row[name].strip()),
                "maximum": max(float(row[name]) for row in rows if row[name].strip()),
            }
            for name in NUMERIC_FEATURES
        },
        "excluded_features": EXCLUDED,
        "evaluation": evaluation,
        "intended_use": "local research/demo classification; not for patient diagnosis or treatment",
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(artifact, indent=2) + "\n", encoding="utf-8")
    return artifact


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("dataset", type=Path)
    parser.add_argument(
        "--output", type=Path, default=API_DIR / "local_models" / "dengue_screening.json"
    )
    args = parser.parse_args()
    artifact = train(args.dataset, args.output)
    print(f"Rows: {artifact['dataset_rows']}; positive: {artifact['positive_rows']}; negative: {artifact['negative_rows']}")
    print(json.dumps(artifact["evaluation"], indent=2))
    print(f"Local artifact written to: {args.output.resolve()}")
    print("The metrics describe this dataset only; they are not clinical validation.")


if __name__ == "__main__":
    main()
