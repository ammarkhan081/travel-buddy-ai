"""Shared OpenAI runtime helpers: retries, fallback model chain, and structured logs."""

import logging
import time
from typing import Callable, Iterable, List, Tuple, TypeVar

import openai

try:
    from ..config import settings
except ImportError:
    from config import settings

logger = logging.getLogger(__name__)
T = TypeVar("T")


def get_model_chain(primary: str | None = None) -> List[str]:
    first = (primary or settings.OPENAI_MODEL or "").strip()
    fallbacks = [m.strip() for m in settings.OPENAI_MODEL_FALLBACKS.split(",") if m.strip()]
    chain: List[str] = []
    for m in [first] + fallbacks:
        if m and m not in chain:
            chain.append(m)
    return chain or ["gpt-4o-mini"]


def is_rate_limit_error(exc: Exception) -> bool:
    text = str(exc).lower()
    if "429" in text or "rate limit" in text or "too many requests" in text:
        return True
    return isinstance(exc, getattr(openai, "RateLimitError", tuple()))


def call_with_retries(label: str, fn: Callable[[], T]) -> T:
    max_retries = max(0, settings.OPENAI_MAX_RETRIES)
    delay = 1.0
    last_exc: Exception | None = None
    for attempt in range(max_retries + 1):
        try:
            return fn()
        except Exception as exc:
            last_exc = exc
            if attempt >= max_retries or not is_rate_limit_error(exc):
                raise
            logger.warning(
                "openai_retry",
                extra={
                    "event": "openai_retry",
                    "label": label,
                    "attempt": attempt + 1,
                    "wait_seconds": delay,
                },
            )
            time.sleep(delay)
            delay = min(delay * 2, 8.0)
    assert last_exc is not None
    raise last_exc


def call_chat_with_fallback(
    client: openai.OpenAI,
    messages: list,
    temperature: float,
    response_format: dict | None = None,
    primary_model: str | None = None,
    label: str = "chat",
) -> Tuple[str, str]:
    """
    Returns (content, model_used). Tries model fallback chain deterministically.
    """
    last_exc: Exception | None = None
    for model in get_model_chain(primary_model):
        try:
            def _run():
                kwargs = {
                    "model": model,
                    "messages": messages,
                    "temperature": temperature,
                }
                if response_format is not None:
                    kwargs["response_format"] = response_format
                return client.chat.completions.create(**kwargs)

            resp = call_with_retries(f"{label}:{model}", _run)
            content = resp.choices[0].message.content
            if not content:
                raise RuntimeError(f"Empty response from model {model}")
            logger.info(
                "model_used",
                extra={"event": "model_used", "label": label, "model": model},
            )
            return content, model
        except Exception as exc:
            last_exc = exc
            logger.warning(
                "model_fallback",
                extra={
                    "event": "model_fallback",
                    "label": label,
                    "failed_model": model,
                    "error": str(exc),
                },
            )
    assert last_exc is not None
    raise last_exc
