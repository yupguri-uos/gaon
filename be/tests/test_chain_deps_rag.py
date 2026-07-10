"""chain_deps.get_retriever — GAON_RAG_MODE 분기·프록시 수명주기 회귀 (§18.1).

rag 의존성(sentence-transformers/torch)이 없는 환경에서도 돌아야 한다 —
모델 로드·실 DB 연결이 일어나는 경로는 테스트하지 않는다(배포 후 운영 체크리스트 몫).
"""

from __future__ import annotations

import sys

import pytest
from gaon_ai.testing import FakeRetriever

from app import chain_deps
from app.chain_deps import _KbRetrieverProxy, get_retriever


@pytest.fixture(autouse=True)
def _reset_kb_singleton():
    # 테스트 간 프록시 싱글턴 격리 — lru_cache가 아니라 명시 리셋 헬퍼를 쓴다
    chain_deps._reset_retriever_for_tests()
    yield
    chain_deps._reset_retriever_for_tests()


def test_fake_mode_returns_fake_retriever(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("GAON_RAG_MODE", "fake")
    assert isinstance(get_retriever(), FakeRetriever)


def test_empty_mode_falls_back_to_kb(monkeypatch: pytest.MonkeyPatch) -> None:
    # compose env_file은 `GAON_RAG_MODE=`(빈 값)를 빈 문자열로 싣는다 → 기본(kb)으로 가야 함
    monkeypatch.setenv("GAON_RAG_MODE", "")
    assert isinstance(get_retriever(), _KbRetrieverProxy)


def test_unknown_mode_raises_with_mode_string(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("GAON_RAG_MODE", "banana")
    with pytest.raises(RuntimeError, match="banana"):
        get_retriever()


def test_kb_proxy_is_singleton(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("GAON_RAG_MODE", "kb")
    assert get_retriever() is get_retriever()


async def test_kb_retrieve_without_rag_deps_raises_install_hint(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("GAON_RAG_MODE", "kb")
    # sys.modules에 None을 심어 임포트 실패를 시뮬레이션(의존성 설치 여부 무관, 실 다운로드 금지)
    monkeypatch.setitem(sys.modules, "sentence_transformers", None)
    retriever = get_retriever()
    with pytest.raises(RuntimeError, match=r'pip install -e "ai\[rag\]"'):
        await retriever.retrieve(["가정통신문"], top_k=1)
