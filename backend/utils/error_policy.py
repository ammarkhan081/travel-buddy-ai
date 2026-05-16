"""Centralized typed errors for deterministic failure handling."""


class AppError(Exception):
    code = "app_error"

    def __init__(self, message: str):
        super().__init__(message)
        self.message = message


class STTError(AppError):
    code = "stt_error"


class IntentError(AppError):
    code = "intent_error"


class ExtractionError(AppError):
    code = "extraction_error"


class RetrievalError(AppError):
    code = "retrieval_error"


class ChatError(AppError):
    code = "chat_error"
