"""활동 로그: activity_events

Revision ID: 0004
Revises: 0003
Create Date: 2026-07-07
"""

from __future__ import annotations

from typing import Sequence, Union

import sqlalchemy as sa  # 가장 많이 임폴트 되는 sa, op
from alembic import op  # sqlalchemy 객체를 실제 db에 수정하는 객체
from sqlalchemy.dialects.postgresql import UUID

revision: str = "0004"
down_revision: Union[str, None] = "0003"  # 여러 타입 중 하나가 될 수 있다는 뜻
branch_labels: Union[str, Sequence[str], None] = (
    None  # 시퀀스는 list나 tuple 처럼 순서가 있는 자료형
)
depends_on: Union[str, Sequence[str], None] = None

activity_kind = sa.Enum(  # enum 타입으로 허용되는 값들을 저장, 디비에 타입이 저장되는 것임
    "document_processed",
    "event_participated",
    "item_missed",
    name="activity_kind",
)


def upgrade() -> None:  # alembic이 업데이트할 때 실행하는 것
    op.create_table(
        "activity_events",
        sa.Column(
            "id",
            UUID(as_uuid=True),  # uuid = db가 직접 id 자동 생성
            server_default=sa.text(
                "gen_random_uuid()"
            ),  # 이걸 postgresql에 전달하면 실행됨 그럼 디폴트값으로 지정이된다
            primary_key=True,
        ),
        sa.Column(
            "user_id",
            UUID(as_uuid=True),  # 인서트할 때 집어넣는것
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(  # 내가 위에 설정한 활동의 종류가 저장되는 칼럼
            "activity_kind", activity_kind, nullable=False
        ),
        sa.Column("related_id", UUID(as_uuid=True), nullable=True),
        sa.Column("occurred_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
    )
    op.create_index(  # 인덱스 생성
        "idx_activity_user_time",  # 인덱스 이름
        "activity_events",  # 테이블 이름
        [
            "user_id",
            "occurred_at",
        ],  # 컬럼 목록, 엠버릭이 시퀀스를 받기 떄문에 칼럼 목록을 리스트로 줄 수 있다.
    )


def downgrade() -> None:
    op.drop_index("idx_activity_user_time", table_name="activity_events")
    op.drop_table("activity_events")
    activity_kind.drop(
        op.get_bind(), checkfirst=True
    )  # 삭제하기 전에 있는지 확인하고 있으면 db에서 연결을 가져와서 activity_kind enum 타입을 삭제!
