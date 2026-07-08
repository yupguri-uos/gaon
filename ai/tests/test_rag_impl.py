"""F-CORE-2 실구현 단위 검증 — 실 DB·실 모델 없이 계약을 고정한다.

대응: KbStore.delete_by_source(§17.9 orphan 방지), ingest(replace_source=True),
PgVectorKbStore의 Protocol 충족·차원(1024) 검증. 실 KURE·실 DB 경로는
test_rag_integration.py(@integration, 기본 스킵) 소관.
"""

from __future__ import annotations

import pytest

from gaon_ai.ingest import EmbeddedChunk, SourceDoc, ingest
from gaon_ai.rag import KbStore
from gaon_ai.testing import FakeEmbedder, FakeKbStore


def _doc(text: str, source: str) -> SourceDoc:
    return SourceDoc(source=source, title="테스트 문서", doc_type="general", text=text)


# ── FakeKbStore.delete_by_source (KbStore Protocol 미러) ────────────────────
async def test_fake_kbstore_delete_by_source_only_target():
    embedder, store = FakeEmbedder(dim=16), FakeKbStore()
    await ingest(
        [_doc("문장A입니다.", "s1"), _doc("문장B입니다.", "s2")], embedder=embedder, store=store
    )
    assert len(store._store) == 2

    deleted = await store.delete_by_source("s1")
    assert deleted == 1  # 반환=삭제 건수
    assert {chunk.source for chunk in store._store.values()} == {"s2"}  # s2는 무사

    assert await store.delete_by_source("없는소스") == 0


# ── ingest(replace_source=True) — 고아 청크 제거(§17.9) ─────────────────────
async def test_ingest_replace_source_removes_orphans():
    embedder, store = FakeEmbedder(dim=16), FakeKbStore()
    await ingest([_doc("옛 내용 문장입니다.", "s1")], embedder=embedder, store=store)
    old_hashes = set(store._store)

    # 같은 source의 내용이 통째로 바뀐 갱신 — replace 없으면 옛 청크가 고아로 남는다
    new_docs = [_doc("새 내용 문장입니다.", "s1")]
    await ingest(new_docs, embedder=embedder, store=store, replace_source=True)
    assert not old_hashes & set(store._store)  # 옛 청크 전부 제거
    assert store._store  # 새 청크는 적재됨


async def test_ingest_replace_source_keeps_other_sources():
    embedder, store = FakeEmbedder(dim=16), FakeKbStore()
    await ingest(
        [_doc("문장A입니다.", "s1"), _doc("문장B입니다.", "s2")], embedder=embedder, store=store
    )
    await ingest([_doc("문장C입니다.", "s1")], embedder=embedder, store=store, replace_source=True)
    sources = {chunk.source for chunk in store._store.values()}
    assert sources == {"s1", "s2"}  # 배치에 없는 s2는 건드리지 않는다


# ── PgVectorKbStore — DB 연결 없이 검증 가능한 계약(lazy open) ──────────────
def _pg_store():
    pytest.importorskip("psycopg_pool", reason="ai[rag] 미설치 환경은 스킵")
    from gaon_ai.stores import PgVectorKbStore

    # from_database_url은 lazy open — 실제 연결은 첫 쿼리 시점이라 가짜 URL로 안전
    return PgVectorKbStore.from_database_url("postgresql://gaon:pw@localhost:5432/gaon")


def test_pgvector_kbstore_satisfies_protocol():
    assert isinstance(_pg_store(), KbStore)


async def test_pgvector_dense_search_rejects_wrong_dim():
    with pytest.raises(ValueError, match="1024"):
        await _pg_store().dense_search([0.0] * 8, top_k=3)


async def test_pgvector_upsert_rejects_wrong_dim():
    chunk = EmbeddedChunk(
        content="본문",
        source="s",
        content_hash="h" * 64,
        embedding=[0.0] * 8,  # 1024가 아니면 DB에 닿기 전에 실패해야 한다
    )
    with pytest.raises(ValueError, match="1024"):
        await _pg_store().upsert([chunk])


async def test_pgvector_sparse_search_not_supported_v1():
    with pytest.raises(NotImplementedError):
        await _pg_store().sparse_search("돗자리", top_k=3)
