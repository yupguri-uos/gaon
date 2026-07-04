"""Chain A 결과: extracted_items, document_results (SSOT §15 + calendar_events 보강)

document_results.calendar_events는 SSOT §15 DDL에 없던 컬럼이다. document_results가 모델링하는
Lifestyle Action 출력(ActionCard)에는 calendar_events가 있는데 DDL만 빠뜨렸다 — 없으면
GET /documents/{id}/result 재조회 시 캘린더 이벤트가 유실돼서 추가했다. SSOT §15 갱신 필요.

Revision ID: 0002
Revises: 0001
Create Date: 2026-07-01
"""

from __future__ import annotations

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects.postgresql import JSONB, UUID

revision: str = "0002"
down_revision: Union[str, None] = "0001"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "extracted_items",
        sa.Column(
            "document_id",
            UUID(as_uuid=True),
            sa.ForeignKey("documents.id", ondelete="CASCADE"),
            primary_key=True,
        ),
        sa.Column("deadline", sa.Date()),
        sa.Column("requires_reply", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("dates", JSONB(), nullable=False, server_default=sa.text("'[]'::jsonb")),
        sa.Column("amounts", JSONB(), nullable=False, server_default=sa.text("'[]'::jsonb")),
        sa.Column("supplies", JSONB(), nullable=False, server_default=sa.text("'[]'::jsonb")),
        sa.Column("checkboxes", JSONB(), nullable=False, server_default=sa.text("'[]'::jsonb")),
        sa.Column("raw_text", sa.Text()),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
    )
    op.execute(
        "CREATE INDEX idx_extracted_deadline ON extracted_items (deadline) "
        "WHERE deadline IS NOT NULL"
    )

    op.create_table(
        "document_results",
        sa.Column(
            "document_id",
            UUID(as_uuid=True),
            sa.ForeignKey("documents.id", ondelete="CASCADE"),
            primary_key=True,
        ),
        sa.Column("summary_native", sa.Text()),
        sa.Column("terms", JSONB(), nullable=False, server_default=sa.text("'[]'::jsonb")),
        sa.Column(
            "action_supplies", JSONB(), nullable=False, server_default=sa.text("'[]'::jsonb")
        ),
        # SSOT §15엔 없는 컬럼 — 사유는 이 파일 상단 docstring 참고.
        sa.Column(
            "calendar_events", JSONB(), nullable=False, server_default=sa.text("'[]'::jsonb")
        ),
        sa.Column("reply_draft_ko", sa.Text()),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
    )


def downgrade() -> None:
    op.drop_table("document_results")
    op.drop_index("idx_extracted_deadline", table_name="extracted_items")
    op.drop_table("extracted_items")
