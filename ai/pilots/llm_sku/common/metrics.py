"""벤더 클라이언트 공통 계측 — 호출별 토큰·지연시간과 계열별 재시도 횟수(신뢰성 평가 축, §4.2).

재시도 카운터는 계측 결함 패치(2026-07-08 사전 선언)로 이원화됐다:
가용성(인프라 노이즈)과 검증 실패(능력 신호)를 합산하면 신뢰성 비교가 오염되기 때문.
"""

from __future__ import annotations

from dataclasses import dataclass, field


@dataclass
class CallRecord:
    model: str
    latency_ms: int
    input_tokens: int | None
    output_tokens: int | None


@dataclass
class ClientMetrics:
    # (a) 5xx·UNAVAILABLE·overloaded — 백오프 재시도(최대 3회)
    availability_retries: int = 0
    # (b) 절단·스키마 불일치·기타 — 1회만(관대화 금지)
    validation_retries: int = 0
    calls: list[CallRecord] = field(default_factory=list)

    @property
    def total_input_tokens(self) -> int:
        return sum(c.input_tokens or 0 for c in self.calls)

    @property
    def total_output_tokens(self) -> int:
        return sum(c.output_tokens or 0 for c in self.calls)

    @property
    def total_latency_ms(self) -> int:
        return sum(c.latency_ms for c in self.calls)
