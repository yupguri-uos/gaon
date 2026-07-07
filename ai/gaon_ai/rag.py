"""
GAON AI — RAG 검색 추상화 (F-CORE-2)

§9 체인 규칙: DocParsing 후 'supplies·용어'로 kb_embeddings를 검색해 rag_context를 만들고,
CulturalTranslation 입력에 주입한다. 검색은 '체인 단계'이며, 에이전트는 rag_context를
주어진 것으로 받는다(§8). 임베딩·pgvector(hnsw cosine) 구현은 이 Protocol 뒤에 숨긴다.
"""

from __future__ import annotations

import asyncio
from typing import TYPE_CHECKING, Protocol, runtime_checkable

from pydantic import BaseModel

from gaon_shared import ExtractedItem

if TYPE_CHECKING:
    from gaon_ai.ingest import EmbeddedChunk  # 런타임 순환 회피(주석은 문자열 평가)


class RetrievedChunk(BaseModel):
    content: str
    source: str | None = None  # 출처(예: 교육부 가이드라인) — kb_embeddings.source
    score: float | None = None  # 코사인 유사도 또는 RRF 융합 점수(선택)
    # ── 프로비넌스·식별(F-CORE-2): 검색 결과에도 출처를 보존한다 ──────────────
    content_hash: str | None = None  # RRF 동일 청크 식별 키(인제스트 멱등키와 동일)
    title: str | None = None
    section: str | None = None
    doc_type: str | None = None


@runtime_checkable
class Retriever(Protocol):
    async def retrieve(self, queries: list[str], *, top_k: int = 4) -> list[RetrievedChunk]: ...


def build_rag_queries(extracted: ExtractedItem) -> list[str]:
    """검색 시드(F-CORE-2): 준비물 원문 + 문서 제목. 용어 해설·관행 청크를 끌어오기 위한 질의."""
    queries: list[str] = list(extracted.supplies)
    if extracted.title:
        queries.append(extracted.title)
    return queries


def chunks_to_context(chunks: list[RetrievedChunk]) -> list[str]:
    """CulturalTranslationInput.rag_context(list[str]) 형태로 변환."""
    return [c.content for c in chunks]


# ── 임베딩·저장 seam ────────────────────────────────────────────────────────
# 실 구현은 후속 주입: Embedder=KURE/BGE-M3, KbStore=PgVectorKbStore(pgvector hnsw).
# 여기서는 모델·DB 무관하게 계약(Protocol)만 고정하고 fake로 테스트한다.
@runtime_checkable
class Embedder(Protocol):
    """텍스트 → 임베딩 벡터. dim=임베딩 차원(기본 1024, KURE/BGE-M3 계열)."""

    dim: int

    async def embed(self, texts: list[str]) -> list[list[float]]: ...


@runtime_checkable
class KbStore(Protocol):
    """kb_embeddings 읽기/쓰기. dense=벡터, sparse=키워드, upsert=멱등 적재."""

    async def dense_search(self, vector: list[float], *, top_k: int) -> list[RetrievedChunk]: ...

    async def sparse_search(self, query: str, *, top_k: int) -> list[RetrievedChunk]: ...

    async def upsert(self, chunks: list[EmbeddedChunk]) -> int: ...


def reciprocal_rank_fusion(
    ranked_lists: list[list[RetrievedChunk]], *, top_k: int, k: int = 60
) -> list[RetrievedChunk]:
    """dense·sparse 결과를 RRF(Σ 1/(k+rank))로 융합. 청크 식별은 content_hash로만 한다.

    content_hash가 없는 청크는 식별 불가라 병합이 조용히 틀린다(중복 계수/오병합).
    따라서 hash 없는 청크가 오면 폴백하지 않고 명시적으로 실패시킨다 —
    hash를 채우는 책임은 KbStore(생산자)에 있고, 이 함수는 전제를 검증만 한다.
    양쪽 리스트에서 모두 상위인 청크가 한쪽에만 있는 청크보다 앞선다.
    """
    scores: dict[str, float] = {}
    chosen: dict[str, RetrievedChunk] = {}
    for ranked in ranked_lists:
        for rank, chunk in enumerate(ranked, start=1):
            if not chunk.content_hash:
                raise ValueError(
                    "reciprocal_rank_fusion: content_hash 없는 청크는 융합할 수 없다"
                    "(KbStore 산출물은 content_hash를 채워야 함)."
                )
            key = chunk.content_hash
            scores[key] = scores.get(key, 0.0) + 1.0 / (k + rank)
            chosen.setdefault(key, chunk)  # 대표 청크=처음 본 것(프로비넌스 보존)
    ranked_keys = sorted(scores, key=lambda key: scores[key], reverse=True)
    # 융합 점수를 score에 실어 반환(원 코사인 점수 대신 RRF 점수)
    return [chosen[key].model_copy(update={"score": scores[key]}) for key in ranked_keys[:top_k]]


class HybridRetriever:
    """Embedder+KbStore로 dense(+옵션 sparse) 검색 후 RRF로 융합. Retriever Protocol 충족.

    use_sparse=False(v1 기본)면 dense-only. True면 dense+sparse를 RRF로 합쳐 하이브리드.
    """

    def __init__(
        self,
        embedder: Embedder,
        store: KbStore,
        *,
        dense_k: int = 8,
        sparse_k: int = 8,
        rrf_k: int = 60,
        use_sparse: bool = False,
    ) -> None:
        self._embedder = embedder
        self._store = store
        self._dense_k = dense_k
        self._sparse_k = sparse_k
        self._rrf_k = rrf_k
        self._use_sparse = use_sparse

    async def retrieve(self, queries: list[str], *, top_k: int = 4) -> list[RetrievedChunk]:
        if not queries:
            return []
        vectors = await self._embedder.embed(queries)
        tasks = []
        for query, vector in zip(queries, vectors):
            tasks.append(self._store.dense_search(vector, top_k=self._dense_k))
            if self._use_sparse:
                tasks.append(self._store.sparse_search(query, top_k=self._sparse_k))
        ranked_lists = await asyncio.gather(*tasks)
        return reciprocal_rank_fusion(list(ranked_lists), top_k=top_k, k=self._rrf_k)
