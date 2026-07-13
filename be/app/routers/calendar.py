"""앱 내 캘린더 = F-DOC-7 (SSOT §11·§12). document_results.calendar_events(ActionCard 결과,
§15 보강분)를 실제 calendar_events 테이블로 옮겨 담는다.

중복 방지 정책(2026-07-13 QA D-3):
- 전체 저장(selected 미전달, 기존 계약): 이 문서로 만든 기존 이벤트를 전부 지우고 다시
  채운다(멱등 전체 동기화 — 버튼 중복 클릭에도 중복 생성 없음).
- 선택 저장(selected 전달): 선택된 (title, date) 키와 일치하는 기존 행만 지우고 그
  키들만 다시 넣는다 — 이전에 저장해 둔 다른 일정은 유지되고, 같은 선택을 다시
  저장해도 중복이 생기지 않는다(합집합 유지 + 멱등).
selected는 엔드포인트 로컬 모델이다 — shared-schema 무변경(§16 규칙).

GET /calendar/events는 SSOT §11 원문엔 없다 — §13 ②홈 '다가오는 일정'과
v0.6 §17.5 ⑨전용 캘린더 페이지(F-CAL-1) 둘 다 목록 조회가 필요해서 추가했다."""

from __future__ import annotations

import calendar as _calendar_module
import uuid
from datetime import date as date_type

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel
from sqlalchemy import delete, select, tuple_
from sqlalchemy.orm import Session

from app.db import get_db
from app.models import CalendarEventRow, Document, DocumentResultRow, User
from app.security import get_current_user

router = APIRouter(tags=["calendar"])


class SelectedEventKey(BaseModel):
    """선택 저장 키 — ActionCard.calendar_events 항목을 (title, date)로 지정한다."""

    title: str
    date: date_type


class CalendarEventsRequest(BaseModel):
    document_id: uuid.UUID
    # 미전달(None) = 기존 계약(문서의 전체 일정 저장). 전달 시 해당 항목만 저장.
    selected: list[SelectedEventKey] | None = None


class CreatedEvent(BaseModel):
    title: str
    date: str
    type: str


class CalendarEventsResponse(BaseModel):
    created: list[CreatedEvent]


class CalendarEventItem(BaseModel):
    id: str
    document_id: str | None
    child_id: str | None
    title: str
    date: str
    type: str


class CalendarEventListResponse(BaseModel):
    events: list[CalendarEventItem]


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

    events = list(result_row.calendar_events)
    if body.selected is None:
        # 전체 저장(기존 계약) — 문서 단위 멱등 전체 동기화
        db.execute(delete(CalendarEventRow).where(CalendarEventRow.document_id == document.id))
    else:
        # 선택 저장 — 선택 키와 일치하는 항목만 대상. 이전 저장분(다른 키)은 유지한다.
        selected_keys = {(k.title, k.date) for k in body.selected}
        events = [
            e for e in events if (e["title"], date_type.fromisoformat(e["date"])) in selected_keys
        ]
        if events:
            # 같은 선택을 다시 저장해도 중복이 생기지 않게 해당 키 기존 행만 교체
            db.execute(
                delete(CalendarEventRow).where(
                    CalendarEventRow.document_id == document.id,
                    tuple_(CalendarEventRow.title, CalendarEventRow.event_date).in_(
                        [(e["title"], date_type.fromisoformat(e["date"])) for e in events]
                    ),
                )
            )

    created: list[CreatedEvent] = []
    for event in events:
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


@router.get("/calendar/events", response_model=CalendarEventListResponse)
def list_calendar_events(
    month: str | None = Query(
        default=None,
        description="YYYY-MM. 지정 시 해당 월만, 생략 시 과거 포함 전체 일정(캘린더 페이지 누적 조회)",
    ),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> CalendarEventListResponse:
    stmt = select(CalendarEventRow).where(CalendarEventRow.user_id == current_user.id)

    if month is not None:
        try:
            year, mon = (int(part) for part in month.split("-"))
            start = date_type(year, mon, 1)
        except ValueError as exc:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST, detail="month는 YYYY-MM 형식이어야 합니다"
            ) from exc
        _, days_in_month = _calendar_module.monthrange(year, mon)
        end = date_type(year, mon, days_in_month)
        stmt = stmt.where(CalendarEventRow.event_date.between(start, end))
    # month 생략 시 날짜 필터 없음 — 알림장 일정은 지난 행사 등 과거 날짜가 많아
    # '오늘 이후' 디폴트면 저장 직후에도 캘린더 탭에 안 보인다(2026-07-11 보고).
    # 홈 '다가오는 일정'은 FE(chat_screen)가 클라이언트에서 오늘 이후로 거른다.

    stmt = stmt.order_by(CalendarEventRow.event_date)
    rows = db.execute(stmt).scalars().all()

    return CalendarEventListResponse(
        events=[
            CalendarEventItem(
                id=str(row.id),
                document_id=str(row.document_id) if row.document_id else None,
                child_id=str(row.child_id) if row.child_id else None,
                title=row.title,
                date=row.event_date.isoformat(),
                type=row.type,
            )
            for row in rows
        ]
    )
