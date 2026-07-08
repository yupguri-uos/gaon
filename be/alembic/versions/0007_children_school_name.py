"""children에 school_name 추가 (SSOT §15엔 없는 컬럼 — 온보딩에서 학교명도 받기로 결정)

name·class_no와 달리 학교명 자체는 미성년 식별 PII로 보지 않아 grade와 동일하게
동의(consent_child_pii) 없이 저장한다.

Revision ID: 0007
Revises: 0006
Create Date: 2026-07-08
"""

from __future__ import annotations

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "0007"
down_revision: Union[str, None] = "0006"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("children", sa.Column("school_name", sa.Text()))


def downgrade() -> None:
    op.drop_column("children", "school_name")
