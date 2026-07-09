"""Chain A(run_chain_a_core)에 주입할 LLMClient/Retriever 팩토리.

결정 #4(SSOT §6, 2026-07-09): 생성 LLM = 단일 Gemini — 기본은 실 GeminiLLMClient를
배선하고, GAON_LLM_MODE=fake일 때만 Fake로 대체한다(로컬 개발·배선 테스트용).
gemini 모드에서 GOOGLE_API_KEY가 없으면 RuntimeError를 그대로 전파한다 —
시연 중 env 누락이 더미 결과로 은폐되는 사고를 막기 위해 Fake 자동 폴백 금지.
"""

from __future__ import annotations

import os
from functools import lru_cache
from pathlib import Path

from gaon_ai.llm import LLMClient
from gaon_ai.llm_gemini import GeminiLLMClient, mime_for_ext
from gaon_ai.rag import Retriever
from gaon_ai.testing import FakeLLMClient, FakeRetriever

from app import storage


def _s3_image_loader(image_ref: str) -> tuple[bytes, str]:
    # 체인이 주는 image_ref = bare 버킷 키(documents.image_ref, 예: {user_id}/{uuid}.jpg).
    # mime은 확장자 기반 — object_key()가 업로드 시 확장자를 보존하므로 안전.
    return storage.download_image(image_ref), mime_for_ext(Path(image_ref).suffix)


@lru_cache(maxsize=1)
def _gemini_singleton() -> GeminiLLMClient:
    # 서비스 상주 싱글턴 — 요청마다 genai.Client를 재생성하지 않는다
    return GeminiLLMClient(image_loader=_s3_image_loader)


def get_llm_client() -> LLMClient:
    # 빈 값도 기본으로 — docker compose env_file은 `GAON_LLM_MODE=`(빈 값)를 빈 문자열로 싣는다
    mode = os.environ.get("GAON_LLM_MODE") or "gemini"
    if mode == "fake":
        return FakeLLMClient()
    if mode == "gemini":
        return _gemini_singleton()
    raise RuntimeError(f"알 수 없는 GAON_LLM_MODE: {mode!r} (gemini | fake)")


def get_retriever() -> Retriever:
    # TODO(BE): 실 Retriever(pgvector) 배선은 DB 풀 주입 조율 후 — LLM 승격 범위 밖.
    return FakeRetriever()
