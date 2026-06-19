"""baseline schema

Revision ID: 20260306_01
Revises:
Create Date: 2026-03-06
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect


# revision identifiers, used by Alembic.
revision = "20260306_01"
down_revision = None
branch_labels = None
depends_on = None


def _has_table(table_name: str) -> bool:
    bind = op.get_bind()
    return inspect(bind).has_table(table_name)


def _has_index(table_name: str, index_name: str) -> bool:
    bind = op.get_bind()
    idxs = inspect(bind).get_indexes(table_name)
    return any(i.get("name") == index_name for i in idxs)


def upgrade() -> None:
    if not _has_table("alert_cache"):
        op.create_table(
            "alert_cache",
            sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
            sa.Column("type", sa.String(), nullable=False),
            sa.Column("message", sa.String(), nullable=False),
            sa.Column("severity", sa.String(), nullable=False),
            sa.Column("location", sa.String(), nullable=True),
            sa.Column("created_at", sa.String(), nullable=False),
        )

    if not _has_table("diary_entries"):
        op.create_table(
            "diary_entries",
            sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
            sa.Column("user_id", sa.String(), nullable=False),
            sa.Column("title", sa.String(), nullable=False),
            sa.Column("content", sa.String(), nullable=False),
            sa.Column("location", sa.String(), nullable=True),
            sa.Column("timestamp", sa.String(), nullable=False),
            sa.Column("is_auto_generated", sa.Boolean(), nullable=False, server_default=sa.false()),
        )

    if not _has_table("expenses"):
        op.create_table(
            "expenses",
            sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
            sa.Column("amount", sa.Float(), nullable=False),
            sa.Column("category", sa.String(), nullable=False),
            sa.Column("description", sa.String(), nullable=True),
            sa.Column("date", sa.String(), nullable=False),
            sa.Column("intent", sa.String(), nullable=True),
            sa.Column("user_id", sa.String(), nullable=False),
            sa.Column("created_at", sa.String(), nullable=True),
        )

    if not _has_table("rag_embeddings"):
        op.create_table(
            "rag_embeddings",
            sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
            sa.Column("user_id", sa.String(), nullable=False),
            sa.Column("source_type", sa.String(), nullable=False),
            sa.Column("source_id", sa.Integer(), nullable=False),
            sa.Column("chunk_index", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("chunk_hash", sa.String(), nullable=False),
            sa.Column("chunk_text", sa.Text(), nullable=False),
            sa.Column("embedding_json", sa.Text(), nullable=False),
            sa.Column("updated_at", sa.String(), nullable=False),
        )
        op.create_index("ix_rag_embeddings_user_id", "rag_embeddings", ["user_id"])
        op.create_index("ix_rag_embeddings_chunk_hash", "rag_embeddings", ["chunk_hash"])
    else:
        if not _has_index("rag_embeddings", "ix_rag_embeddings_user_id"):
            op.create_index("ix_rag_embeddings_user_id", "rag_embeddings", ["user_id"])
        if not _has_index("rag_embeddings", "ix_rag_embeddings_chunk_hash"):
            op.create_index("ix_rag_embeddings_chunk_hash", "rag_embeddings", ["chunk_hash"])

    if not _has_table("reminders"):
        op.create_table(
            "reminders",
            sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
            sa.Column("title", sa.String(), nullable=False),
            sa.Column("datetime", sa.String(), nullable=False),
            sa.Column("transcript", sa.String(), nullable=True),
            sa.Column("text", sa.String(), nullable=False),
            sa.Column("intent", sa.String(), nullable=True),
            sa.Column("user_id", sa.String(), nullable=False),
            sa.Column("location", sa.String(), nullable=True),
            sa.Column("priority", sa.String(), nullable=True),
            sa.Column("status", sa.String(), nullable=True),
            sa.Column("created_at", sa.String(), nullable=True),
        )

    if not _has_table("voice_notes"):
        op.create_table(
            "voice_notes",
            sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
            sa.Column("user_id", sa.String(), nullable=False),
            sa.Column("transcript", sa.String(), nullable=False),
            sa.Column("keywords", sa.String(), nullable=True),
            sa.Column("timestamp", sa.String(), nullable=True),
            sa.Column("created_at", sa.String(), nullable=True),
        )


def downgrade() -> None:
    # Safe reverse order.
    if _has_table("voice_notes"):
        op.drop_table("voice_notes")
    if _has_table("reminders"):
        op.drop_table("reminders")
    if _has_table("rag_embeddings"):
        if _has_index("rag_embeddings", "ix_rag_embeddings_chunk_hash"):
            op.drop_index("ix_rag_embeddings_chunk_hash", table_name="rag_embeddings")
        if _has_index("rag_embeddings", "ix_rag_embeddings_user_id"):
            op.drop_index("ix_rag_embeddings_user_id", table_name="rag_embeddings")
        op.drop_table("rag_embeddings")
    if _has_table("expenses"):
        op.drop_table("expenses")
    if _has_table("diary_entries"):
        op.drop_table("diary_entries")
    if _has_table("alert_cache"):
        op.drop_table("alert_cache")
