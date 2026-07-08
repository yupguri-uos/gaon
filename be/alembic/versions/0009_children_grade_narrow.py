"""children.grade CHECK 축소: 초1~고3으로 갔던 0008을 초1~6으로 되돌림 (팀 결정 — 중고등 범위 밖)

Revision ID: 0009
Revises: 0008
Create Date: 2026-07-08
"""

from __future__ import annotations

from typing import Sequence, Union

from alembic import op

revision: str = "0009"
down_revision: Union[str, None] = "0008"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

WIDE_GRADES = (
    "('elem_1','elem_2','elem_3','elem_4','elem_5','elem_6',"
    "'mid_1','mid_2','mid_3','high_1','high_2','high_3')"
)
ELEM_GRADES = "('elem_1','elem_2','elem_3','elem_4','elem_5','elem_6')"


def upgrade() -> None:
    op.drop_constraint("ck_children_grade", "children", type_="check")
    op.create_check_constraint("ck_children_grade", "children", f"grade IN {ELEM_GRADES}")


def downgrade() -> None:
    op.drop_constraint("ck_children_grade", "children", type_="check")
    op.create_check_constraint("ck_children_grade", "children", f"grade IN {WIDE_GRADES}")
