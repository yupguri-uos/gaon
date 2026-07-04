"""공통 테이블: users, children, documents (SSOT §15 + §17.6)

Revision ID: 0001
Revises:
Create Date: 2026-07-01
"""

from __future__ import annotations

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects.postgresql import UUID

revision: str = "0001"
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

doc_status = sa.Enum(
    "uploaded",
    "parsing",
    "translating",
    "action",
    "done",
    "failed",
    name="doc_status",
)
doc_kind = sa.Enum("notice", "consent", "survey", name="doc_kind")


def upgrade() -> None:
    op.create_table(
        "users",
        sa.Column(
            "id", UUID(as_uuid=True), server_default=sa.text("gen_random_uuid()"), primary_key=True
        ),
        sa.Column("kakao_id", sa.Text(), nullable=False, unique=True),
        sa.Column("display_name", sa.Text()),
        sa.Column("origin_country", sa.Text()),
        sa.Column("native_language", sa.Text()),
        sa.Column("onboarded_at", sa.DateTime(timezone=True)),
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
        sa.CheckConstraint("origin_country IN ('VN','CN')", name="ck_users_origin_country"),
        sa.CheckConstraint("native_language IN ('vi','zh')", name="ck_users_native_language"),
    )

    op.create_table(
        "children",
        sa.Column(
            "id", UUID(as_uuid=True), server_default=sa.text("gen_random_uuid()"), primary_key=True
        ),
        sa.Column(
            "user_id",
            UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("name", sa.Text()),
        sa.Column("grade", sa.Text()),
        sa.Column("class_no", sa.Text()),
        sa.Column("color", sa.Text()),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.CheckConstraint("grade IN ('elem_1','elem_2','elem_3')", name="ck_children_grade"),
    )
    op.create_index("idx_children_user", "children", ["user_id"])

    op.create_table(
        "documents",
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
        sa.Column("image_ref", sa.Text(), nullable=False),
        sa.Column("status", doc_status, nullable=False, server_default="uploaded"),
        sa.Column("doc_type", doc_kind),
        sa.Column("title", sa.Text()),
        sa.Column("error", sa.Text()),
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
    # SSOT §15: created_at DESC로 최근 문서 우선 조회(F-LOG 이력·폴링)
    op.execute("CREATE INDEX idx_documents_user_created ON documents (user_id, created_at DESC)")


def downgrade() -> None:
    op.drop_index("idx_documents_user_created", table_name="documents")
    op.drop_table("documents")  # documents 삭제 시 doc_status·doc_kind 타입도 자동으로 DROP된다
    op.drop_index("idx_children_user", table_name="children")
    op.drop_table("children")
    op.drop_table("users")
