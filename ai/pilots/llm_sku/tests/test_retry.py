"""이원화 재시도 정책 단위 테스트 — 모의 예외만 사용, 실 API·실제 sleep 없음.

계측 결함 패치(2026-07-08 사전 선언): 가용성(5xx 계열)=최대 3회 지수 백오프(2s→8s→30s),
검증 실패(절단·스키마)=1회 유지(능력 신호, 관대화 금지), 계열별 카운터 분리.
실행: pytest ai/pilots/llm_sku/tests
"""

import pytest

from common.metrics import ClientMetrics
from common.retry import BACKOFF_SECONDS, PilotCallError, call_with_retries


class FakeAvailabilityError(Exception):
    """모의 5xx·UNAVAILABLE·overloaded."""


class FakeValidationError(Exception):
    """모의 절단·스키마 불일치."""


def _is_availability(exc: Exception) -> bool:
    return isinstance(exc, FakeAvailabilityError)


def _is_validation(exc: Exception) -> bool:
    return isinstance(exc, FakeValidationError)


class Harness:
    """호출 시나리오(예외 나열 후 성공)와 sleep 기록기."""

    def __init__(self, outcomes):
        self.outcomes = list(outcomes)  # Exception이면 raise, 아니면 return
        self.attempts = 0
        self.sleeps: list[float] = []
        self.metrics = ClientMetrics()

    async def attempt(self):
        self.attempts += 1
        outcome = self.outcomes.pop(0)
        if isinstance(outcome, Exception):
            raise outcome
        return outcome

    async def sleep(self, seconds: float) -> None:
        self.sleeps.append(seconds)  # 실제 대기 없음 — 백오프 스케줄만 검증

    async def run(self):
        return await call_with_retries(
            self.attempt,
            is_availability=_is_availability,
            is_validation=_is_validation,
            metrics=self.metrics,
            sleep=self.sleep,
        )


async def test_success_first_try_no_retries():
    h = Harness(["ok"])
    assert await h.run() == "ok"
    assert (h.metrics.availability_retries, h.metrics.validation_retries) == (0, 0)
    assert h.sleeps == []


async def test_availability_backoff_then_success():
    # 5xx 2회 후 성공 → 백오프 2s, 8s 소비
    h = Harness([FakeAvailabilityError("503"), FakeAvailabilityError("503"), "ok"])
    assert await h.run() == "ok"
    assert h.metrics.availability_retries == 2
    assert h.metrics.validation_retries == 0
    assert h.sleeps == [2.0, 8.0]


async def test_availability_exhausts_three_backoffs_then_raises():
    # 5xx 연속 → 3회(2s→8s→30s) 재시도 후 [availability]로 최종 실패
    h = Harness([FakeAvailabilityError("503")] * 4)
    with pytest.raises(PilotCallError) as ei:
        await h.run()
    assert ei.value.kind == "availability"
    assert str(ei.value).startswith("[availability]")
    assert h.attempts == 4  # 최초 1 + 재시도 3
    assert h.sleeps == list(BACKOFF_SECONDS)
    assert h.metrics.availability_retries == 3


async def test_validation_single_retry_then_success():
    # 절단·스키마 실패 1회 → 즉시(백오프 없음) 1회 재시도
    h = Harness([FakeValidationError("truncated"), "ok"])
    assert await h.run() == "ok"
    assert h.metrics.validation_retries == 1
    assert h.sleeps == []


async def test_validation_second_failure_raises_without_leniency():
    # 검증 실패는 1회만 — 관대화 금지, [validation] 마커로 최종 실패
    h = Harness([FakeValidationError("truncated")] * 2)
    with pytest.raises(PilotCallError) as ei:
        await h.run()
    assert ei.value.kind == "validation"
    assert h.attempts == 2
    assert h.metrics.validation_retries == 1


async def test_other_error_shares_single_retry_and_kind_other():
    # 검증도 가용성도 아닌 예외(예: 인증 오류)도 1회 예산, 최종 kind는 other
    h = Harness([RuntimeError("401")] * 2)
    with pytest.raises(PilotCallError) as ei:
        await h.run()
    assert ei.value.kind == "other"
    assert h.metrics.validation_retries == 1


async def test_availability_and_validation_budgets_are_independent():
    # 5xx 재시도 뒤에 절단이 나도 검증 1회는 별도로 보장
    h = Harness([FakeAvailabilityError("503"), FakeValidationError("truncated"), "ok"])
    assert await h.run() == "ok"
    assert h.metrics.availability_retries == 1
    assert h.metrics.validation_retries == 1
    assert h.sleeps == [2.0]


def test_run_pilot_failure_classification_uses_markers():
    # run_report 분류는 PilotCallError 접두 마커 기반(문자열 패턴 추측 아님)
    import run_pilot

    assert run_pilot._classify_failure("[availability] 503 UNAVAILABLE") == "availability"
    assert run_pilot._classify_failure("[validation] 1 validation error") == "validation"
    assert run_pilot._classify_failure("이미지 없음") == "other"
    assert run_pilot._classify_failure(None) == "other"
