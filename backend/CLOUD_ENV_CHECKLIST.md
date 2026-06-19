# Cloud Environment Checklist

Use this checklist when creating the backend service in a cloud host. Do not
commit real values to Git.

## Required

```env
ENVIRONMENT=production
AUTH_BYPASS=false
DATABASE_URL=postgresql://...
SECRET_KEY=<long-random-secret>
OPENAI_API_KEY=sk-...
FIREBASE_CREDENTIALS_JSON=<one-line-service-account-json>
```

## Required For Full Feature Demo

```env
OPENWEATHERMAP_API_KEY=...
GOOGLE_MAPS_API_KEY=...
NEWS_API_KEY=...
DEEPGRAM_API_KEY=...
```

## Recommended

```env
APP_TIMEZONE=Asia/Karachi
OPENAI_MODEL=gpt-4o-mini
OPENAI_EMBEDDING_MODEL=text-embedding-3-small
WHISPER_MODEL=whisper-1
MAX_AUDIO_DURATION=300
DIARY_FILES_DIR=diary_files
```

## Set After Backend URL Is Known

For a mobile app that calls only APIs with bearer tokens, CORS is less critical
than for web, but the backend requires explicit origins in production.

```env
ALLOWED_ORIGINS=https://travel-buddy-ai-backend.onrender.com
```

If the cloud host gives a different URL, update this value to match the final
backend URL.

## Do Not Set In Cloud

```env
DB_PATH=travel_buddy.db
FIREBASE_CREDENTIALS_PATH=backend/firebase_service_account.json
```

SQLite files and local Firebase JSON files are for laptop development only.
