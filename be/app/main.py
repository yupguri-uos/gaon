import asyncio
import contextlib
import logging
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI

from app.chain_deps import close_retriever, current_llm_mode, current_rag_mode, warmup_retriever
from app.routers import (
    auth,
    calendar,
    children,
    documents,
    notifications,
    onboarding,
    profile,
    report,
    teacher_message,
)

logger = logging.getLogger(__name__)


async def _warmup_retriever_logged() -> None:
    # 워밍업 실패는 경고로만 남기고 앱은 살린다(SSOT §18.1) — 예: DB 일시 다운 시 기동은 되되
    # 요청 경로가 명시 에러를 보장하므로 실패가 은폐되지 않는다.
    try:
        await warmup_retriever()
    except Exception:
        logger.warning("RAG 워밍업 실패 — 첫 문서 처리 요청 시 초기화를 재시도한다", exc_info=True)


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    # RAG 워밍업(kb 모드): KURE 로드(수십 초)·풀 open을 백그라운드 태스크로 — 기동 비차단.
    # fake 모드면 warmup_retriever가 즉시 no-op.
    warmup_task = asyncio.create_task(_warmup_retriever_logged())
    yield
    if not warmup_task.done():
        warmup_task.cancel()
        with contextlib.suppress(asyncio.CancelledError):
            await warmup_task
    await close_retriever()


app = FastAPI(title="GAON API", lifespan=lifespan)

app.include_router(documents.router)
app.include_router(onboarding.router)
app.include_router(calendar.router)
app.include_router(profile.router)
app.include_router(children.router)
app.include_router(teacher_message.router)
app.include_router(report.router)
app.include_router(notifications.router)
app.include_router(auth.router, prefix="/auth", tags=["Auth"])


@app.get("/health")
def health() -> dict:
    # llm/rag 모드 노출 — 배포 서버가 fake로 떠서 더미 결과를 내는 사고를 밖에서
    # 감지할 수 있게 한다(2026-07-11 보고: 미니PC가 고정 더미 데이터만 반환 의심).
    return {"ok": True, "llm_mode": current_llm_mode(), "rag_mode": current_rag_mode()}
