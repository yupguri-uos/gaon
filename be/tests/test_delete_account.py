"""DELETE /auth/me 회원탈퇴(F-ON-4, QA A-4) 회귀 테스트.

- users 삭제 호출 + {ok: true} 응답.
- MinIO 이미지 정리는 best-effort — 스토리지 실패해도 계정 삭제는 200으로 진행.
실 DB·실 MinIO 없이 MagicMock으로 검증한다.
"""

from __future__ import annotations

import uuid
from types import SimpleNamespace
from unittest.mock import MagicMock

import pytest

from fastapi.testclient import TestClient

from app.db import get_db
from app.main import app
from app.security import get_current_user

USER_ID = uuid.uuid4()


@pytest.fixture()
def delete_client(monkeypatch):
    """이미지 2개를 가진 사용자의 탈퇴 요청 클라이언트. (client, db, deleted_keys) 반환."""
    user = SimpleNamespace(id=USER_ID, needs_onboarding=False)
    db = MagicMock()

    # 삭제 전 이미지 키 수집(SELECT image_ref) 응답
    result = MagicMock()
    result.scalars.return_value.all.return_value = ["u1/a.jpg", "u1/b.png", None]
    db.execute.return_value = result

    deleted_keys: list[str] = []

    def fake_delete_image(key: str) -> None:
        deleted_keys.append(key)

    monkeypatch.setattr("app.routers.auth.storage.delete_image", fake_delete_image)

    saved_overrides = app.dependency_overrides.copy()
    app.dependency_overrides[get_db] = lambda: db
    app.dependency_overrides[get_current_user] = lambda: user
    try:
        yield TestClient(app), db, deleted_keys
    finally:
        app.dependency_overrides = saved_overrides


def test_delete_account_removes_user_and_images(delete_client):
    """users 삭제 + 커밋 + 이미지 키 best-effort 정리(None 키는 건너뜀)."""
    client, db, deleted_keys = delete_client
    res = client.delete("/auth/me")
    assert res.status_code == 200
    assert res.json() == {"ok": True}
    db.delete.assert_called_once()
    db.commit.assert_called_once()
    assert deleted_keys == ["u1/a.jpg", "u1/b.png"]


def test_delete_account_survives_storage_failure(delete_client, monkeypatch):
    """MinIO 삭제가 실패해도 계정 삭제는 성공(200) — best-effort 계약."""
    client, db, _ = delete_client

    def boom(key: str) -> None:
        raise RuntimeError("minio down")

    monkeypatch.setattr("app.routers.auth.storage.delete_image", boom)
    res = client.delete("/auth/me")
    assert res.status_code == 200
    assert res.json() == {"ok": True}
    db.delete.assert_called_once()  # 계정 삭제는 그대로 수행됨
