"""Chain B(교사 소통) 배선 검증 — 가짜 LLM으로 계약·에코·에러 경로를 고정한다.

대응: SSOT §8(에이전트 ④ I/O)·§9(Chain B)·F-TCH-1~4. 실제 LLM 호출은 하지 않는다.
"""

from __future__ import annotations

import pytest

from gaon_ai.agents import TeacherCommunicationAgent
from gaon_ai.chain_a import ChainError
from gaon_ai.chain_b import run_chain_b
from gaon_ai.testing import FailingLLMClient, FakeLLMClient
from gaon_shared import ChildInfo, TeacherCommInput, TeacherMessage


def build_input(situation: str = "absence") -> TeacherCommInput:
    return TeacherCommInput(
        input_native="(모국어 입력)",
        situation=situation,
        native_language="vi",
        child_info=ChildInfo(grade="elem_1", class_no="3"),
    )


async def test_teacher_message_echoes_input_and_fills_generated():
    # situation·input_native은 입력 에코(코드가 채움), output_ko·admin_guide_native는 LLM 생성
    resp = await TeacherCommunicationAgent(FakeLLMClient()).run(build_input())
    assert resp.status == "ok"
    assert resp.data is not None
    msg = resp.data
    assert isinstance(msg, TeacherMessage)
    assert msg.situation == "absence"
    assert msg.input_native == "(모국어 입력)"
    assert msg.output_ko
    assert msg.admin_guide_native


@pytest.mark.parametrize("situation", ["absence", "sick_note", "consultation", "custom"])
async def test_all_situations_ok(situation):
    resp = await TeacherCommunicationAgent(FakeLLMClient()).run(build_input(situation))
    assert resp.status == "ok"
    assert resp.data is not None
    assert resp.data.situation == situation


async def test_failing_llm_returns_error_envelope():
    resp = await TeacherCommunicationAgent(FailingLLMClient()).run(build_input())
    assert resp.status == "error"
    assert resp.data is None


async def test_run_chain_b_returns_message_on_success():
    msg = await run_chain_b(build_input(), llm=FakeLLMClient())
    assert isinstance(msg, TeacherMessage)
    assert msg.output_ko


async def test_run_chain_b_raises_chain_error_on_failure():
    with pytest.raises(ChainError) as excinfo:
        await run_chain_b(build_input(), llm=FailingLLMClient())
    assert excinfo.value.agent == "teacher_communication"
