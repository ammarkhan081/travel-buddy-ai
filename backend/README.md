# Travel Buddy AI - Backend Documentation

## Setup Instructions

### 1. Environment Setup

Create a `.env` file in the project root with the following variables:

```env
# Required
OPENAI_API_KEY=your_openai_api_key_here

# Optional (for enhanced features)
DEEPGRAM_API_KEY=your_deepgram_api_key_here
OPENWEATHER_API_KEY=your_openweather_api_key_here
GOOGLE_MAPS_API_KEY=your_google_maps_api_key_here
NEWS_API_KEY=your_newsapi_key_here

# Firebase (optional)
FIREBASE_CREDENTIALS_PATH=backend/firebase_service_account.json

# Cloud Firebase Admin credentials (prefer one of these instead of a file)
FIREBASE_CREDENTIALS_JSON={"type":"service_account",...}
FIREBASE_CREDENTIALS_BASE64=base64_encoded_service_account_json

# Database
DB_PATH=travel_buddy.db

# Cloud database (leave empty for local SQLite)
DATABASE_URL=postgresql://USER:PASSWORD@HOST:PORT/DATABASE
```

`DB_PATH` relative values are resolved from the `backend/` directory, so
`travel_buddy.db` consistently means `backend/travel_buddy.db` even when the
server is started from the project root.

When `DATABASE_URL` is set, it takes priority over `DB_PATH`. Use this for
cloud deployments so app data is stored in a managed database instead of the
server's local filesystem.

For cloud deployments, prefer `FIREBASE_CREDENTIALS_JSON` or
`FIREBASE_CREDENTIALS_BASE64` instead of uploading
`firebase_service_account.json`.

### 2. Install Dependencies

```bash
pip install -r requirements.txt
python -m spacy download en_core_web_sm
```

### 3. Initialize Database

The database will be automatically initialized on first run. To manually initialize:

```python
from backend.database import Base, engine
Base.metadata.create_all(bind=engine)
```

### 3.1 Schema Migrations (Alembic)

From `backend/`:

```bash
# Install dependencies (includes alembic)
pip install -r requirements.txt

# Existing DB that already contains current schema
alembic -c alembic.ini stamp 20260306_01

# Apply migrations for new/prod environments
alembic -c alembic.ini upgrade head
```

For cloud PostgreSQL, set `DATABASE_URL` first, then run:

```bash
alembic -c backend/alembic.ini upgrade head
```

### 4. Run the Server

```bash
# Development mode with auto-reload (Run from project root)
uvicorn backend.main:app --reload

# Production mode
uvicorn backend.main:app --host 0.0.0.0 --port 8000
```

## API Endpoints

### Reminders
- `GET /api/reminders/`: List all reminders.
- `POST /api/reminders/`: Create manual reminder.
- `POST /api/reminders/voice`: AI extraction from audio.

### Voice Notes
- `GET /api/voice-notes/`: List all notes.
- `POST /api/voice-notes/transcribe`: Whisper STT + Save.

### Travel Diary
- `GET /api/diary/`: List entries.
- `POST /api/diary/auto-generate`: AI summarizing with GPS.

### Expenses
- `GET /api/expenses/`: List expenses.
- `POST /api/expenses/voice`: AI voice extraction.

### Alerts
- `GET /api/alerts/`: Fetch live weather/news/traffic.

## Testing

Run tests with pytest:

```bash
# All tests
pytest tests/ -v

# Specific test file
pytest tests/test_stt.py -v

# With coverage
pytest tests/ -v --cov=fastapi_app --cov-report=html
```

## Docker Deployment

### Build Image
```bash
docker build -t travel-buddy-ai -f Dockerfile .
```

### Run Container
```bash
docker run -p 8000:8000 --env-file ../.env travel-buddy-ai
```

## Development

### Project Structure
```
backend/
├── main.py           # Application entry point
├── routes/           # API endpoints (FastAPI routers)
├── schemas/          # Pydantic models (IO validation)
├── models/           # SQLAlchemy models (Database)
├── services/         # Business logic & AI Processing
└── utils/            # Helper functions
```

### Adding New Endpoints

1. Create schema in `schemas/`
2. Create service in `services/`
3. Create route in `routes/`
4. Register route in `main.py`
5. Add tests in `tests/`

## Troubleshooting

### Common Issues

1. **Import Errors**: Ensure PYTHONPATH includes project root
2. **Database Errors**: For local SQLite, check DB_PATH and file permissions. For cloud deployments, check DATABASE_URL and run Alembic migrations.
3. **API Key Errors**: Verify .env file and API key validity
4. **spaCy Model**: Run `python -m spacy download en_core_web_sm`

## Performance Tips

1. Use async/await for I/O operations
2. Cache AI API responses when possible
3. Batch database operations
4. Use connection pooling for production

## Security Notes

- Never commit `.env` file
- Rotate API keys regularly
- Use environment variables for secrets
- Validate all user inputs
- Implement rate limiting (future)

