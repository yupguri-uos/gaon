"""세션 검증 = stateless JWT(§12 '단순한 쪽으로'). 서버측 세션 테이블 없음.

토큰 발급(로그인 성공 시 JWT 생성)은 카카오 인증(박수빈 스코프)에서 담당한다.
아래와 호환되려면 로그인 엔드포인트가 발급하는 JWT가 이 조건을 지켜야 한다:
  - SESSION_SECRET(.env) 시크릿으로 HS256 서명
  - payload에 {"sub": <User.id, str(uuid)>} 포함(만료는 "exp" 클레임으로, 선택)
"""

from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone 

import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.config import settings
from app.db import get_db
from app.models import User


_bearer_scheme = HTTPBearer()


def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(_bearer_scheme),
    db: Session = Depends(get_db),
) -> User:
    try:
        payload = jwt.decode(
            credentials.credentials, settings.session_secret, algorithms=[_ALGORITHM]
        )
        user_id = uuid.UUID(payload["sub"])
    except (jwt.PyJWTError, ValueError, KeyError) as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="세션이 유효하지 않습니다"
        ) from exc

    user = db.execute(select(User).where(User.id == user_id)).scalar_one_or_none()
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="사용자를 찾을 수 없습니다"
        )
    return user


def create_access_token(user_id: uuid.UUID) -> str:
    now = datetime.now(timezone.utc)
    
    payload = {
            "sub":str(user_id),
            "iat":now,
            "exp": now + timedelta(minutes=settings.access_token_expire_minutes),
        }
    return jwt.encode(
        payload, 
        settings.session_secret,
        algorithm=settings.jwt_algorithm,
        ) 