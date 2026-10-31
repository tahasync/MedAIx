from __future__ import annotations

import csv
import tempfile
from pathlib import Path

from anemia_model import NUMERIC_FEATURES, predict_probability, screening_enabled
from scripts.train_anemia_model import train


def test_training_writes_artifact_without_source_rows() -> None:
    with tempfile.TemporaryDirectory(prefix=".anemia-model-test-", dir=Path(__file__).parent) as folder:
        root = Path(folder)
        dataset = root / "sample.csv"
        output = root / "model.json"
        fields = ["Gender", "Hemoglobin", "MCH", "MCHC", "MCV", "Result"]
        with dataset.open("w", newline="", encoding="utf-8") as source:
            writer = csv.DictWriter(source, fieldnames=fields)
            writer.writeheader()
            for index in range(60):
                low_hgb = index % 2 == 1
                writer.writerow({
                    "Gender": index % 2,
                    "Hemoglobin": 8.0 if low_hgb else 14.0,
                    "MCH": 20.0 if low_hgb else 28.0,
                    "MCHC": 28.0 if low_hgb else 32.0,
                    "MCV": 72.0 if low_hgb else 90.0,
                    "Result": int(low_hgb),
                })

        artifact = train(dataset, output)
        assert artifact["dataset_rows"] == 60
        assert artifact["evaluation"]["stratified_holdout"]["roc_auc"] >= 0.9
        serialized = output.read_text(encoding="utf-8")
        assert "source_rows" not in serialized
        assert "Gender" in artifact["excluded_features"]

        probability = predict_probability(
            {"hemoglobin": 8.0, "mch": 20.0, "mchc": 28.0, "mcv": 72.0},
            artifact,
        )
        assert probability > 0.5


def test_screening_is_disabled_by_default(monkeypatch) -> None:
    monkeypatch.delenv("MEDAIX_ANEMIA_SCREENING_ENABLED", raising=False)
    assert not screening_enabled()
