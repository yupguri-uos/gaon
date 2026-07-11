"""F-ON-1 프로필 조회·수정 (SSOT §11: GET /me · PATCH /profile).

GET /me는 §11 명세('UserProfile|null')에 있었으나 미구현이라 FE가 온보딩 응답
캐시로 우회하던 항목 — 온보딩 전(origin_country/native_language 미설정)에는
shared User 계약을 만족할 수 없으므로 §11 원문대로 null을 반환한다.
PATCH /profile은 User 필드만 부분 수정(자녀 정보는 별도, F-ON-4 설정 페이지 영역)."""

from __future__ import annotations

from fastapi import APIRouter, Depends
from gaon_shared import NativeLanguage, OriginCountry
from gaon_shared import User as UserSchema
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.db import get_db
from app.models import User
from app.security import get_current_user

router = APIRouter(tags=["profile"])


@router.get("/me", response_model=UserSchema | None)
def get_me(current_user: User = Depends(get_current_user)) -> UserSchema | None:
    """내 프로필(§13 ⓪ user!=null 분기용). 온보딩 전이면 null — FE는 온보딩으로 라우팅."""
    if current_user.needs_onboarding:
        return None
    return current_user.to_schema()


class ProfileUpdateRequest(BaseModel):
    display_name: str | None = None
    origin_country: OriginCountry | None = None
    native_language: NativeLanguage | None = None


@router.patch("/profile", response_model=UserSchema)
def update_profile(
    body: ProfileUpdateRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> UserSchema:
    for field, value in body.model_dump(exclude_unset=True).items():
        setattr(current_user, field, value)
    db.commit()
    db.refresh(current_user)
    return current_user.to_schema()
