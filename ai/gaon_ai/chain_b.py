"""
GAON AI — Chain B 오케스트레이션 (교사 소통, 시나리오2 / §3·§9)

Chain B는 Teacher Communication 단독이다(RAG·상태전이 없음). run_chain_a_core와 대칭으로
BE에 얇은 진입점을 제공한다: 봉투를 벗기고 실패 시 ChainError를 던진다. 전송은 하지 않고
생성까지만(결정 #2, F-TCH-3) — 반환한 TeacherMessage를 BE가 저장·응답하고 사용자가 수동 전송한다.
"""

from __future__ import annotations

from gaon_shared import TeacherCommInput, TeacherMessage

from gaon_ai.agents import TeacherCommunicationAgent
from gaon_ai.chain_a import ChainError  # 체인 공통 에러(에이전트 태깅) 재사용
from gaon_ai.llm import LLMClient


async def run_chain_b(data: TeacherCommInput, *, llm: LLMClient) -> TeacherMessage:
    """교사 소통 입력 1건 → 경어체 메시지 + 행정 안내(TeacherMessage)."""
    resp = await TeacherCommunicationAgent(llm).run(data)
    if resp.status != "ok" or resp.data is None:
        raise ChainError(resp.agent, resp.error)
    return resp.data
