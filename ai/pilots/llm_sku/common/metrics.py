"""벤더 클라이언트 공통 계측 — 호출별 토큰·지연시간과 재시도 횟수(신뢰성 평가 축, §4.2)."""

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
    retry_count: int = 0
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
