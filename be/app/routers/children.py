"""F-ON-4: 다자녀 관리(설정 페이지). SSOT §17.3 — 온보딩(POST /onboarding)이 만드는
첫 자녀 1명 이후로, 자녀 추가·수정·삭제를 여기서 다룬다. name·class_no는 미성년 PII라
결정 #7-PII에 따라 동의(consent_child_pii=true)가 있을 때만 저장한다."""

from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from gaon_shared import Child as ChildSchema
from gaon_shared import ChildGrade
from pydantic import BaseModel
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.db import get_db
from app.models import Child, User
from app.security import get_current_user

router = APIRouter(tags=["children"])

MAX_CHILDREN = 5  # 자녀 수 상한(QA 2026-07-11). 남용 방지 — 온보딩 첫 자녀 포함해 총 5명.


class ChildCreateRequest(BaseModel):
    grade: ChildGrade
    name: str | None = None
    class_no: str | None = None
    school_name: str | None = None
    color: str | None = None
    consent_child_pii: bool = False


class ChildUpdateRequest(BaseModel):
    grade: ChildGrade | None = None
    name: str | None = None
    class_no: str | None = None
    school_name: str | None = None
    color: str | None = None
    consent_child_pii: bool = False


def _get_owned_child(db: Session, child_id: uuid.UUID, user: User) -> Child:
    child = db.get(Child, child_id)
    if child is None or child.user_id != user.id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="자녀를 찾을 수 없습니다")
    return child


@router.get("/children", response_model=list[ChildSchema])
def list_children(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> list[ChildSchema]:
    rows = (
        db.execute(select(Child).where(Child.user_id == current_user.id).order_by(Child.created_at))
        .scalars()
        .all()
    )
    return [row.to_schema() for row in rows]


@router.post("/children", response_model=ChildSchema, status_code=status.HTTP_201_CREATED)
def create_child(
    body: ChildCreateRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> ChildSchema:
    if (body.name or body.class_no) and not body.consent_child_pii:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="이름·반 저장에는 consent_child_pii 동의가 필요합니다",
        )

    child_count = db.scalar(
        select(func.count()).select_from(Child).where(Child.user_id == current_user.id)
    )
    if child_count >= MAX_CHILDREN:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"자녀는 최대 {MAX_CHILDREN}명까지 등록할 수 있습니다",
        )

    child = Child(
        user_id=current_user.id,
        grade=body.grade,
        name=body.name if body.consent_child_pii else None,
        class_no=body.class_no if body.consent_child_pii else None,
        school_name=body.school_name,
        color=body.color,
    )
    db.add(child)
    db.commit()
    db.refresh(child)
    return child.to_schema()


@router.patch("/children/{child_id}", response_model=ChildSchema)
def update_child(
    child_id: uuid.UUID,
    body: ChildUpdateRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> ChildSchema:
    child = _get_owned_child(db, child_id, current_user)

    fields = body.model_dump(exclude_unset=True, exclude={"consent_child_pii"})
    if ("name" in fields or "class_no" in fields) and not body.consent_child_pii:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="이름·반 저장에는 consent_child_pii 동의가 필요합니다",
        )

    for field, value in fields.items():
        setattr(child, field, value)

    db.commit()
    db.refresh(child)
    return child.to_schema()


@router.delete("/children/{child_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_child(
    child_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> None:
    child = _get_owned_child(db, child_id, current_user)
    db.delete(child)
    db.commit()
