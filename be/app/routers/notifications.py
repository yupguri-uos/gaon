"""능동 알림 = Proactive (F-PRO-1~3, SSOT §11).

§11 명세 3종을 배선한다:
  - GET   /notifications            → Notification[] (shared-schema 그대로)
  - POST  /notifications/fcm-token  → {ok} (device_tokens upsert)
  - PATCH /notifications/{id}/read  → {ok}

주의: 알림 '생성'은 스케줄러(배치) 워커 몫이고(§11: "스케줄러는 엔드포인트 아님"),
FCM '발송'은 결정 #10(2026-07-10)으로 실구현 범위에서 제외됐다.
여기는 순수 조회·상태 API — 테이블(0010)이 비어 있으면 빈 배열이 정상이다.
이 라우터가 생기면서 FE ApiRepository.getNotifications의 '항상 빈 배열' 스텁이 제거된다.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from gaon_shared import Notification as NotificationSchema
from pydantic import BaseModel
from sqlalchemy import select, text
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.orm import Session

from app.db import get_db
from app.models import DeviceTokenRow, NotificationRow, User
from app.routers.common import OkResponse
from app.security import get_current_user

router = APIRouter(tags=["notifications"])


class FcmTokenRequest(BaseModel):
    fcm_token: str


@router.get("/notifications", response_model=list[NotificationSchema])
def list_notifications(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> list[NotificationSchema]:
    """내 알림 목록 — 최신(scheduled_at) 순. 읽음 여부와 무관하게 전부 반환(§7 계약에 read 필드 없음)."""
    rows = (
        db.execute(
            select(NotificationRow)
            .where(NotificationRow.user_id == current_user.id)
            .order_by(NotificationRow.scheduled_at.desc())
        )
        .scalars()
        .all()
    )
    return [row.to_schema() for row in rows]


@router.post("/notifications/fcm-token", response_model=OkResponse)
def register_fcm_token(
    body: FcmTokenRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> OkResponse:
    """기기 토큰 등록(F-PRO-2). 같은 토큰 재등록이면 소유자·시각만 갱신(멱등).

    select-then-insert는 동시 등록 시 unique 위반(500)이 가능 — PG 네이티브 upsert로 처리.
    """
    stmt = pg_insert(DeviceTokenRow).values(user_id=current_user.id, token=body.fcm_token)
    stmt = stmt.on_conflict_do_update(
        index_elements=[DeviceTokenRow.token],
        # 기기 주인이 바뀐 경우(재로그인) 이관
        set_={"user_id": current_user.id, "updated_at": text("now()")},
    )
    db.execute(stmt)
    db.commit()
    return OkResponse()


@router.patch("/notifications/{notification_id}/read", response_model=OkResponse)
def mark_notification_read(
    notification_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> OkResponse:
    notification = db.get(NotificationRow, notification_id)
    if notification is None or notification.user_id != current_user.id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="알림을 찾을 수 없습니다")
    if notification.read_at is None:  # 중복 read 호출은 최초 시각 유지(멱등)
        notification.read_at = datetime.now(timezone.utc)
        db.commit()
    return OkResponse()
