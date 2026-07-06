"""교사 소통 = Chain B 결과 ORM(SSOT §15 + §11): messages. 생성만 저장 — 전송 없음(결정 #2).

child_id는 SSOT §15 DDL엔 없지만 documents·calendar_events·notifications와 패턴을 맞추려
추가했다(§17.6) — 자녀별 메시지 이력 조회(F-LOG)에 필요. SSOT 갱신 필요."""

from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import DateTime, Enum, ForeignKey, Index, Text, text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base

MsgSituation = Enum(
    "absence",
    "sick_note",
    "consultation",
    "custom",
    name="msg_situation",
    create_type=False,
)


class MessageRow(Base):
    """Teacher Communication 결과(F-TCH-1~4)."""

    __tablename__ = "messages"
    __table_args__ = (Index("idx_messages_user_created", "user_id", "created_at"),)

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, server_default=text("gen_random_uuid()")
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    child_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("children.id", ondelete="SET NULL")
    )
    situation: Mapped[str] = mapped_column(MsgSituation, nullable=False)
    input_native: Mapped[str] = mapped_column(Text, nullable=False)
    output_ko: Mapped[str] = mapped_column(Text, nullable=False)
    admin_guide_native: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=text("now()")
    )
