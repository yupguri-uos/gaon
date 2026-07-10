"""GET /calendar/events 필터 정책 회귀 테스트(F-CAL-1) — 2026-07-11 결정.

알림장 일정은 지난 행사 등 과거 날짜가 많아 '오늘 이후' 디폴트면 저장 직후에도
캘린더 탭에 안 보였다 — month 생략 시 과거 포함 전체를 반환해야 한다.
쿼리 조건은 db.execute에 전달된 SELECT 문을 문자열로 검사한다(실 DB 불필요).
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


@pytest.fixture()
def calendar_client():
    """db.execute에 잡힌 SELECT 문을 관찰할 수 있는 TestClient. (client, captured) 반환."""
    user = SimpleNamespace(id=uuid.uuid4(), needs_onboarding=False)
    captured: dict = {}
    db = MagicMock()

    def capture_execute(stmt):
        captured["stmt"] = stmt
        result = MagicMock()
        result.scalars.return_value.all.return_value = []
        return result

    db.execute.side_effect = capture_execute

    saved_overrides = app.dependency_overrides.copy()
    app.dependency_overrides[get_db] = lambda: db
    app.dependency_overrides[get_current_user] = lambda: user
    try:
        yield TestClient(app), captured
    finally:
        app.dependency_overrides = saved_overrides


def test_default_returns_all_events_without_date_filter(calendar_client):
    """month 생략 = 과거 포함 전체 — '오늘 이후(event_date >=)' 디폴트 회귀 가드."""
    client, captured = calendar_client
    res = client.get("/calendar/events")
    assert res.status_code == 200
    where = str(captured["stmt"])
    assert "event_date >=" not in where
    assert "BETWEEN" not in where


def test_month_param_filters_to_that_month(calendar_client):
    client, captured = calendar_client
    res = client.get("/calendar/events", params={"month": "2026-07"})
    assert res.status_code == 200
    assert "BETWEEN" in str(captured["stmt"])


def test_invalid_month_is_400(calendar_client):
    client, _ = calendar_client
    res = client.get("/calendar/events", params={"month": "not-a-month"})
    assert res.status_code == 400
