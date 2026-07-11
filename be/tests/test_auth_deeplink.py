"""Kakao 콜백의 앱 딥링크 분기(F-ON-3) 검증.

/auth/kakao/login?client=app → callback이 gaon://auth/callback 딥링크로 302 리다이렉트해
Flutter 앱(fe/lib/main.dart)에 토큰을 넘기는지, web(기본)은 기존 JSON 응답을 유지하는지 확인한다.
카카오 API·DB는 실호출 없이 대체한다(test_activity_service.py와 동일한 접근).
"""

from __future__ import annotations

import uuid
from types import SimpleNamespace
from unittest.mock import MagicMock
from urllib.parse import parse_qs, urlsplit

import pytest
from fastapi.testclient import TestClient

from app.db import get_db
from app.main import app
from app.routers import auth as auth_router


@pytest.fixture()
def client_with_fakes(monkeypatch):
    """카카오 API 2종을 대체하고 DB 의존성을 오버라이드한 TestClient."""

    async def fake_exchange(code: str) -> str:
        return "kakao-access-token"

    async def fake_fetch(token: str):
        return SimpleNamespace(kakao_id="kakao-e2e-1", nickname="탕지수")

    monkeypatch.setattr(auth_router, "exchange_code_for_access_token", fake_exchange)
    monkeypatch.setattr(auth_router, "fetch_kakao_user", fake_fetch)

    # 기존 유저(온보딩 완료) 반환 — needs_onboarding=False 경로
    fake_user = SimpleNamespace(id=uuid.uuid4(), display_name="탕지수", needs_onboarding=False)
    db = MagicMock()
    db.execute.return_value.scalar_one_or_none.return_value = fake_user

    saved_overrides = app.dependency_overrides.copy()
    app.dependency_overrides[get_db] = lambda: db
    try:
        yield TestClient(app), fake_user
    finally:
        app.dependency_overrides = saved_overrides


def test_login_app_client_sets_deeplink_cookie():
    client = TestClient(app)
    res = client.get("/auth/kakao/login", params={"client": "app"}, follow_redirects=False)
    assert res.status_code == 302
    assert "kauth.kakao.com" in res.headers["location"]
    cookies = ",".join(res.headers.get_list("set-cookie"))
    assert "kakao_oauth_state=" in cookies
    assert "kakao_oauth_client=app" in cookies


def test_login_web_client_has_no_deeplink_cookie():
    client = TestClient(app)
    res = client.get("/auth/kakao/login", follow_redirects=False)
    assert res.status_code == 302
    # 웹 로그인은 딥링크 분기 쿠키를 심지 않는다 — 있어도 stale 정리용 삭제(Max-Age=0)뿐
    client_cookies = [
        h for h in res.headers.get_list("set-cookie") if h.startswith("kakao_oauth_client=")
    ]
    assert all("Max-Age=0" in h for h in client_cookies)


def test_callback_app_redirects_to_gaon_deeplink(client_with_fakes):
    client, fake_user = client_with_fakes
    client.cookies.set("kakao_oauth_state", "state-1")
    client.cookies.set("kakao_oauth_client", "app")
    res = client.get(
        "/auth/kakao/callback",
        params={"code": "auth-code", "state": "state-1"},
        follow_redirects=False,
    )
    assert res.status_code == 302
    location = res.headers["location"]
    assert location.startswith(auth_router.APP_CALLBACK_URL + "?")
    query = parse_qs(urlsplit(location).query)
    assert query["needs_onboarding"] == ["false"]
    assert query["token"][0]  # JWT 존재 — 유효성은 security 단위테스트 영역


def test_callback_web_returns_json_login_response(client_with_fakes):
    client, fake_user = client_with_fakes
    client.cookies.set("kakao_oauth_state", "state-1")
    res = client.get(
        "/auth/kakao/callback",
        params={"code": "auth-code", "state": "state-1"},
        follow_redirects=False,
    )
    assert res.status_code == 200
    body = res.json()
    assert body["user_id"] == str(fake_user.id)
    assert body["needs_onboarding"] is False
    assert body["access_token"]


def test_callback_rejects_state_mismatch(client_with_fakes):
    client, _ = client_with_fakes
    client.cookies.set("kakao_oauth_state", "state-1")
    res = client.get(
        "/auth/kakao/callback",
        params={"code": "auth-code", "state": "다른-state"},
        follow_redirects=False,
    )
    assert res.status_code == 400


def test_login_rejects_unknown_client():
    """client 파라미터는 web|app만 허용(Literal) — 오타는 조용히 웹으로 새지 않고 422."""
    client = TestClient(app)
    res = client.get("/auth/kakao/login", params={"client": "mobile"}, follow_redirects=False)
    assert res.status_code == 422


def _cookie_deletions(headers: list[str], name: str) -> list[str]:
    """set-cookie 헤더 중 name 쿠키의 삭제(Max-Age=0) 지시만 추림."""
    return [h for h in headers if h.startswith(f"{name}=") and "Max-Age=0" in h]


def test_login_web_clears_stale_app_client_cookie():
    """app으로 시작만 하고 이탈 → 그 안에 웹 로그인 시작.

    stale kakao_oauth_client 쿠키가 남아 있으면 이후 웹 콜백이 딥링크 302로 새어
    JWT가 브라우저 히스토리에 노출된다(리뷰 재현) — 웹 login 진입에서 삭제돼야 한다.
    """
    client = TestClient(app)
    client.get("/auth/kakao/login", params={"client": "app"}, follow_redirects=False)
    res = client.get("/auth/kakao/login", follow_redirects=False)
    assert _cookie_deletions(res.headers.get_list("set-cookie"), "kakao_oauth_client")


def test_callback_web_after_stale_app_start_returns_json(client_with_fakes):
    """회귀: app으로 login 시작(이탈) → 웹 login → 웹 콜백 전체 흐름.

    콜백은 딥링크 302가 아니라 JSON 200이어야 하고, 응답이 일회성 쿠키 2종
    (state·client)을 모두 삭제해 다음 로그인에 상태가 남지 않아야 한다.
    """
    client, fake_user = client_with_fakes
    # 1) app으로 시작만 하고 이탈 — client=app 쿠키가 600초 수명으로 남는다
    client.get("/auth/kakao/login", params={"client": "app"}, follow_redirects=False)
    # 2) 같은 브라우저에서 웹 로그인 시작 — stale client 쿠키가 여기서 삭제된다
    client.get("/auth/kakao/login", follow_redirects=False)
    # 3) 웹 콜백 — JSON 200 (state는 테스트 고정값으로 대체)
    client.cookies.set("kakao_oauth_state", "state-1")
    res = client.get(
        "/auth/kakao/callback",
        params={"code": "auth-code", "state": "state-1"},
        follow_redirects=False,
    )
    assert res.status_code == 200
    assert res.json()["user_id"] == str(fake_user.id)
    set_cookies = res.headers.get_list("set-cookie")
    assert _cookie_deletions(set_cookies, "kakao_oauth_state")
    assert _cookie_deletions(set_cookies, "kakao_oauth_client")


def test_callback_app_new_user_redirects_with_needs_onboarding(monkeypatch):
    """신규 유저(INSERT 분기, 기존 테스트 미커버) — needs_onboarding=true로 딥링크 복귀."""

    async def fake_exchange(code: str) -> str:
        return "kakao-access-token"

    async def fake_fetch(token: str):
        return SimpleNamespace(kakao_id="kakao-e2e-new", nickname="신규유저")

    monkeypatch.setattr(auth_router, "exchange_code_for_access_token", fake_exchange)
    monkeypatch.setattr(auth_router, "fetch_kakao_user", fake_fetch)

    db = MagicMock()
    db.execute.return_value.scalar_one_or_none.return_value = None  # 기존 유저 없음 → INSERT
    db.refresh.side_effect = lambda obj: setattr(obj, "id", uuid.uuid4())  # DB PK 부여 흉내

    saved_overrides = app.dependency_overrides.copy()
    app.dependency_overrides[get_db] = lambda: db
    try:
        client = TestClient(app)
        client.cookies.set("kakao_oauth_state", "state-1")
        client.cookies.set("kakao_oauth_client", "app")
        res = client.get(
            "/auth/kakao/callback",
            params={"code": "auth-code", "state": "state-1"},
            follow_redirects=False,
        )
    finally:
        app.dependency_overrides = saved_overrides

    assert res.status_code == 302
    query = parse_qs(urlsplit(res.headers["location"]).query)
    assert query["needs_onboarding"] == ["true"]
    assert query["token"][0]
    db.add.assert_called_once()  # INSERT 경로를 실제로 탔는지
