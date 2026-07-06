"""교사 소통 = Chain B 결과: messages (SSOT §15 + §11)

down_revision=0003: 이 브랜치(feat/teacher-message)는 0004(kb_embeddings, 별도 브랜치)와
독립적으로 9e20a7b에서 갈라져나왔다. kb_embeddings와 messages는 서로 무관한 변경이라
머지 순서 아무 쪽이든 상관없이 적용돼야 하므로 0003을 부모로 둔다 — 두 브랜치를 합칠 때
alembic이 멀티헤드(0004, 0005 둘 다 0003의 자식)로 보게 되면, 합치는 쪽에서
`alembic merge`로 머지 리비전을 만들거나 둘 중 하나의 down_revision을 재배선해야 한다.

Revision ID: 0005
Revises: 0003
Create Date: 2026-07-07
"""

from __future__ import annotations

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects.postgresql import UUID

revision: str = "0005"
down_revision: Union[str, None] = "0003"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

msg_situation = sa.Enum("absence", "sick_note", "consultation", "custom", name="msg_situation")


def upgrade() -> None:
    op.create_table(
        "messages",
        sa.Column(
            "id", UUID(as_uuid=True), server_default=sa.text("gen_random_uuid()"), primary_key=True
        ),
        sa.Column(
            "user_id",
            UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("situation", msg_situation, nullable=False),
        sa.Column("input_native", sa.Text(), nullable=False),
        sa.Column("output_ko", sa.Text(), nullable=False),
        sa.Column("admin_guide_native", sa.Text()),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
    )
    op.execute("CREATE INDEX idx_messages_user_created ON messages (user_id, created_at DESC)")


def downgrade() -> None:
    op.drop_index("idx_messages_user_created", table_name="messages")
    op.drop_table("messages")  # msg_situation 타입도 함께 자동 DROP된다
