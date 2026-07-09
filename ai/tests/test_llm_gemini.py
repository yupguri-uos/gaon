"""GeminiLLMClient 단위 테스트 — genai SDK 전면 모킹, 네트워크 호출 없음.

커버: 결정 #4 기본 SKU 회귀 가드 · env 오버라이드 · _convert 변환 규칙 ·
이원화 재시도 분류(가용성/검증) · 주입 이미지 로더 경로.
"""

from __future__ import annotations

from types import SimpleNamespace

import pytest
from google.genai import errors as genai_errors
from pydantic import BaseModel

from gaon_ai.llm import ModelTier, system, user_image_and_text, user_text
from gaon_ai.llm_gemini import GeminiLLMClient
from gaon_ai.llm_runtime import LLMCallError


class Answer(BaseModel):
    value: str


@pytest.fixture(autouse=True)
def clean_env(monkeypatch):
    # 개발자 셸의 실제 env가 테스트에 새어들지 않게 고정
    for name in ("GEMINI_MODEL_FAST", "GEMINI_MODEL_QUALITY", "GOOGLE_API_KEY", "GEMINI_API_KEY"):
        monkeypatch.delenv(name, raising=False)


@pytest.fixture
def zero_backoff(monkeypatch):
    # 가용성 백오프(2/8/30s)를 0으로 — 정책(횟수)은 그대로 검증하되 테스트는 즉시 진행
    monkeypatch.setattr("gaon_ai.llm_runtime.BACKOFF_SECONDS", (0.0, 0.0, 0.0))


def make_response(parsed=None, text=None):
    return SimpleNamespace(
        parsed=parsed,
        text=text,
        usage_metadata=SimpleNamespace(prompt_token_count=10, candidates_token_count=5),
    )


def wire_fake_generate(client: GeminiLLMClient, generate) -> None:
    """실 genai.Client 대신 generate_content만 흉내내는 더미로 교체."""
    client._client = SimpleNamespace(
        aio=SimpleNamespace(models=SimpleNamespace(generate_content=generate))
    )


def make_availability_error(code: int = 503) -> genai_errors.APIError:
    return genai_errors.APIError(
        code, {"error": {"message": "unavailable", "status": "UNAVAILABLE"}}
    )


# ── 생성자·SKU ──────────────────────────────────────────────────────────────


def test_missing_api_key_raises():
    with pytest.raises(RuntimeError):
        GeminiLLMClient()


async def test_default_skus_are_decision_4_values():
    # 결정 #4 확정 SKU — 파일럿 stale 값(gemini-2.5-flash/gemini-3-pro) 회귀 가드
    client = GeminiLLMClient(api_key="test-key")
    seen: list[str] = []

    async def generate(**kwargs):
        seen.append(kwargs["model"])
        return make_response(parsed=Answer(value="ok"))

    wire_fake_generate(client, generate)
    await client.generate_structured(
        messages=[user_text("hi")], output_model=Answer, tier=ModelTier.FAST
    )
    await client.generate_structured(
        messages=[user_text("hi")], output_model=Answer, tier=ModelTier.QUALITY
    )
    assert seen == ["gemini-3-flash-preview", "gemini-3.1-pro-preview"]


async def test_env_override_models(monkeypatch):
    monkeypatch.setenv("GEMINI_MODEL_FAST", "custom-fast")
    monkeypatch.setenv("GEMINI_MODEL_QUALITY", "custom-quality")
    client = GeminiLLMClient(api_key="test-key")
    seen: list[str] = []

    async def generate(**kwargs):
        seen.append(kwargs["model"])
        return make_response(parsed=Answer(value="ok"))

    wire_fake_generate(client, generate)
    await client.generate_structured(
        messages=[user_text("hi")], output_model=Answer, tier=ModelTier.FAST
    )
    await client.generate_structured(
        messages=[user_text("hi")], output_model=Answer, tier=ModelTier.QUALITY
    )
    assert seen == ["custom-fast", "custom-quality"]


# ── _convert ────────────────────────────────────────────────────────────────


def test_convert_separates_system_text():
    client = GeminiLLMClient(api_key="test-key")
    system_text, contents = client._convert([system("지시 1"), system("지시 2"), user_text("본문")])
    assert system_text == "지시 1\n\n지시 2"
    assert len(contents) == 1
    assert contents[0].text == "본문"


def test_convert_builds_text_and_image_parts():
    loaded: list[str] = []

    def loader(image_ref: str) -> tuple[bytes, str]:
        loaded.append(image_ref)
        return b"img-bytes", "image/jpeg"

    client = GeminiLLMClient(api_key="test-key", image_loader=loader)
    _, contents = client._convert([user_image_and_text("u1/doc.jpg", "이 문서를 분석해줘")])
    assert loaded == ["u1/doc.jpg"]  # 주입 로더가 image_ref 그대로 호출됨
    assert len(contents) == 2
    assert contents[0].inline_data.data == b"img-bytes"
    assert contents[0].inline_data.mime_type == "image/jpeg"
    assert contents[1].text == "이 문서를 분석해줘"


def test_convert_rejects_image_in_system():
    from gaon_ai.llm import ImagePart, LLMMessage

    client = GeminiLLMClient(api_key="test-key")
    bad = LLMMessage(role="system", content=[ImagePart(image_ref="x.jpg")])
    with pytest.raises(ValueError):
        client._convert([bad])


# ── 재시도 분류 ─────────────────────────────────────────────────────────────


async def test_availability_error_backs_off_then_succeeds(zero_backoff):
    client = GeminiLLMClient(api_key="test-key")
    attempts = 0

    async def generate(**kwargs):
        nonlocal attempts
        attempts += 1
        if attempts <= 2:
            raise make_availability_error()
        return make_response(parsed=Answer(value="ok"))

    wire_fake_generate(client, generate)
    result = await client.generate_structured(messages=[user_text("hi")], output_model=Answer)
    assert result.value == "ok"
    assert attempts == 3
    assert client.metrics.availability_retries == 2
    assert client.metrics.validation_retries == 0


async def test_availability_exhaustion_raises_llm_call_error(zero_backoff):
    client = GeminiLLMClient(api_key="test-key")
    attempts = 0

    async def generate(**kwargs):
        nonlocal attempts
        attempts += 1
        raise make_availability_error()

    wire_fake_generate(client, generate)
    with pytest.raises(LLMCallError) as excinfo:
        await client.generate_structured(messages=[user_text("hi")], output_model=Answer)
    assert excinfo.value.kind == "availability"
    assert attempts == 4  # 최초 1회 + 백오프 재시도 3회
    assert client.metrics.availability_retries == 3


async def test_validation_error_retries_once_then_fails():
    client = GeminiLLMClient(api_key="test-key")
    attempts = 0

    async def generate(**kwargs):
        nonlocal attempts
        attempts += 1
        # parsed 미채움 + 깨진 JSON → model_validate_json이 ValidationError를 던진다
        return make_response(parsed=None, text='{"wrong_field": true')

    wire_fake_generate(client, generate)
    with pytest.raises(LLMCallError) as excinfo:
        await client.generate_structured(messages=[user_text("hi")], output_model=Answer)
    assert excinfo.value.kind == "validation"
    assert attempts == 2  # 검증 실패는 1회만 재시도(관대화 금지)
    assert client.metrics.validation_retries == 1
    assert client.metrics.availability_retries == 0
