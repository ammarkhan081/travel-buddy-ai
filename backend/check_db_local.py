import sqlite3
import os
from pathlib import Path

raw_db_path = os.getenv("DB_PATH", "travel_buddy.db").strip()
if not raw_db_path:
    raw_db_path = "travel_buddy.db"
if raw_db_path.startswith("sqlite:///"):
    raw_db_path = raw_db_path.replace("sqlite:///", "", 1)

db_path = Path(raw_db_path).expanduser()
if not db_path.is_absolute():
    db_path = Path(__file__).resolve().parent / db_path

if not os.path.exists(db_path):
    print(f"Database not found at {db_path}")
    exit(1)

conn = sqlite3.connect(db_path)
cursor = conn.cursor()

try:
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='reminders'")
    table_exists = cursor.fetchone()
    if not table_exists:
        print("Table 'reminders' DOES NOT EXIST")
    else:
        print("Table 'reminders' exists. Schema:")
        cursor.execute("PRAGMA table_info(reminders)")
        columns = cursor.fetchall()
        for col in columns:
            print(col)
except Exception as e:
    print(f"Error: {e}")
finally:
    conn.close()
