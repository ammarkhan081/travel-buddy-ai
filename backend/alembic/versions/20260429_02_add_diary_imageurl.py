"""add diary imageUrl column

Revision ID: 20260429_02
Revises: 20260306_01
Create Date: 2026-04-29
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect


# revision identifiers, used by Alembic.
revision = "20260429_02"
down_revision = "20260306_01"
branch_labels = None
depends_on = None


def _has_column(table_name: str, column_name: str) -> bool:
    """Check if a column exists in a table."""
    bind = op.get_bind()
    inspector = inspect(bind)
    columns = inspector.get_columns(table_name)
    return any(col["name"] == column_name for col in columns)


def upgrade() -> None:
    """Add imageUrl column to diary_entries table."""
    # Only add if column doesn't exist (idempotent)
    if not _has_column("diary_entries", "imageUrl"):
        op.add_column(
            "diary_entries",
            sa.Column("imageUrl", sa.String(), nullable=True)
        )


def downgrade() -> None:
    """Remove imageUrl column from diary_entries table."""
    # Only drop if column exists (idempotent)
    if _has_column("diary_entries", "imageUrl"):
        op.drop_column("diary_entries", "imageUrl")
