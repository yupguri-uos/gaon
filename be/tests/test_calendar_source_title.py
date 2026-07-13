"""GET /calendar/events 출처 문서 제목(source_title, QA D-5) 회귀 테스트.

엔드포인트 로컬 필드 — shared-schema 무변경. 서로 다른 두 문서의 일정이
각자의 Document.title을 source_title로 달고 반환되는지,
document_id 없음/제목 빈 값이면 null인지 검증한다(실 DB 불필요).
"""

from __future__ import annotations

import uuid
from datetime import date
from types import SimpleNamespace
from unittest.mock import MagicMock

import pytest
from fastapi.testclient import TestClient

from app.db import get_db
from app.main import app
from app.security import get_current_user

USER_ID = uuid.uuid4()
DOC_A = uuid.uuid4()  # 제목 있는 문서
DOC_B = uuid.uuid4()  # 제목 있는 문서 2
DOC_C = uuid.uuid4()  # 제목이 빈 문자열인 문서


def _event_row(doc_id, title, d):
    return SimpleNamespace(
        id=uuid.uuid4(),
        document_id=doc_id,
        child_id=None,
        title=title,
        event_date=d,
        type="event",
    )


EVENT_ROWS = [
    _event_row(DOC_A, "현장체험학습", date(2026, 6, 16)),
    _event_row(DOC_B, "운동회", date(2026, 6, 20)),
    _event_row(DOC_C, "준비물 마감", date(2026, 6, 22)),
    _event_row(None, "수동 일정", date(2026, 6, 25)),  # 출처 문서 없음
]

DOCUMENTS = [
    SimpleNamespace(id=DOC_A, title="3월 6일 알림장"),
    SimpleNamespace(id=DOC_B, title="운동회 안내문"),
    SimpleNamespace(id=DOC_C, title=""),  # 제목 미상 → null 취급
]


@pytest.fixture()
def list_client():
    user = SimpleNamespace(id=USER_ID, needs_onboarding=False)
    db = MagicMock()

    # 1번째 execute = 이벤트 목록, 2번째 execute = 출처 문서 배치 조회
    results = iter([EVENT_ROWS, DOCUMENTS])

    def fake_execute(stmt):
        result = MagicMock()
        result.scalars.return_value.all.return_value = next(results)
        return result

    db.execute.side_effect = fake_execute

    saved_overrides = app.dependency_overrides.copy()
    app.dependency_overrides[get_db] = lambda: db
    app.dependency_overrides[get_current_user] = lambda: user
    try:
        yield TestClient(app), db
    finally:
        app.dependency_overrides = saved_overrides


def test_each_event_carries_its_own_source_title(list_client):
    """서로 다른 문서의 일정이 각자 올바른 source_title을 단다."""
    client, db = list_client
    res = client.get("/calendar/events")
    assert res.status_code == 200
    events = res.json()["events"]
    by_title = {e["title"]: e["source_title"] for e in events}
    assert by_title["현장체험학습"] == "3월 6일 알림장"
    assert by_title["운동회"] == "운동회 안내문"
    # 제목이 빈 문자열인 문서·출처 문서 없는 일정은 null
    assert by_title["준비물 마감"] is None
    assert by_title["수동 일정"] is None
    # N+1 없이 이벤트 1회 + 문서 배치 1회 조회
    assert db.execute.call_count == 2
