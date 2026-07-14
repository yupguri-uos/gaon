from __future__ import annotations

import logging
import secrets
from typing import Literal
from urllib.parse import urlencode

from fastapi import APIRouter, Cookie, Depends, HTTPException, Response, status
from fastapi.responses import RedirectResponse
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.orm import Session

from app import storage
from app.db import get_db
from app.models.common import Document, User
from app.routers.common import OkResponse
from app.security import create_access_token, get_current_user
from app.services.kakao import (
    get_kakao_login_url,
    exchange_code_for_access_token,
    fetch_kakao_user,
    KakaoAPIError,
)

logger = logging.getLogger(__name__)

router = APIRouter()
STATE_COOKIE_NAME = "kakao_oauth_state"
CLIENT_COOKIE_NAME = "kakao_oauth_client"

# Flutter 앱 딥링크 콜백(F-ON-3) — FE의 AndroidManifest/Info.plist에 등록된
# 커스텀 스킴과 반드시 일치해야 한다(fe/lib/main.dart 참조).
APP_CALLBACK_URL = "gaon://auth/callback"


class LoginResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user_id: str
    needs_onboarding: bool


@router.get("/kakao/login")
def kakao_login(client: Literal["web", "app"] = "web") -> RedirectResponse:
    """카카오 로그인 진입. client=app이면 콜백에서 앱 딥링크로 토큰을 넘긴다(F-ON-3).

    Flutter 앱은 외부 브라우저로 이 URL(?client=app)을 열고,
    /kakao/callback이 gaon:// 딥링크로 복귀시킨다. 웹(기본)은 기존 JSON 응답 유지.
    """
    state_value = secrets.token_urlsafe(32)  # state생성

    login_url = get_kakao_login_url(state_value)  # 로그인 url 생성

    response = RedirectResponse(
        url=login_url,
        status_code=status.HTTP_302_FOUND,  # 다른 페이지로 리다이렉트라는 의미
    )

    response.set_cookie(
        key=STATE_COOKIE_NAME,
        value=state_value,  # state 검증할 값 저장
        max_age=600,
        httponly=True,
        secure=False,  # HTTPS 배포 환경에서 True로 변경
        samesite="lax",
    )

    if client == "app":
        # 콜백에서 딥링크 분기 판별용 — state와 같은 수명의 일회성 쿠키
        response.set_cookie(
            key=CLIENT_COOKIE_NAME,
            value="app",
            max_age=600,
            httponly=True,
            secure=False,  # HTTPS 배포 환경에서 True로 변경
            samesite="lax",
        )
    else:
        # app으로 시작만 하고 완료하지 않으면 이 쿠키가 600초 남아, 그 안의 웹 로그인이
        # 딥링크 302로 새어 JWT가 브라우저 히스토리에 노출된다 — 웹 진입 시 제거
        response.delete_cookie(CLIENT_COOKIE_NAME)

    return response


@router.get(
    "/kakao/callback",
    response_model=None,  # 반환이 JSON|302 유니언이라 자동 추론 불가
    responses={200: {"model": LoginResponse}},  # OpenAPI 문서에 웹 분기 계약 복원
)
async def kakao_callback(
    response: Response,
    code: str,
    state: str,
    kakao_oauth_state: str | None = Cookie(
        default=None,
        alias=STATE_COOKIE_NAME,
    ),  # 쿠키에서 STATE_COOKIE_NAME이라는 이름의 값이 있으면 str을 넣고 없으면 None을 넣어라
    kakao_oauth_client: str | None = Cookie(
        default=None,
        alias=CLIENT_COOKIE_NAME,
    ),  # /kakao/login?client=app에서 심은 딥링크 분기 플래그
    db: Session = Depends(get_db),
) -> LoginResponse | RedirectResponse:
    if kakao_oauth_state is None or not secrets.compare_digest(
        # str 비교는 비ASCII 입력에서 TypeError(500)를 내므로 bytes로 비교한다
        state.encode("utf-8"),
        kakao_oauth_state.encode("utf-8"),
    ):  # state1 == state2해도되지만 compare_digest를 하는것이 타이밍 공격을 막을 수 있다
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="유효하지 않은 OAuth state입니다",
        )

    try:
        kakao_access_token = await exchange_code_for_access_token(code)
        kakao_user = await fetch_kakao_user(kakao_access_token)
    except KakaoAPIError as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=str(exc),
        ) from exc

    user = db.execute(select(User).where(User.kakao_id == kakao_user.kakao_id)).scalar_one_or_none()

    if user is None:
        user = User(
            kakao_id=kakao_user.kakao_id,
            display_name=kakao_user.nickname,
        )
        db.add(user)
        db.commit()
        db.refresh(user)

    elif user.display_name is None and kakao_user.nickname:
        user.display_name = kakao_user.nickname
        db.commit()
        db.refresh(user)

    gaon_access_token = create_access_token(user.id)

    if kakao_oauth_client == "app":
        # Flutter 앱 복귀(F-ON-3): 커스텀 스킴 딥링크로 토큰 전달.
        # 딥링크 쿼리는 기기 내 앱으로만 전달되므로 MVP 수준에서 허용(§12 stateless JWT).
        deeplink = (
            f"{APP_CALLBACK_URL}"
            f"?{urlencode({'token': gaon_access_token, 'needs_onboarding': str(user.needs_onboarding).lower()})}"
        )
        redirect = RedirectResponse(url=deeplink, status_code=status.HTTP_302_FOUND)
        redirect.delete_cookie(STATE_COOKIE_NAME)
        redirect.delete_cookie(CLIENT_COOKIE_NAME)
        return redirect

    response.delete_cookie(STATE_COOKIE_NAME)  # 검증이 끝나면 일회성 쿠키는 지움
    response.delete_cookie(CLIENT_COOKIE_NAME)  # stale 딥링크 분기 쿠키도 방어적으로 제거

    return LoginResponse(
        access_token=gaon_access_token,
        user_id=str(user.id),
        needs_onboarding=user.needs_onboarding,
    )


@router.post("/logout", response_model=OkResponse)
def logout(current_user: User = Depends(get_current_user)) -> OkResponse:
    """로그아웃(§11: POST /auth/logout). 세션은 stateless JWT(§12 확정)라 서버 상태가
    없다 — 클라이언트가 토큰을 폐기하면 끝. 형식적 확인 응답만 준다(토큰 유효성 검증 겸용)."""
    return OkResponse()


@router.delete("/me", response_model=OkResponse)
def delete_account(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> OkResponse:
    """회원 탈퇴 — 본인 계정 삭제. users 한 줄만 지우면 자녀·문서·캘린더·활동로그·
    메시지·알림·디바이스토큰이 FK ON DELETE CASCADE로 함께 삭제된다(결정 #7-PII).

    MinIO 이미지 오브젝트는 best-effort로 함께 정리한다(QA A-4) — 스토리지 실패가
    계정 삭제를 막으면 안 되므로 오류는 로그만 남기고 진행한다.
    stateless JWT라 토큰 폐기는 클라이언트가 담당한다."""
    # 삭제 전에 이 사용자의 이미지 키를 모아 둔다(CASCADE로 rows가 사라지기 전)
    image_keys = (
        db.execute(select(Document.image_ref).where(Document.user_id == current_user.id))
        .scalars()
        .all()
    )

    db.delete(current_user)
    db.commit()

    for key in image_keys:
        if not key:
            continue
        try:
            storage.delete_image(key)
        except Exception as exc:  # noqa: BLE001 — best-effort: 계정 삭제가 우선
            logger.warning("탈퇴 이미지 정리 실패(무시): key=%s err=%s", key, exc)
    return OkResponse()
