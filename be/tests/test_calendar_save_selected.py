"""POST /calendar/events 선택 저장(F-DOC-7, QA D-3) 회귀 테스트.

- selected 미전달 = 기존 계약(전체 저장, 문서 단위 delete 후 재삽입) 유지.
- selected 전달 = 해당 (title, date)만 저장. 일치하는 기존 행만 지워
  이전에 저장한 다른 일정은 유지된다(합집합 + 멱등).
실 DB 없이 MagicMock 세션으로 add/execute 호출을 관찰한다.
"""

from __future__ import annotations

import uuid
from types import SimpleNamespace
from unittest.mock import MagicMock

import pytest
from fastapi.testclient import TestClient

from app.db import get_db
from app.main import app
from app.models import CalendarEventRow, Document, DocumentResultRow
from app.security import get_current_user

USER_ID = uuid.uuid4()
DOC_ID = uuid.uuid4()

RESULT_EVENTS = [
    {"title": "현장체험학습", "date": "2026-06-16", "type": "event", "child_id": None},
    {"title": "회신 마감", "date": "2026-06-12", "type": "deadline", "child_id": None},
]


@pytest.fixture()
def save_client():
    """document/result_row가 존재하는 상태의 TestClient. (client, db) 반환."""
    user = SimpleNamespace(id=USER_ID, needs_onboarding=False)
    document = SimpleNamespace(id=DOC_ID, user_id=USER_ID, child_id=None)
    result_row = SimpleNamespace(calendar_events=RESULT_EVENTS)

    db = MagicMock()

    def fake_get(model, pk):
        if model is Document:
            return document
        if model is DocumentResultRow:
            return result_row
        return None

    db.get.side_effect = fake_get

    saved_overrides = app.dependency_overrides.copy()
    app.dependency_overrides[get_db] = lambda: db
    app.dependency_overrides[get_current_user] = lambda: user
    try:
        yield TestClient(app), db
    finally:
        app.dependency_overrides = saved_overrides


def _added_rows(db: MagicMock) -> list[CalendarEventRow]:
    return [call.args[0] for call in db.add.call_args_list]


def test_full_save_without_selected_keeps_legacy_contract(save_client):
    """selected 미전달 → 문서 전체 일정 저장 + 문서 단위 delete(멱등 전체 동기화)."""
    client, db = save_client
    res = client.post("/calendar/events", json={"document_id": str(DOC_ID)})
    assert res.status_code == 200
    created = res.json()["created"]
    assert [c["title"] for c in created] == ["현장체험학습", "회신 마감"]
    assert len(_added_rows(db)) == 2
    # 문서 단위 전체 삭제(재삽입 전) — title/date 조건 없는 delete
    delete_sql = str(db.execute.call_args_list[0].args[0])
    assert "DELETE" in delete_sql and "title" not in delete_sql


def test_selected_saves_only_matching_events(save_client):
    """selected 전달 → 일치 (title, date)만 저장, created도 그 항목만 반환."""
    client, db = save_client
    res = client.post(
        "/calendar/events",
        json={
            "document_id": str(DOC_ID),
            "selected": [{"title": "현장체험학습", "date": "2026-06-16"}],
        },
    )
    assert res.status_code == 200
    created = res.json()["created"]
    assert [c["title"] for c in created] == ["현장체험학습"]
    rows = _added_rows(db)
    assert len(rows) == 1 and rows[0].title == "현장체험학습"
    # 선택 키와 일치하는 행만 지운다 — 이전 저장분(다른 키)은 유지
    delete_sql = str(db.execute.call_args_list[0].args[0])
    assert "DELETE" in delete_sql and ("title" in delete_sql or "IN" in delete_sql)


def test_selected_empty_list_saves_nothing(save_client):
    """selected=[] → 아무것도 저장·삭제하지 않는다(created=[])."""
    client, db = save_client
    res = client.post("/calendar/events", json={"document_id": str(DOC_ID), "selected": []})
    assert res.status_code == 200
    assert res.json()["created"] == []
    assert db.add.call_count == 0
    assert db.execute.call_count == 0  # delete도 없음


def test_selected_unknown_key_is_ignored(save_client):
    """결과에 없는 (title, date) 키는 무시된다 — 존재 항목만 저장."""
    client, db = save_client
    res = client.post(
        "/calendar/events",
        json={
            "document_id": str(DOC_ID),
            "selected": [
                {"title": "없는 일정", "date": "2026-06-01"},
                {"title": "회신 마감", "date": "2026-06-12"},
            ],
        },
    )
    assert res.status_code == 200
    assert [c["title"] for c in res.json()["created"]] == ["회신 마감"]
    assert len(_added_rows(db)) == 1
