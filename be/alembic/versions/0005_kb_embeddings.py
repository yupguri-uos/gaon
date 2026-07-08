"""RAG 지식베이스: kb_embeddings (SSOT §15 + §17.9)

vector 확장을 처음 쓰는 테이블이라 CREATE EXTENSION도 여기서 한다. 배포 DB엔 kb_embeddings가
아직 없으므로(§18.6) 순수 CREATE — 기존 vector(1536) 드리프트는 repo/개발 DB 얘기였고 배포
DB와는 무관해 DROP/ALTER가 필요 없다.

합의된 마이그레이션 순서(2026-07-08): 0004=activity_events(박수빈, feat/log, 그대로 유지) ·
0005=kb_embeddings(이 파일) · 0006=messages(feat/teacher-message). kb_embeddings와
activity_events가 둘 다 0003에서 독립적으로 갈라져나와 0004로 번호가 겹쳤던 걸
이 순서로 정리하기로 함.

Revision ID: 0005
Revises: 0004
Create Date: 2026-07-06
"""

from __future__ import annotations

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from pgvector.sqlalchemy import Vector
from sqlalchemy.dialects.postgresql import JSONB, TSVECTOR, UUID

revision: str = "0005"
down_revision: Union[str, None] = "0004"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute("CREATE EXTENSION IF NOT EXISTS vector")

    op.create_table(
        "kb_embeddings",
        sa.Column(
            "id", UUID(as_uuid=True), server_default=sa.text("gen_random_uuid()"), primary_key=True
        ),
        sa.Column("content", sa.Text(), nullable=False),
        sa.Column(
            "content_hash", sa.Text(), nullable=False, unique=True
        ),  # 멱등키(재적재 중복 방지)
        sa.Column("embedding", Vector(1024)),  # KURE(BGE-M3 기반), 결정 #4
        sa.Column("source", sa.Text()),
        sa.Column("title", sa.Text()),
        sa.Column("url", sa.Text()),
        sa.Column("section", sa.Text()),
        sa.Column("doc_type", sa.Text()),
        sa.Column("content_tsv", TSVECTOR()),  # 하이브리드 sparse용, v1 미사용(컬럼만 선확보)
        sa.Column("metadata", JSONB(), nullable=False, server_default=sa.text("'{}'::jsonb")),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
    )
    op.execute(
        "CREATE INDEX idx_kb_embedding ON kb_embeddings USING hnsw (embedding vector_cosine_ops)"
    )
    op.execute("CREATE INDEX idx_kb_content_tsv ON kb_embeddings USING gin (content_tsv)")


def downgrade() -> None:
    op.drop_index("idx_kb_content_tsv", table_name="kb_embeddings")
    op.drop_index("idx_kb_embedding", table_name="kb_embeddings")
    op.drop_table("kb_embeddings")
