"""add booking and decision review tables

Revision ID: 20260620_06
Revises: 20260606_05
Create Date: 2026-06-20
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect


# revision identifiers, used by Alembic.
revision = "20260620_06"
down_revision = "20260606_05"
branch_labels = None
depends_on = None


def _inspector():
    return inspect(op.get_bind())


def _has_table(table_name: str) -> bool:
    return _inspector().has_table(table_name)


def _has_column(table_name: str, column_name: str) -> bool:
    if not _has_table(table_name):
        return False
    return any(col["name"] == column_name for col in _inspector().get_columns(table_name))


def _has_index(table_name: str, index_name: str) -> bool:
    if not _has_table(table_name):
        return False
    return any(idx.get("name") == index_name for idx in _inspector().get_indexes(table_name))


def _create_index_if_possible(index_name: str, table_name: str, columns: list[str]) -> None:
    if not _has_table(table_name) or _has_index(table_name, index_name):
        return
    if all(_has_column(table_name, col) for col in columns):
        op.create_index(index_name, table_name, columns)


def upgrade() -> None:
    if not _has_table("bookings"):
        op.create_table(
            "bookings",
            sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
            sa.Column("user_id", sa.String(), nullable=False),
            sa.Column("destination_name", sa.String(), nullable=False),
            sa.Column("agency_id", sa.String(), nullable=False),
            sa.Column("agency_name", sa.String(), nullable=False),
            sa.Column("travel_date", sa.String(), nullable=False),
            sa.Column("return_date", sa.String(), nullable=True),
            sa.Column("num_people", sa.Integer(), nullable=False, server_default="1"),
            sa.Column("user_phone", sa.String(), nullable=False),
            sa.Column("user_name", sa.String(), nullable=False),
            sa.Column("user_email", sa.String(), nullable=True),
            sa.Column("special_requests", sa.String(), nullable=True),
            sa.Column("status", sa.String(), nullable=False, server_default="Completed"),
            sa.Column("trip_id", sa.Integer(), nullable=True),
            sa.Column("created_at", sa.String(), nullable=False),
        )

    if not _has_table("decision_reviews"):
        op.create_table(
            "decision_reviews",
            sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
            sa.Column("user_id", sa.String(), nullable=False),
            sa.Column("transcript", sa.String(), nullable=False),
            sa.Column("intent", sa.String(), nullable=False),
            sa.Column("source_action", sa.String(), nullable=False),
            sa.Column("suggested_payload", sa.String(), nullable=True),
            sa.Column("status", sa.String(), nullable=False, server_default="pending"),
            sa.Column("resolution_payload", sa.String(), nullable=True),
            sa.Column("created_at", sa.String(), nullable=False),
            sa.Column("resolved_at", sa.String(), nullable=True),
        )

    for index_name, table_name, columns in [
        ("ix_bookings_user_id", "bookings", ["user_id"]),
        ("ix_bookings_trip_id", "bookings", ["trip_id"]),
        ("ix_decision_reviews_user_id", "decision_reviews", ["user_id"]),
        ("ix_alert_cache_user_id", "alert_cache", ["user_id"]),
        ("ix_reminders_user_id", "reminders", ["user_id"]),
        ("ix_expenses_user_id", "expenses", ["user_id"]),
        ("ix_diary_entries_user_id", "diary_entries", ["user_id"]),
        ("ix_voice_notes_user_id", "voice_notes", ["user_id"]),
        ("ix_expenses_trip_id", "expenses", ["trip_id"]),
        ("ix_reminders_trip_id", "reminders", ["trip_id"]),
        ("ix_voice_notes_trip_id", "voice_notes", ["trip_id"]),
        ("ix_diary_entries_trip_id", "diary_entries", ["trip_id"]),
    ]:
        _create_index_if_possible(index_name, table_name, columns)


def downgrade() -> None:
    for index_name, table_name in [
        ("ix_diary_entries_trip_id", "diary_entries"),
        ("ix_voice_notes_trip_id", "voice_notes"),
        ("ix_reminders_trip_id", "reminders"),
        ("ix_expenses_trip_id", "expenses"),
        ("ix_voice_notes_user_id", "voice_notes"),
        ("ix_diary_entries_user_id", "diary_entries"),
        ("ix_expenses_user_id", "expenses"),
        ("ix_reminders_user_id", "reminders"),
        ("ix_alert_cache_user_id", "alert_cache"),
        ("ix_decision_reviews_user_id", "decision_reviews"),
        ("ix_bookings_trip_id", "bookings"),
        ("ix_bookings_user_id", "bookings"),
    ]:
        if _has_index(table_name, index_name):
            op.drop_index(index_name, table_name=table_name)

    if _has_table("decision_reviews"):
        op.drop_table("decision_reviews")
    if _has_table("bookings"):
        op.drop_table("bookings")
