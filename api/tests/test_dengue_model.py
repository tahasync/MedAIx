import csv
import json
import tempfile
from pathlib import Path

import pytest

from dengue_model import (
    DengueModelUnavailable,
    load_model,
    out_of_training_range,
    predict_probability,
    screening_enabled,
)
from scripts.train_dengue_model import train


def _dataset(path):
    fields = [
        "age",
        "gender",
        "hemoglobin_g_dl",
        "wbc_count",
        "differential_count",
        "rbc_count",
        "platelet_count",
        "platelet_distribution_width",
        "dengue_label",
    ]
    with path.open("w", newline="", encoding="utf-8") as file:
        writer = csv.DictWriter(file, fieldnames=fields)
        writer.writeheader()
        for index in range(50):
            positive = index % 2
            writer.writerow(
                {
                    "age": 25 + index,
                    "gender": ("Female", "Male", "Child")[index % 3],
                    "hemoglobin_g_dl": 13.0 + positive,
                    "wbc_count": 3000 + 4000 * (1 - positive),
                    "differential_count": 1,
                    "rbc_count": 1,
                    "platelet_count": 60000 + 150000 * (1 - positive),
                    "platelet_distribution_width": 17 + 2 * positive,
                    "dengue_label": positive,
                }
            )


def test_train_holdout_and_cross_validation_without_storing_rows() -> None:
    with tempfile.TemporaryDirectory(
        prefix=".dengue-model-test-", dir=Path(__file__).resolve().parent
    ) as temporary:
        tmp_path = Path(temporary)
        dataset = tmp_path / "sample.csv"
        artifact_path = tmp_path / "model.json"
        _dataset(dataset)

        artifact = train(dataset, artifact_path)

        assert artifact["dataset_rows"] == 50
        assert "holdout_test" in artifact["evaluation"]
        assert len(artifact["evaluation"]["five_fold_cv"]) == 4
        saved = json.loads(artifact_path.read_text(encoding="utf-8"))
        assert "rows" not in saved
        assert saved["excluded_features"]["rbc_count"]
        payload = {
            "age": 35,
            "gender": "Female",
            "hemoglobin_g_dl": 13.5,
            "wbc_count": 5000,
            "platelet_count": 120000,
            "platelet_distribution_width": 18,
        }
        score = predict_probability(payload, saved)
        assert 0.0 <= score <= 1.0
        assert out_of_training_range({**payload, "age": 200}, saved) == ["age"]


def test_model_is_disabled_by_default_and_requires_explicit_opt_in(
    monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.delenv("MEDAIX_DENGUE_SCREENING_ENABLED", raising=False)

    assert not screening_enabled()
    with pytest.raises(DengueModelUnavailable, match="disabled"):
        load_model(Path(__file__).with_name("missing-model.json"))
