import sqlite3
import os
from pathlib import Path


def _resolve_db_path() -> str:
    raw = os.getenv("DB_PATH", "travel_buddy.db").strip()
    if raw.startswith("sqlite:///"):
        return raw.replace("sqlite:///", "", 1)

    path_obj = Path(raw).expanduser()
    if path_obj.is_absolute():
        return str(path_obj)
    return str((Path(__file__).resolve().parent / path_obj).resolve())


def migrate():
    conn = sqlite3.connect(_resolve_db_path())
    cursor = conn.cursor()
    
    print("Running migrations...")
    
    # Add user_id to diary_entries
    try:
        cursor.execute("ALTER TABLE diary_entries ADD COLUMN user_id TEXT")
        print("Added user_id to diary_entries")
    except sqlite3.OperationalError:
        print("user_id already exists in diary_entries")

    # Add user_id to voice_notes
    try:
        cursor.execute("ALTER TABLE voice_notes ADD COLUMN user_id TEXT")
        print("Added user_id to voice_notes")
    except sqlite3.OperationalError:
        print("user_id already exists in voice_notes")
        
    conn.commit()
    conn.close()
    print("Migration complete.")

if __name__ == "__main__":
    migrate()
