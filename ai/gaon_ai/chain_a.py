"""
GAON AI — Chain A 코어 오케스트레이션 (문서 처리, 시나리오1 / §3·§9)

순서: DocParsing → (RAG 검색) → CulturalTranslation → LifestyleAction.
Document.status 전이(§9): parsing → translating → action → done.
상태 전이는 on_status 콜백으로 외부(BE)가 받아 Document.status/폴링(F-DOC-4)에 반영한다.
체인은 DB·스토리지에 직접 의존하지 않는다(에이전트·검색 추상화에만 의존).
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Callable

from gaon_shared import (
    ActionCard,
    CulturalTranslationInput,
    DocParsingInput,
    DocStatus,
    Document,
    ExtractedItem,
    LifestyleActionInput,
    TranslatedContent,
    User,
)

from gaon_ai.agents import (
    CulturalTranslationAgent,
    DocumentParsingAgent,
    LifestyleActionAgent,
)
from gaon_ai.llm import LLMClient
from gaon_ai.rag import Retriever, build_rag_queries, chunks_to_context


class ChainError(RuntimeError):
    """체인 단계 실패. 어떤 에이전트에서 났는지 agent에 담는다."""

    def __init__(self, agent: str, message: str | None) -> None:
        super().__init__(f"[{agent}] {message}")
        self.agent = agent


@dataclass
class ChainAResult:
    extracted: ExtractedItem
    translated: TranslatedContent
    action_card: ActionCard


StatusCallback = Callable[[DocStatus], None]


async def run_chain_a_core(
    document: Document,
    user: User,
    *,
    llm: LLMClient,
    retriever: Retriever,
    on_status: StatusCallback | None = None,
) -> ChainAResult:
    """문서 1건에 대해 Chain A 전체(파싱 → 번역 → 행동)를 실행한다."""

    def emit(s: DocStatus) -> None:
        if on_status is not None:
            on_status(s)

    # 1) 파싱
    emit("parsing")
    parse = await DocumentParsingAgent(llm).run(
        DocParsingInput(
            image_ref=document.image_ref,
            user_profile=user,
            received_date=document.created_at.date(),  # 상대 날짜 해석 기준일(§8 v0.6.1)
        )
    )
    if parse.status != "ok" or parse.data is None:
        raise ChainError(parse.agent, parse.error)
    extracted = parse.data

    # 2) RAG 검색(체인 단계, §9) — supplies·용어로 kb_embeddings 조회 → rag_context 주입
    chunks = await retriever.retrieve(build_rag_queries(extracted))
    rag_context = chunks_to_context(chunks)

    # 3) 문화맥락 번역·해설
    emit("translating")
    trans = await CulturalTranslationAgent(llm).run(
        CulturalTranslationInput(
            extracted_item=extracted,
            native_language=user.native_language,
            rag_context=rag_context,
        )
    )
    if trans.status != "ok" or trans.data is None:
        raise ChainError(trans.agent, trans.error)

    # 4) 행동 카드(Lifestyle Action) — Chain A 마무리
    emit("action")
    act = await LifestyleActionAgent(llm).run(
        LifestyleActionInput(
            extracted_item=extracted,
            translated=trans.data,
            native_language=user.native_language,
        )
    )
    if act.status != "ok" or act.data is None:
        raise ChainError(act.agent, act.error)
    action_card = act.data

    # child_id 백필(§17.4): 에이전트는 child를 모르므로 체인이 Document.child_id로 채운다
    for event in action_card.calendar_events:
        if event.child_id is None:
            event.child_id = document.child_id

    emit("done")
    return ChainAResult(extracted=extracted, translated=trans.data, action_card=action_card)
