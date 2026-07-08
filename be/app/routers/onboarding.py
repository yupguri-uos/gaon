"""F-ON-1: 온보딩 = 보호자 프로필 완성 + 자녀 1명 등록(SSOT §11, §17.4 반영).

SSOT §11 원문(in: {origin_country, native_language, child_grade})은 v0.6 이전
UserProfile 기준이라 User+Child 분리(§17.4)에 맞게 확장했다. 자녀 이름·반은
미성년 PII라 결정 #7-PII(동의 기반)에 따라 consent_child_pii=true일 때만 저장한다.
F-ON-4(다자녀 추가·수정)는 별도 설정 페이지 엔드포인트로, 여기서는 첫 자녀 1명만 받는다.
"""

from __future__ import annotations

from datetime import datetime, timezone

from fastapi import APIRouter, Depends
from gaon_shared import Child as ChildSchema
from gaon_shared import ChildGrade, NativeLanguage, OriginCountry
from gaon_shared import User as UserSchema
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.db import get_db
from app.models import Child, User
from app.security import get_current_user

router = APIRouter(tags=["onboarding"])


class OnboardingRequest(BaseModel):
    origin_country: OriginCountry
    native_language: NativeLanguage
    child_grade: ChildGrade
    child_name: str | None = None
    child_class_no: str | None = None
    child_school_name: str | None = None
    consent_child_pii: bool = False


class OnboardingResponse(BaseModel):
    user: UserSchema
    child: ChildSchema


@router.post("/onboarding", response_model=OnboardingResponse)
def onboard(
    body: OnboardingRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> OnboardingResponse:
    current_user.origin_country = body.origin_country
    current_user.native_language = body.native_language
    current_user.onboarded_at = datetime.now(timezone.utc)

    child = Child(
        user_id=current_user.id,
        grade=body.child_grade,
        name=body.child_name if body.consent_child_pii else None,
        class_no=body.child_class_no if body.consent_child_pii else None,
        school_name=body.child_school_name,
    )
    db.add(child)
    db.commit()
    db.refresh(current_user)
    db.refresh(child)

    return OnboardingResponse(user=current_user.to_schema(), child=child.to_schema())
