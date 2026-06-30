"""
GAON AI — LLM 클라이언트 추상화 (model-agnostic)

결정 #4(SSOT §6): 멀티모달 LLM '한 패밀리'로 통일하되 단계별 티어를 둔다.
  - FAST    : 저비용 멀티모달 — 추출/번역 등 고빈도 단계
  - QUALITY : 상위 모델 — 경어체·문화 해설 등 품질 민감 단계
구체 SKU는 API 셋업 직전 확정(결정 #4). 에이전트는 이 추상화에만 의존하므로
SKU/벤더가 바뀌어도 에이전트 코드는 불변. 실제 구현체는 SKU 확정 후 이 Protocol을 구현해 주입한다.
"""

from __future__ import annotations

from enum import Enum
from typing import Literal, Protocol, TypeVar, runtime_checkable

from pydantic import BaseModel


class ModelTier(str, Enum):
    FAST = "fast"  # 추출/번역 등 고빈도 → 저비용
    QUALITY = "quality"  # 경어체·문화 해설 등 품질 민감 → 상위 모델


class TextPart(BaseModel):
    type: Literal["text"] = "text"
    text: str


class ImagePart(BaseModel):
    # image_ref = 객체스토리지 키/URL(예: MinIO). 구체 LLMClient 구현이 바이트를 로드·인코딩한다.
    type: Literal["image"] = "image"
    image_ref: str


LLMContentPart = TextPart | ImagePart


class LLMMessage(BaseModel):
    role: Literal["system", "user"]
    content: list[LLMContentPart]


M = TypeVar("M", bound=BaseModel)


@runtime_checkable
class LLMClient(Protocol):
    """구조화 출력 단일 진입점.

    구현체는 messages(+이미지)를 받아 output_model 스키마에 맞는 JSON을 생성하고
    검증된 인스턴스를 반환한다(메커니즘=tool-use/json_mode 등은 구현 내부에 숨김).
    실패 시 예외를 던지며, Agent.run()이 AgentResponse(error)로 감싼다.
    """

    async def generate_structured(
        self,
        *,
        messages: list[LLMMessage],
        output_model: type[M],
        tier: ModelTier = ModelTier.FAST,
    ) -> M: ...


# ── 메시지 빌더 헬퍼 ────────────────────────────────────────────────────────
def system(text: str) -> LLMMessage:
    return LLMMessage(role="system", content=[TextPart(text=text)])


def user_text(text: str) -> LLMMessage:
    return LLMMessage(role="user", content=[TextPart(text=text)])


def user_image_and_text(image_ref: str, text: str) -> LLMMessage:
    return LLMMessage(role="user", content=[ImagePart(image_ref=image_ref), TextPart(text=text)])
