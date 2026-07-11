"""
GeminiLLMClient — gaon_ai.llm.LLMClient Protocol의 Gemini(google-genai 신 SDK) 구현.

결정 #4(SSOT §6, 2026-07-09): 생성 LLM = 단일 Gemini. 파일럿 llm_sku 승자 클라이언트 승격본.
structured output은 SDK 공식 경로만 사용한다: response_schema에 Pydantic 모델을 직접
전달 + response_mime_type="application/json". 수제 "JSON으로 답해줘" 프롬프트 금지.

이미지 로더는 호출자가 주입한다(예: BE가 S3 로더 주입) — gaon_ai는 스토리지에 비관여.
기본 로더는 로컬 파일 경로 해석(개발·스모크용).
"""

from __future__ import annotations

import logging
import os
from pathlib import Path
from time import perf_counter
from typing import Callable, TypeVar

from google import genai
from google.genai import errors as genai_errors
from google.genai import types
from pydantic import BaseModel, ValidationError

from gaon_ai.llm import LLMMessage, ModelTier
from gaon_ai.llm_runtime import ClientMetrics, call_with_retries

logger = logging.getLogger(__name__)

M = TypeVar("M", bound=BaseModel)

# 결정 #4 확정 SKU — FAST=고빈도 추출/번역, QUALITY=경어체·문화 해설 등 품질 민감 단계
_DEFAULT_MODELS = {
    ModelTier.FAST: "gemini-3-flash-preview",
    ModelTier.QUALITY: "gemini-3.1-pro-preview",
}

_MIME_BY_EXT = {
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".png": "image/png",
    ".webp": "image/webp",
}


def mime_for_ext(suffix: str) -> str:
    """확장자 → mime. object_key()가 확장자를 보존하므로 버킷 키에도 그대로 쓸 수 있다."""
    mime = _MIME_BY_EXT.get(suffix.lower())
    if mime is None:
        raise ValueError(f"지원하지 않는 이미지 확장자: {suffix!r} (jpg/jpeg/png/webp만 지원)")
    return mime


def load_local_image(image_ref: str) -> tuple[bytes, str]:
    """기본 로더 — image_ref를 로컬 파일 경로로 해석한다(개발·스모크용)."""
    path = Path(image_ref)
    mime = mime_for_ext(path.suffix)  # 미지원 확장자는 파일을 읽기 전에 실패
    return path.read_bytes(), mime


def _is_availability_error(exc: Exception) -> bool:
    # (a) 5xx(UNAVAILABLE·overloaded 포함) — google-genai는 APIError.code에 HTTP 상태를 담는다
    return isinstance(exc, genai_errors.APIError) and (getattr(exc, "code", 0) or 0) >= 500


def _is_validation_error(exc: Exception) -> bool:
    # (b) 절단·스키마 불일치 — model_validate_json이 pydantic ValidationError로 드러낸다
    return isinstance(exc, ValidationError)


class GeminiLLMClient:
    """LLMClient 구현체. 이원화 재시도(가용성 3회 백오프/검증 1회), temperature=0, 누적 계측."""

    def __init__(
        self,
        api_key: str | None = None,
        image_loader: Callable[[str], tuple[bytes, str]] | None = None,
    ) -> None:
        key = api_key or os.environ.get("GOOGLE_API_KEY") or os.environ.get("GEMINI_API_KEY")
        if not key:
            raise RuntimeError("GOOGLE_API_KEY(또는 GEMINI_API_KEY)가 설정돼 있지 않습니다.")
        self._client = genai.Client(api_key=key)
        self._load_image = image_loader or load_local_image
        # env 오버라이드(GEMINI_MODEL_FAST/QUALITY) — 빈 값이면 결정 #4 기본 SKU
        self._models = {
            tier: os.environ.get(f"GEMINI_MODEL_{tier.name}") or default
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
        system_text, contents = self._convert(messages)
        # 이원화 재시도: 가용성=3회 백오프 / 검증 실패·기타=1회(gaon_ai/llm_runtime.py)
        return await call_with_retries(
            lambda: self._attempt(model_id, system_text, contents, output_model),
            is_availability=_is_availability_error,
            is_validation=_is_validation_error,
            metrics=self.metrics,
        )

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
                temperature=0.0,  # 재현성
                # Gemini 3는 내부 thinking 토큰이 이 한도를 함께 소모한다 — 8192로는
                # 긴 가정통신문에서 출력이 절단돼 JSON 검증에서 반복 실패(2026-07-11 보고).
                max_output_tokens=32768,
                response_mime_type="application/json",
                response_schema=output_model,  # Pydantic 모델 직접 전달(SDK 공식 경로)
            ),
        )
        latency_ms = int((perf_counter() - start) * 1000)
        usage = response.usage_metadata
        input_tokens = getattr(usage, "prompt_token_count", None)
        output_tokens = getattr(usage, "candidates_token_count", None)
        self.metrics.record_call(
            latency_ms=latency_ms, input_tokens=input_tokens, output_tokens=output_tokens
        )
        logger.debug(
            "gemini 호출: model=%s latency_ms=%d input_tokens=%s output_tokens=%s",
            model_id,
            latency_ms,
            input_tokens,
            output_tokens,
        )
        parsed = response.parsed
        if isinstance(parsed, output_model):
            return parsed
        # SDK가 parsed를 채우지 못한 경우 원문 JSON을 직접 검증(실패 시 예외 → 재시도 경로)
        return output_model.model_validate_json(response.text or "")

    def _convert(self, messages: list[LLMMessage]) -> tuple[str, list[types.Part]]:
        """LLMMessage → (system_instruction 텍스트, user 파트 목록). 이미지는 주입된 로더로."""
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
                    data, mime = self._load_image(part.image_ref)
                    contents.append(types.Part.from_bytes(data=data, mime_type=mime))
        return "\n\n".join(system_parts), contents
