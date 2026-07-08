"""F-CORE-2 통합 — 실 KURE(다운로드) + 실 pgvector DB. 기본 스킵.

실행: GAON_INTEGRATION=1 DATABASE_URL=postgresql://... pytest ai/tests -m integration
전제: `pip install -e "ai[rag]"` + 0005 마이그레이션 적용된 DB.
"""

from __future__ import annotations

import os

import pytest

from gaon_ai.ingest import SourceDoc, ingest
from gaon_ai.rag import Embedder, HybridRetriever, KbStore, Retriever

pytestmark = [
    pytest.mark.integration,
    pytest.mark.skipif(
        not os.getenv("GAON_INTEGRATION"),
        reason="통합 테스트는 GAON_INTEGRATION=1일 때만(실 KURE 다운로드·실 DB 필요)",
    ),
]

_SOURCE = "itest-rag-f-core-2"  # 테스트 전용 source — 시작·종료 시 delete_by_source로 정리


@pytest.fixture(scope="module")
def kure():
    from gaon_ai.embedders import KureEmbedder

    return KureEmbedder()  # 모델 로드가 무거워 모듈당 1회


def test_kure_satisfies_embedder_and_dim(kure):
    assert isinstance(kure, Embedder)
    assert kure.dim == 1024


async def test_kure_returns_normalized_vectors(kure):
    [vec] = await kure.embed(["현장학습 준비물 돗자리"])
    assert len(vec) == 1024
    assert abs(sum(x * x for x in vec) - 1.0) < 1e-3  # normalize_embeddings=True


async def test_pgvector_roundtrip_idempotent_and_dense_e2e(kure):
    from gaon_ai.stores import PgVectorKbStore

    store = PgVectorKbStore.from_database_url()
    assert isinstance(store, KbStore)
    docs = [
        SourceDoc(
            source=_SOURCE,
            title="통합 픽스처",
            doc_type="general",
            text="돗자리는 현장학습 때 바닥에 까는 깔개다. 물통과 도시락도 함께 챙긴다.",
        )
    ]
    try:
        await store.delete_by_source(_SOURCE)  # 이전 실행 잔여물 정리

        n1 = await ingest(docs, embedder=kure, store=store)
        assert n1 > 0
        n2 = await ingest(docs, embedder=kure, store=store)  # 재적재해도 중복 없음(멱등)
        assert n2 == n1

        # dense 검색 end-to-end: KURE + pgvector + HybridRetriever(dense-only)
        retriever = HybridRetriever(kure, store, use_sparse=False)
        assert isinstance(retriever, Retriever)
        out = await retriever.retrieve(["돗자리"], top_k=3)
        assert out
        assert all(c.content_hash for c in out)  # 프로비넌스 보존
        assert any("돗자리" in c.content for c in out)

        deleted = await store.delete_by_source(_SOURCE)
        assert deleted == n1  # 멱등 적재라 총 행수 = 1회 적재분
    finally:
        await store.delete_by_source(_SOURCE)
        await store.close()
