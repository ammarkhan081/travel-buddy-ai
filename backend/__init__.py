"""
Backend package initializer.
Ensures the project root is in sys.path so the `ai/` package
is always importable, regardless of which directory uvicorn is called from.
"""
import sys
from pathlib import Path

_PROJECT_ROOT = Path(__file__).resolve().parent.parent
if str(_PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(_PROJECT_ROOT))
