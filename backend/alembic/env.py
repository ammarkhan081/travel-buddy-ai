from __future__ import annotations

import os
from logging.config import fileConfig
from pathlib import Path

from alembic import context
from sqlalchemy import engine_from_config, pool

if context.config.config_file_name is not None:
    fileConfig(context.config.config_file_name)

# Ensure imports resolve when running from backend/
ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in os.sys.path:
    os.sys.path.insert(0, str(ROOT))

from backend.database import Base, SQLALCHEMY_DATABASE_URL  # noqa: E402
from backend import models  # noqa: F401,E402

target_metadata = Base.metadata


def _db_url() -> str:
    return SQLALCHEMY_DATABASE_URL


def run_migrations_offline() -> None:
    url = _db_url()
    context.configure(
        url=url,
        target_metadata=target_metadata,
        literal_binds=True,
        compare_type=True,
        compare_server_default=True,
    )

    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    config_section = context.config.get_section(context.config.config_ini_section) or {}
    config_section["sqlalchemy.url"] = _db_url()
    connectable = engine_from_config(
        config_section,
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )

    with connectable.connect() as connection:
        context.configure(
            connection=connection,
            target_metadata=target_metadata,
            compare_type=True,
            compare_server_default=True,
        )

        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
