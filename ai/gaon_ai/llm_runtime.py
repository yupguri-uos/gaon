"""
LLM 호출 공통 런타임 — 이원화 재시도 정책 + 누적 계측 (파일럿 llm_sku 승격본).

이원화 재시도(정책은 파일럿 검증값 그대로, 변경 금지):
(a) 가용성(5xx·UNAVAILABLE·overloaded): 최대 3회 지수 백오프(2s→8s→30s) — 인프라 노이즈.
(b) 검증 실패(절단·스키마 불일치)·기타: 1회만 — 모델 능력 신호, 관대화 금지.

최종 실패는 LLMCallError로 감싸 계열 마커를 남긴다 — 에러 문자열에
"[availability]"/"[validation]" 접두가 실려 로그에서 실패 계열 분류가 가능하다.
"""

from __future__ import annotations

import asyncio
from dataclasses import dataclass
from typing import Any, Awaitable, Callable

# (a) 가용성 재시도 백오프 — 최대 3회(파일럿 사전 선언값 고정, 인자화 금지)
BACKOFF_SECONDS: tuple[float, ...] = (2.0, 8.0, 30.0)


@dataclass
class ClientMetrics:
    """서비스 상주 클라이언트의 누적 카운터.

    호출별 상세(CallRecord 목록)는 파일럿 계측용이었다 — 상주 객체에서 무한 append는
    메모리 누수라 누적 카운터로 단순화했고, 호출별 상세는 클라이언트가 logging.debug로 남긴다.
    """

    call_count: int = 0
    total_input_tokens: int = 0
    total_output_tokens: int = 0
    total_latency_ms: int = 0
    # (a) 5xx·UNAVAILABLE·overloaded — 백오프 재시도(최대 3회)
    availability_retries: int = 0
    # (b) 절단·스키마 불일치·기타 — 1회만(관대화 금지)
    validation_retries: int = 0

    def record_call(
        self, *, latency_ms: int, input_tokens: int | None, output_tokens: int | None
    ) -> None:
        self.call_count += 1
        self.total_latency_ms += latency_ms
        self.total_input_tokens += input_tokens or 0
        self.total_output_tokens += output_tokens or 0


class LLMCallError(RuntimeError):
    """재시도 소진 후 최종 실패. kind는 로그 실패 계열 분류용 마커."""

    def __init__(self, kind: str, cause: Exception) -> None:
        super().__init__(f"[{kind}] {cause}")
        self.kind = kind  # "availability" | "validation" | "other"
        self.cause = cause


async def call_with_retries(
    attempt: Callable[[], Awaitable[Any]],
    *,
    is_availability: Callable[[Exception], bool],
    is_validation: Callable[[Exception], bool],
    metrics: ClientMetrics,
    sleep: Callable[[float], Awaitable[None]] = asyncio.sleep,
) -> Any:
    """이원화 재시도 루프. 가용성·검증 예산은 독립(5xx 재시도 후 절단이 나도 1회는 보장)."""
    availability_used = 0
    validation_retried = False
    while True:
        try:
            return await attempt()
        except Exception as exc:
            if is_availability(exc):
                if availability_used >= len(BACKOFF_SECONDS):
                    raise LLMCallError("availability", exc) from exc
                delay = BACKOFF_SECONDS[availability_used]
                availability_used += 1
                metrics.availability_retries += 1
                await sleep(delay)
                continue
            # (b) 검증 실패·기타 — 1회만(능력 신호, 관대화 금지)
            if validation_retried:
                kind = "validation" if is_validation(exc) else "other"
                raise LLMCallError(kind, exc) from exc
            validation_retried = True
            metrics.validation_retries += 1
