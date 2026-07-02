"""F-ON-1 프로필 수정 (SSOT §11: PATCH /profile). Partial<UserProfile> → 이제 User 필드만
부분 수정한다(자녀 정보는 별도, F-ON-4 설정 페이지 영역). 보낸 필드만 갱신한다."""

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
