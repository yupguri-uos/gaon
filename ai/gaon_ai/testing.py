"""
GAON AI — 테스트용 가짜 구현 (실제 LLM/DB 없이 체인·에이전트 배선 검증)

실제 구현체(vendor LLM client, pgvector Retriever)는 결정 #4(SKU)·DB 셋업 후 추가하고
이 자리에 주입한다. 가짜는 단위 테스트/CI 용도다.
"""

from __future__ import annotations

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
