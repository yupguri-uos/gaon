"""
GAON AI — 테스트용 가짜 구현 (실제 LLM/DB 없이 체인·에이전트 배선 검증)

실제 구현체(vendor LLM client, pgvector Retriever)는 결정 #4(SKU)·DB 셋업 후 추가하고
이 자리에 주입한다. 가짜는 단위 테스트/CI 용도다.
"""

from __future__ import annotations

import hashlib
import math
import re
from datetime import date
from typing import TypeVar

from pydantic import BaseModel

from gaon_shared import (
    ActionCard,
    CalendarEvent,
    DateItem,
    ExtractedItem,
    Supply,
    Term,
    TranslatedContent,
)

from gaon_ai.agents import ReplyDraft, TeacherDraft
from gaon_ai.ingest import EmbeddedChunk
from gaon_ai.llm import LLMMessage, ModelTier
from gaon_ai.rag import RetrievedChunk

M = TypeVar("M", bound=BaseModel)


class FakeLLMClient:
    """output_model 타입에 따라 정해진 더미 결과를 반환(배선 검증용)."""

    async def generate_structured(
        self, *, messages: list[LLMMessage], output_model: type[M], tier: ModelTier = ModelTier.FAST
    ) -> M:
        if output_model is ExtractedItem:
            return ExtractedItem(  # type: ignore[return-value]
                doc_type="notice",
                title="현장학습 안내",
                dates=[DateItem(label="현장학습일", date=date(2026, 7, 10))],
                supplies=["도시락", "물통", "돗자리"],
                deadline=date(2026, 7, 5),
                requires_reply=True,
                raw_text="(이미지 원문)",
            )
        if output_model is TranslatedContent:
            return TranslatedContent(  # type: ignore[return-value]
                summary_native="(모국어 요약)",
                terms=[
                    Term(
                        term_ko="현장학습",
                        literal_native="(직역)",
                        explanation_native="(문화 해설)",
                    )
                ],
            )
        if output_model is ActionCard:
            return ActionCard(  # type: ignore[return-value]
                supplies=[
                    Supply(
                        name_ko="돗자리",
                        name_native="(모국어명)",
                        explanation_native="(설명)",
                        ecommerce_keyword="돗자리",
                        # ecommerce_deeplink는 비움 → 에이전트가 채움
                    )
                ],
                calendar_events=[
                    CalendarEvent(title="현장학습", date=date(2026, 7, 10), type="event")
                ],
                # reply_draft_ko는 비움 → 회신 필요 시 별도 QUALITY 호출이 채움
            )
        if output_model is ReplyDraft:
            return ReplyDraft(reply_draft_ko="(경어체 회신 초안)")  # type: ignore[return-value]
        if output_model is TeacherDraft:
            return TeacherDraft(  # type: ignore[return-value]
                output_ko="(경어체 한국어 메시지)",
                admin_guide_native="(모국어 행정 절차 안내)",
            )
        raise NotImplementedError(f"FakeLLMClient: {output_model.__name__} 미지원")


class FailingLLMClient:
    """항상 실패 — 봉투(error)·ChainError 경로 검증용."""

    async def generate_structured(self, *, messages, output_model, tier=ModelTier.FAST):
        raise RuntimeError("LLM 호출 실패(가짜)")


class FakeRetriever:
    async def retrieve(self, queries: list[str], *, top_k: int = 4) -> list[RetrievedChunk]:
        return [
            RetrievedChunk(content=f"[근거] '{q}' 관련 학교 관행 설명", source="fixture", score=0.9)
            for q in queries[:top_k]
        ]


# ── RAG 스캐폴딩용 fake(F-CORE-2) — 실 임베딩·pgvector 없이 계약 검증 ─────────
def _tokenize(text: str) -> list[str]:
    return re.findall(r"\w+", text.lower())


def _cosine(a: list[float], b: list[float]) -> float:
    dot = sum(x * y for x, y in zip(a, b))
    norm_a = math.sqrt(sum(x * x for x in a)) or 1.0
    norm_b = math.sqrt(sum(x * x for x in b)) or 1.0
    return dot / (norm_a * norm_b)


def _to_retrieved(chunk: EmbeddedChunk, score: float) -> RetrievedChunk:
    """저장된 EmbeddedChunk → 검색 결과. 프로비넌스·content_hash를 그대로 실어 보낸다."""
    return RetrievedChunk(
        content=chunk.content,
        source=chunk.source,
        score=score,
        content_hash=chunk.content_hash,
        title=chunk.title,
        section=chunk.section,
        doc_type=chunk.doc_type,
    )


class FakeEmbedder:
    """해시 시드로 결정적 단위벡터를 만드는 가짜 임베더(모델 불요)."""

    def __init__(self, dim: int = 1024) -> None:
        self.dim = dim

    async def embed(self, texts: list[str]) -> list[list[float]]:
        return [self._vector(text) for text in texts]

    def _vector(self, text: str) -> list[float]:
        # text#i 해시 바이트를 성분으로 채우고 L2 정규화 → 결정적 단위벡터
        raw: list[float] = []
        block = 0
        while len(raw) < self.dim:
            digest = hashlib.sha256(f"{text}#{block}".encode()).digest()
            raw.extend(byte - 127.5 for byte in digest)
            block += 1
        raw = raw[: self.dim]
        norm = math.sqrt(sum(x * x for x in raw)) or 1.0
        return [x / norm for x in raw]


class FakeKbStore:
    """인메모리 kb_embeddings(dict[content_hash → EmbeddedChunk]). 멱등 업서트."""

    def __init__(self) -> None:
        self._store: dict[str, EmbeddedChunk] = {}

    async def upsert(self, chunks: list[EmbeddedChunk]) -> int:
        for chunk in chunks:
            self._store[chunk.content_hash] = chunk  # 동일 hash 덮어씀(멱등)
        return len(chunks)

    async def dense_search(self, vector: list[float], *, top_k: int) -> list[RetrievedChunk]:
        scored = [(_cosine(vector, chunk.embedding), chunk) for chunk in self._store.values()]
        scored.sort(key=lambda pair: pair[0], reverse=True)
        return [_to_retrieved(chunk, score) for score, chunk in scored[:top_k]]

    async def sparse_search(self, query: str, *, top_k: int) -> list[RetrievedChunk]:
        query_tokens = set(_tokenize(query))
        scored: list[tuple[float, EmbeddedChunk]] = []
        for chunk in self._store.values():
            overlap = len(query_tokens & set(_tokenize(chunk.content)))
            if overlap:
                scored.append((float(overlap), chunk))
        scored.sort(key=lambda pair: pair[0], reverse=True)
        return [_to_retrieved(chunk, score) for score, chunk in scored[:top_k]]
