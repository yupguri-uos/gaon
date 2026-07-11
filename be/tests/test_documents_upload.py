"""문서 업로드(F-DOC-1)·상태 폴링(F-DOC-4) 회귀 테스트 — 2026-07-11 시연 안정화분.

- MIME은 선언 헤더가 아니라 매직 바이트로 판별한다(갤러리 스크린샷 PNG가
  image/jpeg로 고정 신고되던 문제). 객체 키 확장자가 곧 Chain A 로더의 mime이므로
  키가 실제 포맷을 따라가는지까지 본다.
- 폴링 응답은 실패 원인(error)을 실어 FE가 콘솔 트래킹할 수 있어야 한다.
스토리지·체인·DB는 실호출 없이 대체한다(test_auth_deeplink.py와 동일한 접근).
"""

from __future__ import annotations

import uuid
from types import SimpleNamespace
from unittest.mock import MagicMock

import pytest
from fastapi.testclient import TestClient

from app.db import get_db
from app.main import app
from app.routers import documents as documents_router
from app.routers.documents import _sniff_image
from app.security import get_current_user

PNG_BYTES = b"\x89PNG\r\n\x1a\n" + b"\x00" * 32
JPEG_BYTES = b"\xff\xd8\xff\xe0" + b"\x00" * 32
WEBP_BYTES = b"RIFF\x24\x00\x00\x00WEBPVP8 " + b"\x00" * 32


def test_sniff_image_formats():
    assert _sniff_image(JPEG_BYTES) == ("image/jpeg", "jpg")
    assert _sniff_image(PNG_BYTES) == ("image/png", "png")
    assert _sniff_image(WEBP_BYTES) == ("image/webp", "webp")
    assert _sniff_image(b"GIF89a" + b"\x00" * 16) is None  # 미지원 포맷
    assert _sniff_image(b"") is None


@pytest.fixture()
def upload_client(monkeypatch):
    """스토리지·체인 실행을 가로챈 업로드용 TestClient. (client, 업로드 기록) 반환."""
    user = SimpleNamespace(id=uuid.uuid4(), needs_onboarding=False)

    db = MagicMock()
    db.refresh.side_effect = lambda obj: setattr(obj, "id", uuid.uuid4())  # DB PK 부여 흉내

    uploads: list[tuple[str, str | None]] = []

    def fake_upload(key: str, data: bytes, content_type: str | None) -> None:
        uploads.append((key, content_type))

    async def fake_chain(document_id: uuid.UUID) -> None:
        return None  # BackgroundTasks가 TestClient 응답 직후 실행하므로 반드시 무력화

    monkeypatch.setattr(documents_router, "upload_image", fake_upload)
    monkeypatch.setattr(documents_router, "_run_chain_a_and_persist", fake_chain)

    saved_overrides = app.dependency_overrides.copy()
    app.dependency_overrides[get_db] = lambda: db
    app.dependency_overrides[get_current_user] = lambda: user
    try:
        yield TestClient(app), uploads
    finally:
        app.dependency_overrides = saved_overrides


def test_upload_detects_png_despite_jpeg_header(upload_client):
    """갤러리 스크린샷 시나리오: PNG 바이트 + image/jpeg 선언 → 매직 바이트가 이긴다."""
    client, uploads = upload_client
    res = client.post("/documents", files={"image": ("screenshot.jpg", PNG_BYTES, "image/jpeg")})
    assert res.status_code == 200
    assert res.json()["status"] == "uploaded"
    key, content_type = uploads[0]
    assert key.endswith(".png")  # Chain A 로더가 이 확장자로 mime을 정한다
    assert content_type == "image/png"


def test_upload_rejects_unsupported_bytes(upload_client):
    client, uploads = upload_client
    res = client.post("/documents", files={"image": ("note.txt", b"hello world", "image/jpeg")})
    assert res.status_code == 400
    assert uploads == []  # 스토리지에 닿기 전에 거부


@pytest.mark.parametrize(
    ("status_value", "error_value"),
    [("failed", "Gemini 응답 절단"), ("parsing", None)],
)
def test_status_polling_exposes_error(status_value, error_value):
    """실패 원인(documents.error)을 폴링 응답에 노출 — FE 콘솔 트래킹용. 평시엔 null."""
    user = SimpleNamespace(id=uuid.uuid4(), needs_onboarding=False)
    doc_id = uuid.uuid4()
    document = SimpleNamespace(id=doc_id, user_id=user.id, status=status_value, error=error_value)
    db = MagicMock()
    db.get.return_value = document

    saved_overrides = app.dependency_overrides.copy()
    app.dependency_overrides[get_db] = lambda: db
    app.dependency_overrides[get_current_user] = lambda: user
    try:
        client = TestClient(app)
        res = client.get(f"/documents/{doc_id}/status")
    finally:
        app.dependency_overrides = saved_overrides

    assert res.status_code == 200
    assert res.json() == {"status": status_value, "step": status_value, "error": error_value}
