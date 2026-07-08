"""
GAON AI — 실 KbStore: PgVectorKbStore (F-CORE-2, kb_embeddings ↔ pgvector)

0005_kb_embeddings 스키마(vector(1024) + hnsw vector_cosine_ops)를 그대로 사용한다 — 추가 DDL 없음.
드라이버는 BE 스택(be/app/db.py = sync SQLAlchemy + psycopg v3)과 동일한 psycopg의 async 모드.
벡터는 '[…]' 리터럴 + ::vector 캐스트로 전달해 커넥션별 어댑터 등록(register_vector) 의존을 없앤다
— 어떤 psycopg 풀이 주입되든 사전 셋업 없이 동작한다.

# TODO(BE): 풀/세션 주입 계약 확정 전(열린 결정) — 생성자 주입(공유 풀)을 우선하고,
# 없으면 from_database_url()로 DATABASE_URL 자체 풀을 만든다. 계약 확정 시 폴백 정리.

설치: `pip install -e "ai[rag]"` (psycopg[binary,pool]).
"""

from __future__ import annotations

import os
from typing import TYPE_CHECKING

from gaon_ai.ingest import EmbeddedChunk
from gaon_ai.rag import RetrievedChunk

if TYPE_CHECKING:
    from psycopg_pool import AsyncConnectionPool

EXPECTED_DIM = 1024  # SSOT §15: kb_embeddings.embedding = vector(1024)

# 멱등 업서트: content_hash = sha256(source|content)(ingest._content_hash)가 유니크 멱등키.
# metadata는 EmbeddedChunk에 대응 필드가 없어 insert 시 서버 기본('{}')에 맡기고
# 갱신 시 기존 값을 보존한다(임의로 비우지 않음).
_UPSERT_SQL = """
INSERT INTO kb_embeddings
    (content, content_hash, embedding, source, title, url, section, doc_type)
VALUES
    (%(content)s, %(content_hash)s, %(embedding)s::vector, %(source)s, %(title)s,
     %(url)s, %(section)s, %(doc_type)s)
ON CONFLICT (content_hash) DO UPDATE SET
    embedding = EXCLUDED.embedding,
    content = EXCLUDED.content,
    source = EXCLUDED.source,
    title = EXCLUDED.title,
    url = EXCLUDED.url,
    section = EXCLUDED.section,
    doc_type = EXCLUDED.doc_type
"""

# <=> = cosine distance(hnsw vector_cosine_ops와 정합) → score = 1 - distance(유사도)
_DENSE_SQL = """
SELECT content, content_hash, source, title, url, section, doc_type,
       1 - (embedding <=> %(vector)s::vector) AS score
FROM kb_embeddings
WHERE embedding IS NOT NULL
ORDER BY embedding <=> %(vector)s::vector
LIMIT %(top_k)s
"""

_DELETE_BY_SOURCE_SQL = "DELETE FROM kb_embeddings WHERE source = %s"


def _vector_literal(vector: list[float]) -> str:
    """pgvector 입력 리터럴('[0.1,0.2,...]'). SQL의 ::vector 캐스트와 함께 쓴다."""
    return "[" + ",".join(map(str, vector)) + "]"


class PgVectorKbStore:
    """KbStore Protocol 실구현: dense_search + upsert(멱등) + delete_by_source(§17.9).

    sparse_search는 v1 미지원(HybridRetriever use_sparse=False 전제) — content_tsv는
    컬럼만 선확보된 상태라 조용한 빈 결과 대신 명시적으로 실패시킨다.
    """

    def __init__(self, pool: AsyncConnectionPool, *, owns_pool: bool = False) -> None:
        # 주입된 풀(owns_pool=False)의 open/close 수명주기는 호출자(BE) 책임이다.
        self._pool = pool
        self._owns_pool = owns_pool
        self._opened = False

    @classmethod
    def from_database_url(cls, database_url: str | None = None) -> PgVectorKbStore:
        """DATABASE_URL(인자 > 환경변수)로 자체 async 풀 생성 — 주입 계약 확정 전 폴백 경로.

        풀은 lazy open: 실제 DB 연결은 첫 쿼리 시점에 일어난다(생성 시점엔 연결 없음).
        """
        try:
            from psycopg_pool import AsyncConnectionPool
        except ImportError as exc:  # pragma: no cover - 의존성 미설치 환경 안내용
            raise ImportError(
                'PgVectorKbStore에는 psycopg[binary,pool]가 필요하다: pip install -e "ai[rag]"'
            ) from exc

        url = database_url or os.getenv("DATABASE_URL")
        if not url:
            raise ValueError("DATABASE_URL이 없다(인자 또는 환경변수로 지정)")
        # SQLAlchemy식 드라이버 접미사(postgresql+psycopg://)는 psycopg conninfo가 못 읽는다
        url = url.replace("postgresql+psycopg://", "postgresql://", 1)
        return cls(AsyncConnectionPool(url, open=False), owns_pool=True)

    async def close(self) -> None:
        """자체 소유 풀만 닫는다. 주입된 풀은 호출자가 관리."""
        if self._owns_pool and self._opened:
            await self._pool.close()
            self._opened = False

    async def dense_search(self, vector: list[float], *, top_k: int) -> list[RetrievedChunk]:
        self._check_dim(len(vector), what="질의 벡터")
        await self._ensure_open()
        async with self._pool.connection() as conn:
            cursor = await conn.execute(
                _DENSE_SQL, {"vector": _vector_literal(vector), "top_k": top_k}
            )
            rows = await cursor.fetchall()
        return [
            RetrievedChunk(
                content=row[0],
                content_hash=row[1],
                source=row[2],
                title=row[3],
                url=row[4],
                section=row[5],
                doc_type=row[6],
                score=float(row[7]),
            )
            for row in rows
        ]

    async def sparse_search(self, query: str, *, top_k: int) -> list[RetrievedChunk]:
        raise NotImplementedError(
            "sparse_search는 v1 미지원(dense-only) — content_tsv 충전 후 후속 구현(F-CORE-2)"
        )

    async def upsert(self, chunks: list[EmbeddedChunk]) -> int:
        if not chunks:
            return 0
        for chunk in chunks:
            self._check_dim(len(chunk.embedding), what=f"청크 {chunk.content_hash[:12]}…")
        params = [
            {
                "content": chunk.content,
                "content_hash": chunk.content_hash,
                "embedding": _vector_literal(chunk.embedding),
                "source": chunk.source,
                "title": chunk.title,
                "url": chunk.url,
                "section": chunk.section,
                "doc_type": chunk.doc_type,
            }
            for chunk in chunks
        ]
        await self._ensure_open()
        async with self._pool.connection() as conn:
            async with conn.cursor() as cursor:
                await cursor.executemany(_UPSERT_SQL, params)  # psycopg3: 내부 파이프라인 배치
        return len(chunks)  # ON CONFLICT DO UPDATE라 입력 전건이 반영된다

    async def delete_by_source(self, source: str) -> int:
        await self._ensure_open()
        async with self._pool.connection() as conn:
            cursor = await conn.execute(_DELETE_BY_SOURCE_SQL, (source,))
            return cursor.rowcount

    async def _ensure_open(self) -> None:
        # 자체 소유 풀은 첫 사용 시 지연 오픈(생성자 시점엔 이벤트 루프가 없을 수 있다)
        if self._owns_pool and not self._opened:
            await self._pool.open()
            self._opened = True

    def _check_dim(self, dim: int, *, what: str) -> None:
        if dim != EXPECTED_DIM:
            raise ValueError(
                f"{what} 차원 {dim} ≠ vector({EXPECTED_DIM})(SSOT §15) — 적재/검색 불가"
            )
