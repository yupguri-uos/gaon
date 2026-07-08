"""교사 소통 = Chain B (F-TCH-1~4, SSOT §11). 생성까지만 — 전송은 사용자가 수동으로
한다(결정 #2, F-TCH-3). Chain A와 달리 단일 LLM 호출이라 BackgroundTasks/폴링 없이
요청-응답으로 바로 처리한다(§12).

child_info는 클라이언트가 중복 입력하지 않고 child_id로 받아 BE가 Child를 조회해
구성한다(§17.10과 동일한 패턴 — 소유권 검증도 여기서 같이 한다)."""

from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from gaon_shared import ChildInfo, MessageSituation, TeacherCommInput
from gaon_shared import TeacherMessage as TeacherMessageSchema
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.chain_deps import get_llm_client
from app.db import get_db
from app.models import Child, MessageRow, User
from app.security import get_current_user
from gaon_ai.chain_a import ChainError
from gaon_ai.chain_b import run_chain_b

router = APIRouter(tags=["teacher-message"])


class TeacherMessageRequest(BaseModel):
    child_id: uuid.UUID
    situation: MessageSituation
    input_native: str


@router.post("/teacher-message", response_model=TeacherMessageSchema)
async def create_teacher_message(
    body: TeacherMessageRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> TeacherMessageSchema:
    if current_user.needs_onboarding:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="온보딩이 필요합니다")

    child = db.get(Child, body.child_id)
    if child is None or child.user_id != current_user.id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="자녀를 찾을 수 없습니다")
    if child.grade is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail="자녀 학년 정보가 필요합니다"
        )

    try:
        result = await run_chain_b(
            TeacherCommInput(
                input_native=body.input_native,
                situation=body.situation,
                native_language=current_user.native_language,
                child_info=ChildInfo(grade=child.grade, class_no=child.class_no, name=child.name),
            ),
            llm=get_llm_client(),
        )
    except ChainError as exc:
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail=str(exc)) from exc

    db.add(
        MessageRow(
            user_id=current_user.id,
            child_id=child.id,
            situation=result.situation,
            input_native=result.input_native,
            output_ko=result.output_ko,
            admin_guide_native=result.admin_guide_native,
        )
    )
    db.commit()

    return result
