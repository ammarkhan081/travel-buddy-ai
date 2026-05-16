"""add chat_conversations and chat_messages tables

Revision ID: 20260515_03
Revises: 20260429_02
Create Date: 2026-05-15
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect


# revision identifiers, used by Alembic.
revision = "20260515_03"
down_revision = "20260429_02"
branch_labels = None
depends_on = None


def _has_table(table_name: str) -> bool:
    bind = op.get_bind()
    inspector = inspect(bind)
    return table_name in inspector.get_table_names()


def upgrade() -> None:
    """Create chat_conversations and chat_messages tables (idempotent)."""
    if not _has_table("chat_conversations"):
        op.create_table(
            "chat_conversations",
            sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
            sa.Column("user_id", sa.String(), nullable=False),
            sa.Column("title", sa.String(), nullable=False, server_default="New Chat"),
            sa.Column("last_location", sa.String(), nullable=True),
            sa.Column("last_intent", sa.String(), nullable=True),
            sa.Column("created_at", sa.String(), nullable=False),
            sa.Column("updated_at", sa.String(), nullable=False),
        )
        op.create_index(
            "ix_chat_conversations_user_id",
            "chat_conversations",
            ["user_id"],
        )
        op.create_index(
            "ix_chat_conversations_updated_at",
            "chat_conversations",
            ["updated_at"],
        )

    if not _has_table("chat_messages"):
        op.create_table(
            "chat_messages",
            sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
            sa.Column("conversation_id", sa.Integer(), nullable=False),
            sa.Column("user_id", sa.String(), nullable=False),
            sa.Column("role", sa.String(), nullable=False),
            sa.Column("content", sa.Text(), nullable=False),
            sa.Column("created_at", sa.String(), nullable=False),
        )
        op.create_index(
            "ix_chat_messages_conversation_id",
            "chat_messages",
            ["conversation_id"],
        )
        op.create_index(
            "ix_chat_messages_user_id",
            "chat_messages",
            ["user_id"],
        )


def downgrade() -> None:
    """Drop chat_messages and chat_conversations tables (idempotent)."""
    if _has_table("chat_messages"):
        op.drop_table("chat_messages")
    if _has_table("chat_conversations"):
        op.drop_table("chat_conversations")
