import os
from pathlib import Path
from sqlalchemy import create_engine, event
from sqlalchemy.orm import declarative_base, sessionmaker


BACKEND_DIR = Path(__file__).resolve().parent


def _sqlite_url_from_path(raw_path: str) -> str:
    path_obj = Path(raw_path).expanduser()
    if not path_obj.is_absolute():
        path_obj = BACKEND_DIR / path_obj
    return f"sqlite:///{path_obj.resolve().as_posix()}"


def _build_sqlite_url() -> str:
    db_path = os.getenv("DB_PATH", "travel_buddy.db").strip()
    if not db_path:
        db_path = "travel_buddy.db"
    if db_path.startswith("sqlite:///"):
        raw_path = db_path.replace("sqlite:///", "", 1)
        return _sqlite_url_from_path(raw_path)

    return _sqlite_url_from_path(db_path)


def _normalize_database_url(raw_url: str) -> str:
    """Return a SQLAlchemy URL suitable for the installed cloud DB driver."""
    url = raw_url.strip()
    if url.startswith("postgres://"):
        url = "postgresql://" + url[len("postgres://"):]
    if url.startswith("postgresql://"):
        url = "postgresql+psycopg://" + url[len("postgresql://"):]
    return url


def _build_database_url() -> str:
    database_url = os.getenv("DATABASE_URL", "").strip()
    if database_url:
        return _normalize_database_url(database_url)
    return _build_sqlite_url()


def _connect_args_for_url(database_url: str) -> dict:
    drivername = database_url.split("://", 1)[0]
    if drivername.startswith("sqlite"):
        return {"check_same_thread": False}
    return {}


SQLALCHEMY_DATABASE_URL = _build_database_url()

engine = create_engine(
    SQLALCHEMY_DATABASE_URL,
    connect_args=_connect_args_for_url(SQLALCHEMY_DATABASE_URL),
    pool_pre_ping=True,
)

if engine.dialect.name == "sqlite":
    # L-6: Enable WAL mode for better concurrent read/write performance.
    @event.listens_for(engine, "connect")
    def _set_wal_mode(dbapi_conn, _connection_record):
        dbapi_conn.execute("PRAGMA journal_mode=WAL")


SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base = declarative_base()

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
