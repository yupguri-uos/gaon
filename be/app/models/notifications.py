"""Proactive 알림 ORM(F-PRO, 마이그레이션 0010): notifications + device_tokens.

테이블은 0010에서 이미 생성돼 있었으나 앱 코드 배선이 없어 FE가 '항상 빈 배열'
스텁으로 돌던 부분 — §11 라우터(routers/notifications.py)에서 사용한다.
FCM '발송'은 결정 #10으로 실구현 범위 제외 — 여기는 조회·읽음·토큰 등록만 다룬다.
"""

from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import DateTime, Enum, ForeignKey, Index, Text, UniqueConstraint, text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from gaon_shared import Notification as NotificationSchema

from app.db import Base

NotiKind = Enum(
    "deadline_d2",
    "unreplied_consent",
    "event_preview",
    name="noti_kind",
    create_type=False,
)


class NotificationRow(Base):
    """능동 알림(F-PRO-1). 생성은 Proactive 스캐너(배치) 몫 — 여기선 조회·읽음만."""

    __tablename__ = "notifications"
    __table_args__ = (
        UniqueConstraint(
            "user_id", "type", "related_document_id", "scheduled_at", name="uq_noti_dedup"
        ),
        Index("idx_noti_due", "scheduled_at", postgresql_where=text("sent_at IS NULL")),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, server_default=text("gen_random_uuid()")
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    child_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True))
    type: Mapped[str] = mapped_column(NotiKind, nullable=False)
    title_native: Mapped[str] = mapped_column(Text, nullable=False)
    body_native: Mapped[str] = mapped_column(Text, nullable=False)
    scheduled_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    related_document_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True))
    sent_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    read_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=text("now()")
    )

    def to_schema(self) -> NotificationSchema:
        # sent_at/read_at은 DB 운영 컬럼 — shared-schema 계약(§7)에는 없음.
        return NotificationSchema(
            notification_id=str(self.id),
            user_id=str(self.user_id),
            child_id=str(self.child_id) if self.child_id else None,
            type=self.type,
            title_native=self.title_native,
            body_native=self.body_native,
            scheduled_at=self.scheduled_at,
            related_document_id=(
                str(self.related_document_id) if self.related_document_id else None
            ),
        )


class DeviceTokenRow(Base):
    """FCM 기기 토큰(F-PRO-2). 등록만 받아둔다 — 발송은 결정 #10으로 범위 제외."""

    __tablename__ = "device_tokens"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, server_default=text("gen_random_uuid()")
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    token: Mapped[str] = mapped_column(Text, nullable=False, unique=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=text("now()")
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=text("now()")
    )
