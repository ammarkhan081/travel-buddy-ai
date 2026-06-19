"""add trips table and per-trip scoping columns

Revision ID: 20260606_05
Revises: 20260523_04
Create Date: 2026-06-06
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect


# revision identifiers, used by Alembic.
revision = "20260606_05"
down_revision = "20260523_04"
branch_labels = None
depends_on = None


def _has_table(table_name: str) -> bool:
    bind = op.get_bind()
    inspector = inspect(bind)
    return table_name in inspector.get_table_names()


def _has_column(table_name: str, column_name: str) -> bool:
    bind = op.get_bind()
    inspector = inspect(bind)
    if table_name not in inspector.get_table_names():
        return False
    return any(col["name"] == column_name for col in inspector.get_columns(table_name))


def upgrade() -> None:
    # 1. trips table
    if not _has_table("trips"):
        op.create_table(
            "trips",
            sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
            sa.Column("user_id", sa.String(), nullable=False),
            sa.Column("destination", sa.String(), nullable=False),
            sa.Column("origin", sa.String(), nullable=True),
            sa.Column("start_date", sa.String(), nullable=False),
            sa.Column("end_date", sa.String(), nullable=True),
            sa.Column("status", sa.String(), nullable=False, server_default="active"),
            sa.Column("transport", sa.String(), nullable=True),
            sa.Column("notes", sa.Text(), nullable=True),
            sa.Column("booking_id", sa.Integer(), nullable=True),
            sa.Column("created_at", sa.String(), nullable=False),
            sa.Column("updated_at", sa.String(), nullable=False),
        )
        op.create_index("ix_trips_user_id", "trips", ["user_id"])
        op.create_index("ix_trips_status", "trips", ["status"])
        op.create_index("ix_trips_start_date", "trips", ["start_date"])

    # 2. per-trip scoping columns on existing tables
    def add_col(table: str, column: str, col_type) -> None:
        if _has_table(table) and not _has_column(table, column):
            op.add_column(table, sa.Column(column, col_type, nullable=True))

    add_col("expenses", "trip_id", sa.Integer())
    add_col("expenses", "location", sa.String())
    add_col("expenses", "merchant", sa.String())
    add_col("reminders", "trip_id", sa.Integer())
    add_col("voice_notes", "trip_id", sa.Integer())
    add_col("voice_notes", "location", sa.String())
    add_col("diary_entries", "trip_id", sa.Integer())
    add_col("bookings", "trip_id", sa.Integer())


def downgrade() -> None:
    for table, column in [
        ("bookings", "trip_id"),
        ("diary_entries", "trip_id"),
        ("voice_notes", "location"),
        ("voice_notes", "trip_id"),
        ("reminders", "trip_id"),
        ("expenses", "merchant"),
        ("expenses", "location"),
        ("expenses", "trip_id"),
    ]:
        if _has_column(table, column):
            op.drop_column(table, column)
    if _has_table("trips"):
        op.drop_table("trips")
