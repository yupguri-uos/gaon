"""Chain A 코어 배선 검증 — 실제 LLM/DB 없이 가짜 구현으로 계약·상태전이·불변식을 고정한다.

가짜는 gaon_ai.testing(FakeLLMClient/FailingLLMClient/FakeRetriever), 헬퍼는
gaon_ai.agents.coupang_search_url 를 쓴다. 실제 LLM 호출은 하지 않는다.
대응: SSOT §9(상태 전이)·§8(에이전트 I/O)·§17.4(child_id 백필)·F-DOC-8(회신/딥링크).
"""

from __future__ import annotations

from datetime import datetime

import pytest

from gaon_ai.agents import LifestyleActionAgent, coupang_search_url
from gaon_ai.chain_a import ChainError, run_chain_a_core
from gaon_ai.llm import LLMClient
from gaon_ai.rag import Retriever
from gaon_ai.testing import FailingLLMClient, FakeLLMClient, FakeRetriever
from gaon_shared import (
    Document,
    ExtractedItem,
    LifestyleActionInput,
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


def build_document(child_id: str | None = "child-1") -> Document:
    return Document(
        document_id="doc-1",
        user_id="u1",
        child_id=child_id,
        image_ref="minio://bucket/doc-1.jpg",
        created_at=datetime(2026, 6, 30, 9, 0),
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
