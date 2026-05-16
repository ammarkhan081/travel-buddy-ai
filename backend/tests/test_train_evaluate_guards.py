"""Isolated guard tests for ai.training.train.evaluate_model."""

import json
import types


def _install_fake_ml_modules(monkeypatch):
    """Install fake transformers and sklearn modules for isolated evaluation tests."""

    class _FakePred:
        def __init__(self, pred):
            self._pred = pred

        def tolist(self):
            return [self._pred]

    class _FakeLogits:
        def __init__(self, pred):
            self._pred = pred

        def argmax(self, dim=-1):
            return _FakePred(self._pred)

    class _FakeModel:
        @classmethod
        def from_pretrained(cls, _path):
            return cls()

        def __call__(self, **_kwargs):
            return types.SimpleNamespace(logits=_FakeLogits(0))

    class _FakeTokenizer:
        @classmethod
        def from_pretrained(cls, _path):
            return cls()

        def __call__(self, texts, **_kwargs):
            return {"input_ids": [[1] for _ in texts], "attention_mask": [[1] for _ in texts]}

    fake_transformers = types.SimpleNamespace(
        AutoTokenizer=_FakeTokenizer,
        AutoModelForSequenceClassification=_FakeModel,
    )
    fake_metrics = types.SimpleNamespace(
        accuracy_score=lambda y_true, y_pred: 1.0 if y_true == y_pred else 0.0,
        precision_recall_fscore_support=lambda y_true, y_pred, average=None: (1.0, 1.0, 1.0, None),
    )

    monkeypatch.setitem(__import__("sys").modules, "transformers", fake_transformers)
    monkeypatch.setitem(__import__("sys").modules, "sklearn", types.SimpleNamespace(metrics=fake_metrics))
    monkeypatch.setitem(__import__("sys").modules, "sklearn.metrics", fake_metrics)


def test_evaluate_model_raises_on_all_unknown_labels(tmp_path, monkeypatch):
    """If no test labels match label_map.json, evaluate_model should fail clearly."""
    from ai.training.train import evaluate_model

    _install_fake_ml_modules(monkeypatch)

    model_dir = tmp_path / "intent_model"
    model_dir.mkdir(parents=True)
    with (model_dir / "label_map.json").open("w", encoding="utf-8") as f:
        json.dump({"label_to_id": {"reminder": 0}, "id_to_label": {"0": "reminder"}}, f)

    test_rows = [{"text": "I spent money", "label": "expense"}]
    result = evaluate_model(str(model_dir), test_rows)
    assert result == {}


def test_evaluate_model_reports_dropped_unknown_labels(tmp_path, monkeypatch):
    """Evaluation should report dropped unknown labels and used sample count."""
    from ai.training.train import evaluate_model

    _install_fake_ml_modules(monkeypatch)

    model_dir = tmp_path / "intent_model"
    model_dir.mkdir(parents=True)
    with (model_dir / "label_map.json").open("w", encoding="utf-8") as f:
        json.dump(
            {
                "label_to_id": {"reminder": 0, "expense": 1},
                "id_to_label": {"0": "reminder", "1": "expense"},
            },
            f,
        )

    test_rows = [
        {"text": "remind me tomorrow", "label": "reminder"},
        {"text": "unknown class sample", "label": "unseen_label"},
    ]
    result = evaluate_model(str(model_dir), test_rows)

    assert result.get("samples_used") == 1
    assert result.get("samples_dropped_unknown_label") == 1
