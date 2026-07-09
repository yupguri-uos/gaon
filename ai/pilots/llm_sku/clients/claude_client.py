"""
AnthropicLLMClient — gaon_ai.llm.LLMClient Protocol의 Claude(anthropic SDK) 구현 (§4.2).

structured output은 SDK 공식 경로만 사용한다: client.messages.parse(output_format=Pydantic 모델)
— 응답을 스키마로 강제하고 SDK가 검증까지 수행한다(anthropic>=0.116에서 확인).
수제 "JSON으로 답해줘" 프롬프트 금지. 이미지는 base64 블록으로 전달.
"""

from __future__ import annotations

import base64
import os
from time import perf_counter
from typing import Any, TypeVar

import anthropic
from anthropic import NOT_GIVEN, AsyncAnthropic
from pydantic import BaseModel, ValidationError

from common.image_loader import load_image
from common.metrics import CallRecord, ClientMetrics
from common.retry import StructuredOutputParseError, call_with_retries
from gaon_ai.llm import LLMMessage, ModelTier

M = TypeVar("M", bound=BaseModel)


def _is_availability_error(exc: Exception) -> bool:
    # (a) 5xx·529(overloaded) — anthropic은 APIStatusError.status_code에 HTTP 상태를 담는다
    return isinstance(exc, anthropic.APIStatusError) and getattr(exc, "status_code", 0) >= 500


def _is_validation_error(exc: Exception) -> bool:
    # (b) 절단·스키마 불일치 — SDK parse의 pydantic 검증 실패 또는 파일럿의 파싱 실패 예외
    return isinstance(exc, (ValidationError, StructuredOutputParseError))


_DEFAULT_MODELS = {
    ModelTier.FAST: "claude-haiku-4-5",
    ModelTier.QUALITY: "claude-sonnet-4-6",
}


class AnthropicLLMClient:
    """LLMClient 구현체. 이원화 재시도(가용성 3회 백오프/검증 1회), temperature=0, 호출별 계측."""

    def __init__(self, api_key: str | None = None) -> None:
        key = api_key or os.environ.get("ANTHROPIC_API_KEY")
        if not key:
            raise RuntimeError("ANTHROPIC_API_KEY가 설정돼 있지 않습니다.")
        # SDK 자체 재시도와 파일럿의 계열별 재시도 카운트가 섞이지 않게 SDK 재시도는 끈다.
        self._client = AsyncAnthropic(api_key=key, max_retries=0)
        if not hasattr(self._client.messages, "parse"):
            raise RuntimeError(
                "anthropic SDK가 structured output(messages.parse)을 지원하지 않습니다 — "
                "pip install -U anthropic 후 다시 실행하세요."
            )
        self._models = {
            tier: os.environ.get(f"ANTHROPIC_MODEL_{tier.name}", default)
            for tier, default in _DEFAULT_MODELS.items()
        }
        self.metrics = ClientMetrics()

    async def generate_structured(
        self,
        *,
        messages: list[LLMMessage],
        output_model: type[M],
        tier: ModelTier = ModelTier.FAST,
    ) -> M:
        model_id = self._models[tier]
        system_text, api_messages = _convert(messages)
        # 이원화 재시도(계측 결함 패치): 가용성=3회 백오프 / 검증 실패·기타=1회(common/retry.py)
        return await call_with_retries(
            lambda: self._attempt(model_id, system_text, api_messages, output_model),
            is_availability=_is_availability_error,
            is_validation=_is_validation_error,
            metrics=self.metrics,
        )

    async def _attempt(
        self,
        model_id: str,
        system_text: str,
        api_messages: list[dict[str, Any]],
        output_model: type[M],
    ) -> M:
        start = perf_counter()
        response = await self._client.messages.parse(
            model=model_id,
            max_tokens=8192,  # 계측 결함 패치: 절단 방지 상향(양 벤더 동일 — 공정성)
            temperature=0.0,  # 재현성(§4.2)
            system=system_text or NOT_GIVEN,  # system은 SDK의 system 파라미터로
            messages=api_messages,
            output_format=output_model,  # 구조화 출력 공식 경로(스키마 강제 + 자동 검증)
        )
        latency_ms = int((perf_counter() - start) * 1000)
        self.metrics.calls.append(
            CallRecord(
                model=model_id,
                latency_ms=latency_ms,
                input_tokens=response.usage.input_tokens,
                output_tokens=response.usage.output_tokens,
            )
        )
        parsed = response.parsed_output
        if not isinstance(parsed, output_model):
            # 절단(stop_reason=max_tokens)·안전 거부 등으로 파싱이 비면 검증 실패 계열로 예외
            raise StructuredOutputParseError(
                f"구조화 출력 파싱 실패(stop_reason={response.stop_reason})"
            )
        return parsed


def _convert(messages: list[LLMMessage]) -> tuple[str, list[dict[str, Any]]]:
    """LLMMessage → (system 텍스트, Anthropic messages). 이미지는 §4.1 공용 로더로 base64 인코딩."""
    system_parts: list[str] = []
    api_messages: list[dict[str, Any]] = []
    for msg in messages:
        if msg.role == "system":
            for part in msg.content:
                if part.type != "text":
                    raise ValueError("system 메시지에는 텍스트만 허용됩니다.")
                system_parts.append(part.text)
            continue
        blocks: list[dict[str, Any]] = []
        for part in msg.content:
            if part.type == "text":
                blocks.append({"type": "text", "text": part.text})
            else:
                data, mime = load_image(part.image_ref)
                blocks.append(
                    {
                        "type": "image",
                        "source": {
                            "type": "base64",
                            "media_type": mime,
                            "data": base64.standard_b64encode(data).decode("ascii"),
                        },
                    }
                )
        api_messages.append({"role": "user", "content": blocks})
    return "\n\n".join(system_parts), api_messages
