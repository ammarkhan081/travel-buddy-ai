# Travel Buddy AI Cloud Deployment Handoff

Last updated: 2026-06-20

## Goal

Deploy the FYP Flutter app and FastAPI backend so the mobile app works from anywhere, without keeping the laptop on.

Target outcome:

- Backend runs on a cloud server.
- Flutter APK/mobile app calls the cloud backend instead of laptop/LAN IP.
- Other users can install/use the app.
- APIs, database-backed features, Firebase auth, AI features, weather/maps/news features continue working when the PC is off.
- Prefer free/student-tier services.

Important free-tier reality:

- Free backend hosting may sleep after inactivity, so first request can be slow.
- Free hosting local filesystem is not reliable for persistent data.
- We moved backend data toward Supabase PostgreSQL instead of relying on SQLite in cloud.

## Project Shape

- `frontend/`: Flutter mobile app.
- `backend/`: FastAPI backend.
- `ai/`: AI inference code used by backend.
- Firebase is used by frontend and backend auth.
- Backend external APIs include OpenAI, Deepgram, OpenWeatherMap, Google Maps, and News API.

Current branch:

```text
codex/cloud-deployment
```

Local backup created before deployment work:

```text
F:\Final Year Project Backups\travel-buddy-pre-cloud-20260620-003553
```

Do not upload/share that backup because it contains local `.env` and database files.

## Completed Steps

### Step 1: Safety Audit

Done.

Checked:

- `.env`
- `backend/.env`
- Firebase service account JSON
- SQLite database files
- Git tracking/history for obvious secrets
- Docker build context risk

Changes:

- Added root `.dockerignore` so Docker/cloud builds exclude secrets, local databases, virtualenvs, build outputs, logs, and Firebase service account JSON.
- Updated `.gitignore` so `.dockerignore` can be tracked and local clutter like `node_modules/` and `.fuse_hidden*` stays ignored.

Important finding:

- Real env files and local DB files are ignored by Git.
- `backend/firebase_service_account.json` exists locally and is ignored.
- Do not commit/upload env files or service account JSON.

### Step 2: Backup/Branch

Done.

Created deployment branch:

```text
codex/cloud-deployment
```

Created local backup:

```text
F:\Final Year Project Backups\travel-buddy-pre-cloud-20260620-003553
```

### Step 3: Feature/API Inventory

Done.

Backend features that must work after deployment:

- Firebase authenticated API access.
- Reminders: manual, voice extraction, list, update, delete.
- Expenses: manual, voice extraction, receipt OCR, list, summary, filter, delete.
- Voice notes: transcribe, save from text, list/search, delete.
- Diary: manual, voice diary, auto-generate, trip diary, update, delete, export PDF/DOCX, summary.
- Alerts: weather, traffic, news, alert history.
- Chat: legacy reply plus saved conversations/messages.
- Trips: create/list/active/update/status/delete.
- Bookings: create/list/cancel, auto-create trip/diary.
- Destination photo proxy: `/api/destination-photo`.
- Secure generated file serving: `/files/{filename}`.
- Health check: `/health`.

Important risk found:

- Flutter `weather_module.dart` calls `/api/weather/`, but backend currently has no `/api/weather/` router. Backend weather logic currently lives under alerts service/routes. This still needs to be fixed before final app testing.

### Step 4: Cloud Database Preparation

Done.

Goal was to support cloud PostgreSQL while keeping local SQLite fallback.

Changes:

- `backend/database.py`
  - Added `DATABASE_URL` support.
  - Keeps SQLite fallback through `DB_PATH`.
  - Normalizes `postgres://` / `postgresql://` to SQLAlchemy psycopg driver URL.
  - SQLite WAL mode now only runs for SQLite.

- `backend/main.py`
  - Made startup schema/index repair dialect-aware.
  - SQLite-only legacy repair no longer runs against PostgreSQL.
  - Index creation only runs when the table/columns exist.

- `backend/requirements.txt`
  - Added `psycopg[binary]>=3.1.18`.

- Added migration:

```text
backend/alembic/versions/20260620_06_add_booking_and_decision_review_tables.py
```

This creates missing fresh-cloud tables:

- `bookings`
- `decision_reviews`

Also adds relevant indexes.

- Fixed PostgreSQL migration portability:

```text
backend/alembic/versions/20260306_01_baseline_schema.py
```

Changed SQLite-style boolean default from `0` to SQLAlchemy boolean false for PostgreSQL compatibility.

Verified:

- Python compile passed.
- Local SQLite fallback still works.
- Focused tests passed.
- Full migration chain worked on temporary SQLite DB.

### Step 5: Supabase PostgreSQL

Done.

Manual work completed:

- Supabase project created.
- Supabase pooler `DATABASE_URL` added to `backend/.env`.

Important:

- Direct Supabase DB URL failed because direct connection host/IP mode was not suitable.
- Switched to Supabase Session Pooler URL.

Migrations ran successfully against Supabase PostgreSQL.

Verified expected tables exist:

- `alert_cache`
- `alembic_version`
- `bookings`
- `chat_conversations`
- `chat_messages`
- `decision_reviews`
- `diary_entries`
- `expenses`
- `rag_embeddings`
- `reminders`
- `trips`
- `voice_notes`

Current Alembic version:

```text
20260620_06
```

### Step 6: Backend Cloud Environment Preparation

Done.

Changes:

- `backend/Dockerfile`
  - Now uses cloud-provided `PORT`, with fallback to `8000`.

```text
uvicorn backend.main:app --host 0.0.0.0 --port ${PORT:-8000}
```

- `backend/auth.py`
  - Added cloud-safe Firebase Admin credential support:
    - `FIREBASE_CREDENTIALS_JSON`
    - `FIREBASE_CREDENTIALS_BASE64`
  - Still supports local `FIREBASE_CREDENTIALS_PATH`.
  - Tightened Firebase init so invalid credential errors are not silently ignored.

- `backend/config.py`
  - Added:
    - `DATABASE_URL`
    - `FIREBASE_CREDENTIALS_JSON`
    - `FIREBASE_CREDENTIALS_BASE64`

- Added:

```text
backend/CLOUD_ENV_CHECKLIST.md
```

This lists cloud environment variables needed for deployment without including secrets.

Verified:

- Python compile passed.
- Local SQLite fallback still works.
- PostgreSQL is selected when `DATABASE_URL` is provided.
- Focused backend tests passed with project venv:

```text
9 passed
```

## Current Important Files

Deployment/security:

- `.dockerignore`
- `.gitignore`
- `.env.example`
- `backend/CLOUD_ENV_CHECKLIST.md`
- `backend/Dockerfile`

Backend cloud/database:

- `backend/database.py`
- `backend/main.py`
- `backend/config.py`
- `backend/auth.py`
- `backend/requirements.txt`
- `backend/alembic/env.py`
- `backend/alembic/versions/20260306_01_baseline_schema.py`
- `backend/alembic/versions/20260620_06_add_booking_and_decision_review_tables.py`

Frontend API base URL:

- `frontend/lib/config/app_config.dart`
- `frontend/lib/services/fastapi_service.dart`

Known frontend/backend mismatch:

- `frontend/lib/screens/modules/weather_module.dart` calls `/api/weather/`.
- Backend currently does not expose `/api/weather/`.

## Current Local Secret State

Do not print or commit these values.

- `backend/.env` contains real `DATABASE_URL`.
- `backend/.env` contains real API keys.
- `backend/firebase_service_account.json` exists locally and is ignored.
- `.env` may contain local secrets too.

These are ignored by Git.

## Remaining Steps

### Step 7: Deploy Backend To Free Cloud Host

Recommended next action.

Need choose a free host. Options:

- Render free web service.
- Koyeb free service.
- Other student/free Docker-capable host.

Backend is Docker-ready. The deploy service must receive env vars from `backend/CLOUD_ENV_CHECKLIST.md`.

Required cloud env vars:

```env
ENVIRONMENT=production
AUTH_BYPASS=false
DATABASE_URL=<Supabase pooler URL>
SECRET_KEY=<long random secret>
OPENAI_API_KEY=<real key>
FIREBASE_CREDENTIALS_JSON=<one-line service account JSON>
```

Required for full demo:

```env
OPENWEATHERMAP_API_KEY=<real key>
GOOGLE_MAPS_API_KEY=<real key>
NEWS_API_KEY=<real key>
DEEPGRAM_API_KEY=<real key>
APP_TIMEZONE=Asia/Karachi
```

Need decide how to safely convert Firebase service account JSON into one-line env var or base64.

Do not upload `firebase_service_account.json` to cloud Git/build.

### Step 8: Test Cloud Backend

After deployment:

- Open cloud URL `/health`.
- Confirm root endpoint.
- Confirm Firebase-protected endpoints reject missing auth.
- Test authenticated calls from app or a Firebase token.
- Test database-backed endpoints.
- Test OpenAI-dependent endpoints.
- Test alerts/weather/maps/news.
- Test file/diary export behavior.

### Step 9: Fix Known Weather Endpoint Mismatch

Before final app testing, either:

- Add backend `/api/weather/` route that returns the shape expected by `weather_module.dart`, or
- Change Flutter Weather module to call existing `/api/alerts/` and map response.

Safer likely option:

- Add a small backend weather router using existing `alert_service.fetch_weather`.
- Register it under `/api/weather`.

### Step 10: Point Flutter App To Cloud Backend

Build APK with:

```bash
flutter build apk --release --dart-define=API_BASE_URL=https://your-cloud-backend-url
```

Relevant frontend config:

```text
frontend/lib/config/app_config.dart
```

### Step 11: Real Mobile Test

Test with laptop backend off.

Use:

- Same Wi-Fi.
- Different Wi-Fi.
- Mobile data.

Verify:

- Signup/login.
- Dashboard.
- Reminders.
- Voice reminder.
- Expenses.
- Voice expense.
- OCR receipt.
- Diary.
- Voice diary.
- Chat.
- Alerts.
- Weather screen.
- Bookings/trips.
- Profile/Firebase Storage features.

### Step 12: App Distribution For FYP

Simplest:

- Share release APK manually through Google Drive/USB/WhatsApp.

Better student-demo options:

- Firebase App Distribution.
- GitHub Release with APK.

Play Store is optional and may require more setup/cost/time.

## Notes For Next Agent

- Do not revert user changes. The worktree has many pre-existing modified/untracked files from the user/project.
- Do not commit or print secrets.
- Use `backend/.env` only locally.
- Use `backend/CLOUD_ENV_CHECKLIST.md` for cloud env setup.
- Use project venv when possible:

```text
F:\Final Year Project\.venv\Scripts\python.exe
```

- System Python is 3.14 and may not have the same Postgres driver support.
- Dockerfile uses Python 3.10 in cloud.
- Supabase DB is already migrated.
- Continue from Step 7.
