"""앱 내 캘린더 = F-DOC-7 (SSOT §11·§12). document_results.calendar_events(ActionCard 결과,
§15 보강분)를 실제 calendar_events 테이블로 옮겨 담는다. 재호출 시 이 문서로 만든 기존
이벤트를 지우고 다시 채워서 중복 생성(버튼 중복 클릭 등)을 막는다."""

from __future__ import annotations

import uuid
from datetime import date as date_type

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy import delete
from sqlalchemy.orm import Session

from app.db import get_db
from app.models import CalendarEventRow, Document, DocumentResultRow, User
from app.security import get_current_user

router = APIRouter(tags=["calendar"])


class CalendarEventsRequest(BaseModel):
    document_id: uuid.UUID


class CreatedEvent(BaseModel):
    title: str
    date: str
    type: str


class CalendarEventsResponse(BaseModel):
    created: list[CreatedEvent]


@router.post("/calendar/events", response_model=CalendarEventsResponse)
def create_calendar_events(
    body: CalendarEventsRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> CalendarEventsResponse:
    document = db.get(Document, body.document_id)
    if document is None or document.user_id != current_user.id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="문서를 찾을 수 없습니다")

    result_row = db.get(DocumentResultRow, body.document_id)
    if result_row is None:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="아직 처리 중입니다")

    db.execute(delete(CalendarEventRow).where(CalendarEventRow.document_id == document.id))

    created: list[CreatedEvent] = []
    for event in result_row.calendar_events:
        row = CalendarEventRow(
            user_id=current_user.id,
            document_id=document.id,
            child_id=event.get("child_id") or document.child_id,
            title=event["title"],
            event_date=date_type.fromisoformat(event["date"]),
            type=event["type"],
        )
        db.add(row)
        created.append(CreatedEvent(title=row.title, date=event["date"], type=row.type))

    db.commit()
    return CalendarEventsResponse(created=created)
