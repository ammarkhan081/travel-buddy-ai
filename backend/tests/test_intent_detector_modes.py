"""Regression tests for intent detector mode behavior."""

import asyncio


def test_local_only_without_model_raises(monkeypatch):
    """local_only must fail clearly when local model artifacts are unavailable."""
    from ai.inference.nlp_pipeline.intent_detector import detect_intent_gpt
    from backend.utils.error_policy import IntentError

    monkeypatch.setenv("INTENT_DETECTOR_MODE", "local_only")
    monkeypatch.setenv("INTENT_LOCAL_MODEL_PATH", "nonexistent/path/for/test")

    try:
        asyncio.run(detect_intent_gpt("remind me tomorrow"))
        assert False, "Expected IntentError in local_only mode when model is missing"
    except IntentError as e:
        assert "local_only" in str(e)


def test_local_first_low_confidence_falls_back_to_openai_mock(monkeypatch):
    """low-confidence local prediction should fallback to OpenAI path in local_first mode."""
    from ai.inference.nlp_pipeline import intent_detector

    monkeypatch.setenv("INTENT_DETECTOR_MODE", "local_first")
    monkeypatch.setenv("INTENT_LOCAL_MIN_CONF", "0.95")
    monkeypatch.setenv("MOCK_MODE", "true")

    monkeypatch.setattr(
        intent_detector,
        "_detect_intent_local_model",
        lambda text: {
            "intent": "note",
            "title": "local note",
            "scheduled_time": None,
            "location": None,
            "priority": "medium",
            "confidence": 0.2,
            "entities": {},
            "model_used": "local_intent_model",
        },
    )

    result = asyncio.run(intent_detector.detect_intent_gpt("remind me tomorrow at 10"))
    assert result["intent"] == "reminder"
    # Mock path does not set model_used, so this proves fallback away from local path.
    assert result.get("model_used") != "local_intent_model"


def test_local_first_high_confidence_uses_local(monkeypatch):
    """high-confidence local prediction should be accepted in local_first mode."""
    from ai.inference.nlp_pipeline import intent_detector

    monkeypatch.setenv("INTENT_DETECTOR_MODE", "local_first")
    monkeypatch.setenv("INTENT_LOCAL_MIN_CONF", "0.7")
    monkeypatch.setenv("MOCK_MODE", "true")

    monkeypatch.setattr(
        intent_detector,
        "_detect_intent_local_model",
        lambda text: {
            "intent": "expense",
            "title": "local expense",
            "scheduled_time": None,
            "location": None,
            "priority": "medium",
            "confidence": 0.99,
            "entities": {},
            "model_used": "local_intent_model",
        },
    )

    result = asyncio.run(intent_detector.detect_intent_gpt("i spent 20 dollars"))
    assert result["intent"] == "expense"
    assert result.get("model_used") == "local_intent_model"
