"""활동 로그: activity_events

Revision ID: 0004
Revises: 0003
Create Date: 2026-07-07
"""

from __future__ import annotations

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects.postgresql import UUID

revision: str = "0004"
down_revision: Union[str, None] = "0003"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

activity_kind = sa.Enum(
    "document_processed",
    "event_participated",
    "item_missed",
    name="activity_kind",
)


def upgrade() -> None:
    op.create_table(
        "activity_events",
        sa.Column(
            "id", UUID(as_uuid=True), server_default=sa.text("gen_random_uuid()"), primary_key=True
        ),
        sa.Column(
            "user_id",
            UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("activity_kind", activity_kind, nullable=False),
        sa.Column("related_id", UUID(as_uuid=True), nullable=True),
        sa.Column("occurred_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
    )
    op.create_index(
        "idx_activity_user_time",
        "activity_events",
        ["user_id", "occurred_at"],
    )


def downgrade() -> None:
    op.drop_index("idx_activity_user_time", table_name="activity_events")
    op.drop_table("activity_events")
    activity_kind.drop(op.get_bind(), checkfirst=True)
