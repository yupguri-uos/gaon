from __future__ import annotations

import secrets

from fastapi import APIRouter, Cookie, Depends, HTTPException, Response, status
from fastapi.responses import RedirectResponse
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db import get_db
from app.models.common import User
from app.security import create_access_token
from app.services.kakao import (
    get_kakao_login_url,
    exchange_code_for_access_token,
    fetch_kakao_user,
    KakaoAPIError,
)

router = APIRouter()
STATE_COOKIE_NAME = "kakao_oauth_state"


class LoginResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user_id: str
    needs_onboarding: bool


@router.get("/kakao/login")
def kakao_login() -> RedirectResponse:
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

    return response


@router.get("/kakao/callback", response_model=LoginResponse)
async def kakao_callback(
    response: Response,
    code: str,
    state: str,
    kakao_oauth_state: str | None = Cookie(
        default=None,
        alias=STATE_COOKIE_NAME,
    ),  # 쿠키에서 STATE_COOKIE_NAME이라는 이름의 값이 있으면 str을 넣고 없으면 None을 넣어라
    db: Session = Depends(get_db),
) -> LoginResponse:
    if (
        kakao_oauth_state is None
        or not secrets.compare_digest(state, kakao_oauth_state) #state1 == state2해도되지만 compare_digest를 하는것이 타이밍 공격을 막을 수 있다 
    ):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail = "유효하지 않은 OAuth state입니다",
        )

    try:
        kakao_access_token = await exchange_code_for_access_token(code)
        kakao_user = await fetch_kakao_user(kakao_access_token)
    except KakaoAPIError as exc: 
        raise HTTPException(
            status_code = status.HTTP_502_BAD_GATEWAY,
            detail = str(exc),
        ) from exc
        
    user = db.execute(
        select(User).where(User.kakao_id == kakao_user.kakao_id)
    ).scalar_one_or_none()
    
    if user is None:
        user = User(
            kakao_id = kakao_user.kakao_id,
            display_name = kakao_user.nickname,
        )
        db.add(user)
        db.commit()
        db.refresh(user)
    
    elif user.display_name is None and kakao_user.nickname:
        user.display_name = kakao_user.nickname
        db.commit()
        db.refresh(user)
        
    gaon_access_token = create_access_token(user.id)
    
    response.delete_cookie(STATE_COOKIE_NAME) #검증이 끝나면 일회성 쿠키는 지움
    
    return LoginResponse(
        access_token=gaon_access_token,
        user_id = str(user.id),
        needs_onboarding=user.needs_onboarding,
    )
    
    
