"""캘린더 이벤트: calendar_events (SSOT §15 + §17.6 child_id)

Revision ID: 0003
Revises: 0002
Create Date: 2026-07-02
"""

from __future__ import annotations

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects.postgresql import UUID

revision: str = "0003"
down_revision: Union[str, None] = "0002"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

cal_kind = sa.Enum("deadline", "event", name="cal_kind")


def upgrade() -> None:
    op.create_table(
        "calendar_events",
        sa.Column(
            "id",
            UUID(as_uuid=True),
            server_default=sa.text("gen_random_uuid()"),
            primary_key=True,
        ),
        sa.Column(
            "user_id",
            UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "document_id", UUID(as_uuid=True), sa.ForeignKey("documents.id", ondelete="SET NULL")
        ),
        sa.Column(
            "child_id", UUID(as_uuid=True), sa.ForeignKey("children.id", ondelete="SET NULL")
        ),
        sa.Column("title", sa.Text(), nullable=False),
        sa.Column("event_date", sa.Date(), nullable=False),
        sa.Column("type", cal_kind, nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
    )
    op.create_index("idx_calendar_user_date", "calendar_events", ["user_id", "event_date"])


def downgrade() -> None:
    op.drop_index("idx_calendar_user_date", table_name="calendar_events")
    op.drop_table("calendar_events")  # cal_kind 타입도 함께 자동 DROP된다
