"""
재시도 정책 — 계측 결함 패치(2026-07-08 사전 선언, README '신뢰성 정책' 절).

이원화(계열별 카운터 분리 기록 — 신뢰성 평가 축 오염 방지):
(a) 가용성(5xx·UNAVAILABLE·overloaded): 최대 3회 지수 백오프(2s→8s→30s) — 인프라 노이즈.
(b) 검증 실패(절단·스키마 불일치)·기타: 1회 유지 — 능력 신호, 관대화 금지.

최종 실패는 PilotCallError로 감싸 계열 마커를 남긴다 — AgentResponse.error 문자열에
"[availability]"/"[validation]" 접두가 실려 run_report의 실패 분류가 가능해진다.
"""

from __future__ import annotations

import asyncio
from typing import Any, Awaitable, Callable

from common.metrics import ClientMetrics

# (a) 가용성 재시도 백오프 — 최대 3회(사전 선언 고정, 인자화 금지)
BACKOFF_SECONDS: tuple[float, ...] = (2.0, 8.0, 30.0)


class StructuredOutputParseError(RuntimeError):
    """구조화 출력 파싱 실패(절단·스키마 불일치) — 검증 실패 계열(능력 신호)."""


class PilotCallError(RuntimeError):
    """재시도 소진 후 최종 실패. kind는 run_report 실패 분류용 마커."""

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
                    raise PilotCallError("availability", exc) from exc
                delay = BACKOFF_SECONDS[availability_used]
                availability_used += 1
                metrics.availability_retries += 1
                await sleep(delay)
                continue
            # (b) 검증 실패·기타 — 1회만(능력 신호, 관대화 금지)
            if validation_retried:
                kind = "validation" if is_validation(exc) else "other"
                raise PilotCallError(kind, exc) from exc
            validation_retried = True
            metrics.validation_retries += 1
