"""Proactive 알림: notifications + device_tokens

Revision ID: 0010
Revises: 0009
"""

from __future__ import annotations
from typing import Union
import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects.postgresql import UUID

revision: str = "0010"
down_revision: Union[str, None] = "0009"
branch_labels = None
depends_on = None

noti_kind = sa.Enum(
    "deadline_d2",
    "unreplied_consent",
    "event_preview",
    name="noti_kind",
)


def upgrade() -> None:
    op.create_table(
        "notifications",
        sa.Column(
            "id",
            UUID(as_uuid=True),
            primary_key=True,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column(
            "user_id",
            UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("child_id", UUID(as_uuid=True), nullable=True),
        sa.Column("type", noti_kind, nullable=False),
        sa.Column("title_native", sa.Text(), nullable=False),
        sa.Column("body_native", sa.Text(), nullable=False),
        sa.Column("scheduled_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("related_document_id", UUID(as_uuid=True), nullable=True),
        sa.Column("sent_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("read_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.UniqueConstraint(
            "user_id",
            "type",
            "related_document_id",
            "scheduled_at",
            name="uq_noti_dedup",
        ),
    )

    op.create_index(
        "idx_noti_due",
        "notifications",
        ["scheduled_at"],
        postgresql_where=sa.text("sent_at IS NULL"),
    )

    op.create_table(
        "device_tokens",
        sa.Column(
            "id",
            UUID(as_uuid=True),
            primary_key=True,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column(
            "user_id",
            UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("token", sa.Text(), nullable=False, unique=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
    )


def downgrade() -> None:
    op.drop_table("device_tokens")
    op.drop_index("idx_noti_due", table_name="notifications")
    op.drop_table("notifications")
    noti_kind.drop(op.get_bind(), checkfirst=True)
