"""Configuration management."""

import os
from typing import Optional
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()


class Settings:
    """Application settings."""
    # API Keys
    OPENAI_API_KEY: str = os.getenv("OPENAI_API_KEY", "")
    DEEPGRAM_API_KEY: str = os.getenv("DEEPGRAM_API_KEY", "")
    OPENWEATHERMAP_API_KEY: str = os.getenv("OPENWEATHERMAP_API_KEY", "") or os.getenv("OPENWEATHER_API_KEY", "")
    GOOGLE_MAPS_API_KEY: str = os.getenv("GOOGLE_MAPS_API_KEY", "")
    NEWS_API_KEY: str = os.getenv("NEWS_API_KEY", "")
    SECRET_KEY: str = os.getenv("SECRET_KEY", "your_random_secret_key_here")
    
    # Firebase
    FIREBASE_CREDENTIALS_PATH: Optional[str] = os.getenv("FIREBASE_CREDENTIALS_PATH", "")
    
    # Database
    DB_PATH: str = os.getenv("DB_PATH", "travel_buddy.db")
    
    # API Settings
    OPENAI_MODEL: str = os.getenv("OPENAI_MODEL", "gpt-3.5-turbo")
    OPENAI_MODEL_FALLBACKS: str = os.getenv("OPENAI_MODEL_FALLBACKS", "gpt-4o-mini,gpt-4.1-mini,gpt-3.5-turbo")
    OPENAI_EMBEDDING_MODEL: str = os.getenv("OPENAI_EMBEDDING_MODEL", "text-embedding-3-small")
    WHISPER_MODEL: str = os.getenv("WHISPER_MODEL", "whisper-1")
    APP_TIMEZONE: str = os.getenv("APP_TIMEZONE", "UTC")
    CHAT_MAX_HISTORY_MESSAGES: int = int(os.getenv("CHAT_MAX_HISTORY_MESSAGES", "20"))
    CHAT_MAX_CONTEXT_CHARS: int = int(os.getenv("CHAT_MAX_CONTEXT_CHARS", "2800"))
    RAG_SIMILARITY_THRESHOLD: float = float(os.getenv("RAG_SIMILARITY_THRESHOLD", "0.30"))
    OPENAI_MAX_RETRIES: int = int(os.getenv("OPENAI_MAX_RETRIES", "3"))
    
    # Performance
    MAX_AUDIO_DURATION: int = int(os.getenv("MAX_AUDIO_DURATION", "300"))  # 5 minutes

    def validate(self):
        """Warn (not crash) if critical settings are missing."""
        import logging
        _logger = logging.getLogger(__name__)
        if not self.OPENAI_API_KEY or self.OPENAI_API_KEY in ("your_openai_api_key_here", "YOUR_OPENAI_KEY", ""):
            _logger.warning(
                "WARNING: OPENAI_API_KEY is missing or placeholder. "
                "AI features (transcription, intent detection) will not work until it is set in backend/.env"
            )


settings = Settings()
settings.validate()

