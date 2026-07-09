"""Chain A 코어 배선 검증 — 실제 LLM/DB 없이 가짜 구현으로 계약·상태전이·불변식을 고정한다.

가짜는 gaon_ai.testing(FakeLLMClient/FailingLLMClient/FakeRetriever), 헬퍼는
gaon_ai.agents.coupang_search_url 를 쓴다. 실제 LLM 호출은 하지 않는다.
대응: SSOT §9(상태 전이)·§8(에이전트 I/O)·§17.4(child_id 백필)·F-DOC-8(회신/딥링크).
"""

from __future__ import annotations

import re
from datetime import date, datetime, timezone

import pytest

from gaon_ai.agents import LifestyleActionAgent, coupang_search_url
from gaon_ai.chain_a import ChainError, run_chain_a_core
from gaon_ai.llm import LLMClient, ModelTier, TextPart
from gaon_ai.rag import Retriever
from gaon_ai.testing import FailingLLMClient, FakeLLMClient, FakeRetriever
from gaon_shared import (
    ActionCard,
    CalendarEvent,
    ChildInfo,
    Document,
    ExtractedItem,
    LifestyleActionInput,
    Supply,
    Term,
    TranslatedContent,
    User,
)


def build_user() -> User:
    return User(
        user_id="u1",
        origin_country="VN",
        native_language="vi",
        created_at=datetime(2026, 6, 30, 9, 0),
    )


def build_document(
    child_id: str | None = "child-1",
    created_at: datetime = datetime(2026, 6, 30, 9, 0),
) -> Document:
    return Document(
        document_id="doc-1",
        user_id="u1",
        child_id=child_id,
        image_ref="minio://bucket/doc-1.jpg",
        created_at=created_at,
    )


class HallucinatingLLMClient(FakeLLMClient):
    """결정적 필드(child_id·딥링크)를 LLM이 환각으로 채워 오는 상황 재현 — 코드 덮어쓰기 검증용."""

    async def generate_structured(self, *, messages, output_model, tier=ModelTier.FAST):
        if output_model is ActionCard:
            return ActionCard(
                supplies=[
                    Supply(
                        name_ko="돗자리",
                        name_native="(모국어명)",
                        explanation_native="(설명)",
                        ecommerce_keyword="돗자리",
                        ecommerce_deeplink="https://evil.example/phish",  # 환각 URL
                    )
                ],
                calendar_events=[
                    CalendarEvent(
                        title="현장학습",
                        date=date(2026, 7, 10),
                        type="event",
                        child_id="hallucinated-child",  # 환각 child_id
                    )
                ],
            )
        return await super().generate_structured(
            messages=messages, output_model=output_model, tier=tier
        )


class RecordingLLMClient(FakeLLMClient):
    """파싱 단계의 user 텍스트를 캡처 — 기준일(ISO)이 프롬프트에 박히는지 검증용."""

    def __init__(self) -> None:
        self.parsing_texts: list[str] = []
        self.lifestyle_texts: list[str] = []

    async def generate_structured(self, *, messages, output_model, tier=ModelTier.FAST):
        if output_model is ExtractedItem:
            self.parsing_texts += [
                part.text
                for message in messages
                for part in message.content
                if isinstance(part, TextPart)
            ]
        if output_model is ActionCard:
            self.lifestyle_texts += [
                part.text
                for message in messages
                for part in message.content
                if isinstance(part, TextPart)
            ]
        return await super().generate_structured(
            messages=messages, output_model=output_model, tier=tier
        )


def test_fakes_satisfy_protocols():
    # 6) runtime_checkable Protocol 만족(구조적 타이핑)
    assert isinstance(FakeLLMClient(), LLMClient)
    assert isinstance(FakeRetriever(), Retriever)


async def test_status_transitions_happy_path():
    # 7) 정상 실행 시 on_status 전이 == [parsing, translating, action, done]
    statuses: list[str] = []
    result = await run_chain_a_core(
        build_document(),
        build_user(),
        llm=FakeLLMClient(),
        retriever=FakeRetriever(),
        on_status=statuses.append,
    )
    assert statuses == ["parsing", "translating", "action", "done"]
    assert isinstance(result.extracted, ExtractedItem)


async def test_received_date_autoinjected_from_created_at():
    # 8) received_date를 직접 안 줘도 Document.created_at에서 자동 주입 → 에러 없이 동작
    result = await run_chain_a_core(
        build_document(),
        build_user(),
        llm=FakeLLMClient(),
        retriever=FakeRetriever(),
    )
    assert result.extracted.deadline is not None  # 파싱 결과 생성됨(기준일 주입 성공)


async def test_coupang_deeplink_assembled_by_code():
    # 9) supplies[0].ecommerce_deeplink == coupang_search_url(keyword) — 코드가 조립
    result = await run_chain_a_core(
        build_document(),
        build_user(),
        llm=FakeLLMClient(),
        retriever=FakeRetriever(),
    )
    supply = result.action_card.supplies[0]
    assert supply.ecommerce_deeplink == coupang_search_url(supply.ecommerce_keyword)
    # 언어 계약 가드(SSOT v0.8.6): 쿠팡 검색어는 한국어 — mock이 모국어로 바뀌면 여기서 잡는다
    assert re.search(r"[가-힣]", supply.ecommerce_keyword)


async def test_calendar_event_child_id_backfilled():
    # 10) calendar_events[0].child_id == document.child_id — 체인이 백필(§17.4)
    document = build_document(child_id="child-42")
    result = await run_chain_a_core(
        document,
        build_user(),
        llm=FakeLLMClient(),
        retriever=FakeRetriever(),
    )
    assert result.action_card.calendar_events[0].child_id == document.child_id == "child-42"


async def test_reply_draft_cleared_when_no_reply_required():
    # 11) requires_reply=False면 LifestyleActionAgent 결과 reply_draft_ko is None
    extracted = ExtractedItem(
        doc_type="notice",
        title="알림장",
        supplies=["물통"],
        requires_reply=False,
        raw_text="(원문)",
    )
    translated = TranslatedContent(
        summary_native="(요약)",
        terms=[Term(term_ko="알림장", literal_native="(직역)", explanation_native="(해설)")],
    )
    resp = await LifestyleActionAgent(FakeLLMClient()).run(
        LifestyleActionInput(
            extracted_item=extracted,
            translated=translated,
            native_language="vi",
        )
    )
    assert resp.status == "ok"
    assert resp.data is not None
    assert resp.data.reply_draft_ko is None


async def test_hallucinated_child_id_and_deeplink_overwritten_by_code():
    # 진단 프로브 실증분 고정: LLM이 child_id·딥링크를 환각으로 채워도 코드가 무조건 덮어쓴다
    document = build_document(child_id="child-7")
    result = await run_chain_a_core(
        document,
        build_user(),
        llm=HallucinatingLLMClient(),
        retriever=FakeRetriever(),
    )
    event = result.action_card.calendar_events[0]
    supply = result.action_card.supplies[0]
    assert event.child_id == document.child_id == "child-7"  # "hallucinated-child" 차단
    assert supply.ecommerce_deeplink == coupang_search_url(supply.ecommerce_keyword)


async def test_received_date_uses_kst_for_utc_created_at():
    # UTC 6/30 16:00 == KST 7/1 01:00 → 상대날짜 해석 기준일은 2026-07-01이어야 한다
    llm = RecordingLLMClient()
    await run_chain_a_core(
        build_document(created_at=datetime(2026, 6, 30, 16, 0, tzinfo=timezone.utc)),
        build_user(),
        llm=llm,
        retriever=FakeRetriever(),
    )
    parsing_prompt = "\n".join(llm.parsing_texts)
    assert "2026-07-01" in parsing_prompt
    assert "2026-06-30" not in parsing_prompt


async def test_child_info_reaches_lifestyle_prompt():
    # §17.10: child_info가 run_chain_a_core에 주어지면 LifestyleAction 프롬프트에 학년이 실린다
    llm = RecordingLLMClient()
    await run_chain_a_core(
        build_document(),
        build_user(),
        llm=llm,
        retriever=FakeRetriever(),
        child_info=ChildInfo(grade="elem_2"),
    )
    lifestyle_prompt = "\n".join(llm.lifestyle_texts)
    assert "elem_2" in lifestyle_prompt


async def test_lifestyle_prompt_forbids_document_supplies():
    # §17.11 1단: 제출 서류는 supplies 금지 — 가드 문구가 실제 LLM 호출 프롬프트에 실리는지 검증
    llm = RecordingLLMClient()
    await run_chain_a_core(
        build_document(),
        build_user(),
        llm=llm,
        retriever=FakeRetriever(),
    )
    lifestyle_prompt = "\n".join(llm.lifestyle_texts)
    assert "구매 가능한 실물만" in lifestyle_prompt
    assert "신청서·동의서·조사서" in lifestyle_prompt


async def test_no_child_info_shows_unspecified_in_lifestyle_prompt():
    # child_info=None(기본값)이면 학년 자리에 '미지정'만 들어가고 크래시하지 않는다
    llm = RecordingLLMClient()
    await run_chain_a_core(
        build_document(),
        build_user(),
        llm=llm,
        retriever=FakeRetriever(),
    )
    lifestyle_prompt = "\n".join(llm.lifestyle_texts)
    assert "미지정" in lifestyle_prompt


async def test_failing_llm_raises_chain_error_at_parsing():
    # 12) FailingLLMClient → ChainError(agent=="document_parsing"), on_status는 [parsing]에서 멈춤
    statuses: list[str] = []
    with pytest.raises(ChainError) as excinfo:
        await run_chain_a_core(
            build_document(),
            build_user(),
            llm=FailingLLMClient(),
            retriever=FakeRetriever(),
            on_status=statuses.append,
        )
    assert excinfo.value.agent == "document_parsing"
    assert statuses == ["parsing"]
