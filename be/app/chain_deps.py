"""Chain A(run_chain_a_core)에 주입할 LLMClient/Retriever 팩토리.

결정 #4(SSOT §6) LLM SKU가 아직 미확정이라 ai/gaon_ai/llm.py에는 Protocol만 있고
실제 벤더 구현체가 없다. 그 전까지는 gaon_ai.testing의 Fake로 배선(업로드→상태전이→
DB 저장→조회)을 검증한다 — 실제 문서 내용과 무관하게 고정된 더미 결과를 반환하므로
데모/실서비스에는 쓸 수 없다. SKU 확정되면 이 두 함수만 실구현으로 바꾸면 된다.
"""

from __future__ import annotations

from gaon_ai.llm import LLMClient
from gaon_ai.rag import Retriever
from gaon_ai.testing import FakeLLMClient, FakeRetriever


def get_llm_client() -> LLMClient:
    return FakeLLMClient()


def get_retriever() -> Retriever:
    return FakeRetriever()
