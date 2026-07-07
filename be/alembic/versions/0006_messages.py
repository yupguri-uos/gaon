"""교사 소통 = Chain B 결과: messages (SSOT §15 + §11)

child_id는 SSOT §15 DDL 원문엔 없는 컬럼이다. documents·calendar_events·notifications는
전부 child_id(§17.6)가 있는데 messages만 빠져 있었다 — 다자녀 이력 조회(F-LOG)에서
"이 메시지가 어느 자녀 건인지"를 구조적으로 못 찾게 되므로 패턴에 맞춰 추가했다.
SSOT §15도 이 컬럼을 반영해 갱신이 필요하다(document_results.calendar_events와 같은 케이스,
chain_a.py 참고).

합의된 마이그레이션 순서(2026-07-08): 0004=activity_events(박수빈, feat/log) ·
0005=kb_embeddings(feat/kb-embeddings-migration) · 0006=messages(이 파일). 셋 다 원래
0003에서 각자 독립적으로 갈라져나와 번호가 겹쳤던 걸 팀이 이 순서로 정리하기로 함.

Revision ID: 0006
Revises: 0005
Create Date: 2026-07-07
"""

from __future__ import annotations

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects.postgresql import UUID

revision: str = "0006"
down_revision: Union[str, None] = "0005"
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
        sa.Column(
            "child_id", UUID(as_uuid=True), sa.ForeignKey("children.id", ondelete="SET NULL")
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
