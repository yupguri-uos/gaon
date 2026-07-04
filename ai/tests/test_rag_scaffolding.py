"""F-CORE-2 RAG 스캐폴딩 검증 — 실 임베딩·DB·코퍼스 없이 fake로 계약을 고정한다.

대응: F-CORE-2(RAG). Embedder/KbStore/Retriever Protocol 충족, 문장 경계 청킹,
content_hash 안정성, 멱등 인제스트, RRF 융합, dense-only HybridRetriever.
"""

from __future__ import annotations

import re

import pytest

from gaon_ai.ingest import SourceDoc, chunk_document, ingest
from gaon_ai.rag import (
    Embedder,
    HybridRetriever,
    KbStore,
    RetrievedChunk,
    Retriever,
    reciprocal_rank_fusion,
)
from gaon_ai.testing import FakeEmbedder, FakeKbStore


def _doc(text: str, source: str = "moe-guide") -> SourceDoc:
    return SourceDoc(source=source, title="테스트 문서", doc_type="general", text=text)


def _sentences(content: str) -> set[str]:
    return set(re.findall(r"문장\d+입니다\.", content))


# ── Protocol 충족 ───────────────────────────────────────────────────────────
def test_fakes_satisfy_protocols():
    embedder = FakeEmbedder()
    store = FakeKbStore()
    assert isinstance(embedder, Embedder)
    assert isinstance(store, KbStore)
    assert isinstance(HybridRetriever(embedder, store), Retriever)


def test_fake_embedder_dim_default():
    assert FakeEmbedder().dim == 1024


async def test_fake_embedder_deterministic_unit_vectors():
    vecs = await FakeEmbedder(dim=16).embed(["가", "나"])
    assert len(vecs) == 2 and all(len(v) == 16 for v in vecs)
    # 결정적: 같은 입력 → 같은 벡터
    a1 = (await FakeEmbedder(dim=16).embed(["가"]))[0]
    a2 = (await FakeEmbedder(dim=16).embed(["가"]))[0]
    assert a1 == a2
    # 단위벡터: L2 노름 ≈ 1
    assert abs(sum(x * x for x in a1) - 1.0) < 1e-9


# ── 청킹 ────────────────────────────────────────────────────────────────────
def test_chunk_document_hash_stable_and_provenance():
    doc = _doc("첫째 문장입니다. 둘째 문장입니다. 셋째 문장입니다.")
    a = chunk_document(doc)
    b = chunk_document(doc)
    assert a  # 최소 1청크
    assert [c.content_hash for c in a] == [c.content_hash for c in b]  # 같은 입력=같은 hash
    for c in a:
        assert c.source == "moe-guide"
        assert c.doc_type == "general"
        assert c.title == "테스트 문서"
        assert c.content_hash


def test_chunk_document_respects_boundary_target_overlap():
    sentences = [f"문장{i}입니다." for i in range(12)]  # 각 짧고 고유
    doc = _doc(" ".join(sentences))
    chunks = chunk_document(doc, target_chars=20, overlap_chars=8)
    assert len(chunks) > 1  # target 초과로 쪼개짐
    # 문장 경계 존중: 각 청크는 온전한 '문장N입니다.' 토큰들로만 구성(문장 중간 절단 없음)
    for c in chunks:
        tokens = c.content.split()
        assert tokens  # 빈 청크 없음
        assert all(re.fullmatch(r"문장\d+입니다\.", token) for token in tokens)
    # overlap: 인접 청크가 최소 한 문장을 공유
    for prev, nxt in zip(chunks, chunks[1:]):
        assert _sentences(prev.content) & _sentences(nxt.content)


# ── 인제스트(멱등) ──────────────────────────────────────────────────────────
async def test_ingest_idempotent():
    docs = [_doc("문장0입니다. 문장1입니다. 문장2입니다.")]
    embedder, store = FakeEmbedder(dim=32), FakeKbStore()
    n1 = await ingest(docs, embedder=embedder, store=store)
    size1 = len(store._store)
    n2 = await ingest(docs, embedder=embedder, store=store)  # 재적재
    size2 = len(store._store)
    assert size1 > 0
    assert n1 == n2  # 업서트 건수 동일
    assert size1 == size2  # 저장 개수 불변(중복 없음 = 멱등)


# ── Retriever(dense-only) ───────────────────────────────────────────────────
async def test_hybrid_retriever_dense_only_returns_top_k():
    embedder, store = FakeEmbedder(dim=32), FakeKbStore()
    docs = [_doc(f"고유내용{i} 문장입니다.", source=f"s{i}") for i in range(6)]
    await ingest(docs, embedder=embedder, store=store)
    retriever = HybridRetriever(embedder, store, use_sparse=False)
    out = await retriever.retrieve(["고유내용3"], top_k=3)
    assert 0 < len(out) <= 3
    assert all(isinstance(c, RetrievedChunk) for c in out)
    assert all(c.content_hash for c in out)  # 프로비넌스 보존


# ── RRF 융합 ────────────────────────────────────────────────────────────────
def _rc(content_hash: str, content: str = "본문") -> RetrievedChunk:
    return RetrievedChunk(content=content, content_hash=content_hash)


def test_reciprocal_rank_fusion_prefers_mutual_top():
    # A: dense1·sparse2 / B: dense2·sparse1 (양쪽 상위) / C·D: 한쪽에만 등장
    dense = [_rc("A"), _rc("B"), _rc("C")]
    sparse = [_rc("B"), _rc("A"), _rc("D")]
    fused = reciprocal_rank_fusion([dense, sparse], top_k=4, k=60)
    order = [c.content_hash for c in fused]
    assert set(order[:2]) == {"A", "B"}  # 양쪽 상위가 앞선다
    assert order.index("A") < order.index("C")
    assert order.index("B") < order.index("D")
    # 융합 점수가 score에 실린다
    assert all(c.score is not None for c in fused)


async def test_rrf_rejects_missing_hash():
    # 계약: content_hash 없는 청크가 오면 조용한 오병합 대신 명시적 실패
    no_hash = RetrievedChunk(content="본문", source="s")  # content_hash=None
    with pytest.raises(ValueError):
        reciprocal_rank_fusion([[no_hash]], top_k=3)


async def test_rrf_identifies_by_hash_not_content():
    # 회귀(진단 케이스1·2): 식별은 hash로만. 같은 content라도 hash 다르면 별개,
    # 같은 hash면 content 달라도 동일 청크로 병합.
    same_hash_diff_content = [[_rc("H1", "본문A")], [_rc("H1", "본문B")]]
    fused = reciprocal_rank_fusion(same_hash_diff_content, top_k=5)
    assert len(fused) == 1  # H1 하나로 병합(중복 계수 없음)

    diff_hash_same_content = [[_rc("H1", "동일본문")], [_rc("H2", "동일본문")]]
    fused2 = reciprocal_rank_fusion(diff_hash_same_content, top_k=5)
    assert len(fused2) == 2  # content 같아도 hash 다르면 오병합 안 함


async def test_kbstore_upsert_dense_roundtrip_identity():
    # (2) 저장한 '바로 그 청크'(content·hash)가 dense_search로 되돌아옴 — store 계약 직접 검증
    embedder = FakeEmbedder()
    store = FakeKbStore()
    text = "고유내용 왕복 검증 문장."
    docs = [SourceDoc(source="src", doc_type="notice", text=text)]
    await ingest(docs, embedder=embedder, store=store)
    stored = set(store._store)  # FakeKbStore 인메모리 dict의 키 = content_hash 집합
    [vec] = await embedder.embed([text])
    got = await store.dense_search(vec, top_k=5)
    assert got, "저장분이 조회돼야 함"
    assert all(c.content_hash for c in got)  # hash가 항상 채워짐(ingest.py 재확인)
    assert any(c.content_hash in stored for c in got)  # 저장한 그 hash가 되돌아옴
