"""add destination_name to diary_entries

Revision ID: 20260523_04
Revises: 20260515_03
Create Date: 2026-05-23
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect


# revision identifiers, used by Alembic.
revision = "20260523_04"
down_revision = "20260515_03"
branch_labels = None
depends_on = None


def _has_column(table_name: str, column_name: str) -> bool:
    """Check if a column exists in a table (idempotent helper)."""
    bind = op.get_bind()
    inspector = inspect(bind)
    columns = inspector.get_columns(table_name)
    return any(col["name"] == column_name for col in columns)


def upgrade() -> None:
    """Add destination_name column to diary_entries table."""
    if not _has_column("diary_entries", "destination_name"):
        op.add_column(
            "diary_entries",
            sa.Column("destination_name", sa.String(), nullable=True),
        )


def downgrade() -> None:
    """Remove destination_name column from diary_entries table."""
    if _has_column("diary_entries", "destination_name"):
        op.drop_column("diary_entries", "destination_name")
