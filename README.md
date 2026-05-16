# Travel Buddy AI: Context-Aware Travel Companion

**AI Specialist & Backend Developer:** Ammar Ayaz (22PWBCS0950)

A comprehensive AI-driven system that powers intelligent travel features including speech-to-text transcription, intent detection, expense tracking, travel diary generation, and context-aware alerts.

## 🎯 Features

- **AI-Powered Reminders**: Intent and time detection using GPT-4.
- **Smart Voice Notes**: High-accuracy transcription with Whisper API.
- **Hybrid Travel Diary**: Automated summarization combining reminders, notes, and expenses.
- **Expense Tracker**: Automatic extraction of amounts and categories from voice.
- **Context-Aware Alerts**: Real-time weather, traffic, and news updates.

## 🚀 Quick Start

### Prerequisites

- Python 3.10+
- Flutter SDK (Latest)
- API Keys (OpenAI required for STT and LLM features)

### Installation & Run

1. **Backend Setup**:
   ```bash
   cd backend
   pip install -r requirements.txt
   python -m spacy download en_core_web_sm
   # Run server (from project root)
   uvicorn backend.main:app --reload
   ```

2. **Frontend Setup**:
   ```bash
   cd frontend
   flutter pub get
   flutter run
   ```

## 📁 Project Structure

```
Travel Buddy AI/
├── backend/                     # FastAPI REST API (SQLAlchemy, OpenAI)
├── frontend/                    # Primary Flutter App (Provider state management)
├── ai/                          # AI Inference pipelines (used by Backend)
├── docs/                        # Project documentation
├── .env                         # Environment variables
└── README.md
```

- **backend**: Handles API, storage in SQLite, and Firebase Authentication verification.
- **frontend**: The official frontend of the system.
- **ai**: Contains the core logic for expense extraction and LLM interaction.

## 📊 Performance Targets

| Module | Metric | Target |
|--------|--------|--------|
| STT | Word Error Rate | ≤ 10% |
| Intent Detection | Accuracy | ≥ 90% |

## 🛠️ Tech Stack

- **Backend**: FastAPI (Python 3.10+)
- **Frontend**: Flutter (Mobile/Web)
- **Database**: SQLite (local) + Firebase Firestore (cloud)
- **AI/NLP**: OpenAI GPT-4 / Whisper API

---
**Author:** Ammar Ayaz (22PWBCS0950)
Final Year Project
