"""Chain A(run_chain_a_core)에 주입할 LLMClient/Retriever 팩토리.

결정 #4(SSOT §6, 2026-07-09): 생성 LLM = 단일 Gemini — 기본은 실 GeminiLLMClient를
배선하고, GAON_LLM_MODE=fake일 때만 Fake로 대체한다(로컬 개발·배선 테스트용).
gemini 모드에서 GOOGLE_API_KEY가 없으면 RuntimeError를 그대로 전파한다 —
시연 중 env 누락이 더미 결과로 은폐되는 사고를 막기 위해 Fake 자동 폴백 금지.

배선 설계 확정(SSOT §18.1, 2026-07-10): Retriever도 같은 원칙 — 기본(GAON_RAG_MODE=kb)은
실 HybridRetriever(KURE+pgvector, dense-only), fake일 때만 FakeRetriever. kb 모드에서
rag 의존성이 없으면 명시 에러(조용한 Fake 폴백 금지). KURE 모델 로드(수십 초)는
_KbRetrieverProxy가 첫 검색 시점에 to_thread로 수행해 이벤트 루프를 막지 않는다.
"""

from __future__ import annotations

import asyncio
import os
from functools import lru_cache
from pathlib import Path
from typing import TYPE_CHECKING

from gaon_ai.llm import LLMClient
from gaon_ai.llm_gemini import GeminiLLMClient, mime_for_ext
from gaon_ai.rag import HybridRetriever, RetrievedChunk, Retriever
from gaon_ai.testing import FakeLLMClient, FakeRetriever

from app import storage
from app.config import settings

if TYPE_CHECKING:
    from gaon_ai.stores.pgvector import PgVectorKbStore


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


class _KbRetrieverProxy:
    """kb 모드 Retriever(Protocol 충족) — 실 구성(HybridRetriever)을 첫 검색 시점까지 미룬다.

    KURE 모델 로드(SentenceTransformer 생성자, 수십 초)는 동기 연산이라 이벤트 루프 안에서
    실행되면 단일 워커 uvicorn이 통째로 멈춘다(/health 포함). 그래서 _build()는 반드시
    asyncio.to_thread로만 호출한다. Lock으로 동시 첫 호출의 중복 빌드를 막고,
    초기화 이후 호출은 Lock 없이 내부 retriever에 위임한다.
    """

    def __init__(self) -> None:
        self._inner: HybridRetriever | None = None
        self._store: PgVectorKbStore | None = None  # close()용 — 풀 수명주기는 자체 소유
        self._lock = asyncio.Lock()

    async def retrieve(self, queries: list[str], *, top_k: int = 4) -> list[RetrievedChunk]:
        if self._inner is None:
            async with self._lock:
                if self._inner is None:
                    await asyncio.to_thread(self._build)
        assert self._inner is not None  # _build 성공 시 항상 설정됨
        return await self._inner.retrieve(queries, top_k=top_k)

    def _build(self) -> None:
        # 무거운 의존성(sentence-transformers/torch, psycopg_pool)은 여기서만 지연 임포트 —
        # rag extra 미설치 환경에서도 모듈 임포트·fake 모드는 동작해야 한다.
        try:
            from gaon_ai.embedders.kure import KureEmbedder
            from gaon_ai.stores.pgvector import PgVectorKbStore

            embedder = KureEmbedder()  # 모델 로드(무겁다) — to_thread 안에서만 실행
            store = PgVectorKbStore.from_database_url(settings.database_url)
        except ImportError as exc:
            raise RuntimeError(
                'GAON_RAG_MODE=kb에는 rag 의존성이 필요하다: pip install -e "ai[rag]"'
            ) from exc
        self._store = store
        self._inner = HybridRetriever(embedder, store, use_sparse=False)

    async def close(self) -> None:
        """자체 소유 DB 풀을 닫는다(lifespan shutdown). 미초기화면 no-op."""
        if self._store is not None:
            await self._store.close()


# 프로세스당 1개 — KURE 모델·DB 풀을 요청마다 재생성하지 않는다.
# lru_cache 대신 모듈 변수 + 명시적 리셋 헬퍼(테스트 격리용)를 쓴다.
_kb_retriever: _KbRetrieverProxy | None = None


def _reset_retriever_for_tests() -> None:
    global _kb_retriever
    _kb_retriever = None


def get_retriever() -> Retriever:
    # 빈 값도 기본으로 — docker compose env_file은 `GAON_RAG_MODE=`(빈 값)를 빈 문자열로 싣는다
    mode = os.environ.get("GAON_RAG_MODE") or "kb"
    if mode == "fake":
        return FakeRetriever()
    if mode == "kb":
        global _kb_retriever
        if _kb_retriever is None:
            _kb_retriever = _KbRetrieverProxy()
        return _kb_retriever
    raise RuntimeError(f"알 수 없는 GAON_RAG_MODE: {mode!r} (kb | fake)")


async def warmup_retriever() -> None:
    """kb 모드일 때 모델 로드·풀 open·쿼리 경로까지 실검색 1회로 예열(기동 첫 요청 지연 방지).

    fake 모드면 no-op. 실패는 예외 전파 — 호출자(main.py lifespan)가 로깅만 하고 앱은 살린다
    (요청 경로가 어차피 명시 에러를 보장하므로 은폐되지 않음).
    """
    mode = os.environ.get("GAON_RAG_MODE") or "kb"
    if mode != "kb":
        return
    retriever = get_retriever()
    await retriever.retrieve(["가정통신문"], top_k=1)


async def close_retriever() -> None:
    """kb 프록시가 열어둔 DB 풀을 닫는다(main.py lifespan shutdown). 미초기화면 no-op."""
    if _kb_retriever is not None:
        await _kb_retriever.close()
