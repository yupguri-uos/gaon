"""
GeminiLLMClient — gaon_ai.llm.LLMClient Protocol의 Gemini(google-genai 신 SDK) 구현 (§4.2).

structured output은 SDK 공식 경로만 사용한다: response_schema에 Pydantic 모델을 직접
전달 + response_mime_type="application/json". 수제 "JSON으로 답해줘" 프롬프트 금지 —
아니면 모델이 아니라 통합 품질을 측정하게 된다.
"""

from __future__ import annotations

import os
from time import perf_counter
from typing import TypeVar

from google import genai
from google.genai import types
from pydantic import BaseModel

from common.image_loader import load_image
from common.metrics import CallRecord, ClientMetrics
from gaon_ai.llm import LLMMessage, ModelTier

M = TypeVar("M", bound=BaseModel)

_DEFAULT_MODELS = {
    ModelTier.FAST: "gemini-2.5-flash",
    # 정확한 공개 모델 문자열은 실행 전 models.list로 확인, 다르면 env로 교정(README 참조)
    ModelTier.QUALITY: "gemini-3-pro",
}


class GeminiLLMClient:
    """LLMClient 구현체. 재시도 1회, temperature=0, 호출별 토큰·지연시간 기록."""

    def __init__(self, api_key: str | None = None) -> None:
        key = api_key or os.environ.get("GOOGLE_API_KEY") or os.environ.get("GEMINI_API_KEY")
        if not key:
            raise RuntimeError("GOOGLE_API_KEY(또는 GEMINI_API_KEY)가 설정돼 있지 않습니다.")
        self._client = genai.Client(api_key=key)
        self._models = {
            tier: os.environ.get(f"GEMINI_MODEL_{tier.name}", default)
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
        system_text, contents = _convert(messages)
        try:
            return await self._attempt(model_id, system_text, contents, output_model)
        except Exception:
            # Pydantic 검증 실패·API 오류 시 1회 재시도 후 예외(§4.2). 횟수는 신뢰성 축으로 기록.
            self.metrics.retry_count += 1
            return await self._attempt(model_id, system_text, contents, output_model)

    async def _attempt(
        self,
        model_id: str,
        system_text: str,
        contents: list[types.Part],
        output_model: type[M],
    ) -> M:
        start = perf_counter()
        response = await self._client.aio.models.generate_content(
            model=model_id,
            contents=contents,
            config=types.GenerateContentConfig(
                system_instruction=system_text or None,  # system은 SDK의 시스템 프롬프트 자리로
                temperature=0.0,  # 재현성(§4.2)
                max_output_tokens=4096,
                response_mime_type="application/json",
                response_schema=output_model,  # Pydantic 모델 직접 전달(SDK 공식 경로)
            ),
        )
        latency_ms = int((perf_counter() - start) * 1000)
        usage = response.usage_metadata
        self.metrics.calls.append(
            CallRecord(
                model=model_id,
                latency_ms=latency_ms,
                input_tokens=getattr(usage, "prompt_token_count", None),
                output_tokens=getattr(usage, "candidates_token_count", None),
            )
        )
        parsed = response.parsed
        if isinstance(parsed, output_model):
            return parsed
        # SDK가 parsed를 채우지 못한 경우 원문 JSON을 직접 검증(실패 시 예외 → 재시도 경로)
        return output_model.model_validate_json(response.text or "")


def _convert(messages: list[LLMMessage]) -> tuple[str, list[types.Part]]:
    """LLMMessage → (system_instruction 텍스트, user 파트 목록). 이미지는 §4.1 공용 로더로."""
    system_parts: list[str] = []
    contents: list[types.Part] = []
    for msg in messages:
        for part in msg.content:
            if msg.role == "system":
                if part.type != "text":
                    raise ValueError("system 메시지에는 텍스트만 허용됩니다.")
                system_parts.append(part.text)
            elif part.type == "text":
                contents.append(types.Part.from_text(text=part.text))
            else:
                data, mime = load_image(part.image_ref)
                contents.append(types.Part.from_bytes(data=data, mime_type=mime))
    return "\n\n".join(system_parts), contents
