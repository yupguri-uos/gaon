"""children.grade CHECK 확장: 초1~3만 있던 것을 초1~고3까지 전체로 확장

Revision ID: 0008
Revises: 0007
Create Date: 2026-07-08
"""

from __future__ import annotations

from typing import Sequence, Union

from alembic import op

revision: str = "0008"
down_revision: Union[str, None] = "0007"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

OLD_GRADES = "('elem_1','elem_2','elem_3')"
NEW_GRADES = (
    "('elem_1','elem_2','elem_3','elem_4','elem_5','elem_6',"
    "'mid_1','mid_2','mid_3','high_1','high_2','high_3')"
)


def upgrade() -> None:
    op.drop_constraint("ck_children_grade", "children", type_="check")
    op.create_check_constraint("ck_children_grade", "children", f"grade IN {NEW_GRADES}")


def downgrade() -> None:
    op.drop_constraint("ck_children_grade", "children", type_="check")
    op.create_check_constraint("ck_children_grade", "children", f"grade IN {OLD_GRADES}")
