"""Chain A 결과 ORM(SSOT §15): extracted_items · document_results.

document_results.calendar_events는 SSOT §15 DDL에 없던 컬럼이다. document_results는
"번역·행동 결과(Cultural Translation + Lifestyle Action) 1:1"을 저장하는 표인데, Lifestyle
Action의 실제 출력인 ActionCard에는 calendar_events가 있고 SSOT DDL만 그 컬럼을 빠뜨렸다.
없으면 GET /documents/{id}/result를 나중에 재조회할 때 캘린더 이벤트가 유실되므로 추가했다.
SSOT §15도 이 컬럼을 반영해 갱신이 필요하다(박수빈 공유 필요).
"""

from __future__ import annotations

import uuid
from datetime import date, datetime

from sqlalchemy import Boolean, Date, DateTime, ForeignKey, Index, Text, text
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base


class ExtractedItemRow(Base):
    """Document Parsing 결과(F-DOC-3). doc_type·title은 documents 테이블에 있다(§15)."""

    __tablename__ = "extracted_items"
    __table_args__ = (
        Index("idx_extracted_deadline", "deadline", postgresql_where=text("deadline IS NOT NULL")),
    )

    document_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("documents.id", ondelete="CASCADE"), primary_key=True
    )
    deadline: Mapped[date | None] = mapped_column(Date)
    requires_reply: Mapped[bool] = mapped_column(
        Boolean, nullable=False, server_default=text("false")
    )
    dates: Mapped[list] = mapped_column(JSONB, nullable=False, server_default=text("'[]'::jsonb"))
    amounts: Mapped[list] = mapped_column(JSONB, nullable=False, server_default=text("'[]'::jsonb"))
    supplies: Mapped[list] = mapped_column(
        JSONB, nullable=False, server_default=text("'[]'::jsonb")
    )
    checkboxes: Mapped[list] = mapped_column(
        JSONB, nullable=False, server_default=text("'[]'::jsonb")
    )
    raw_text: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=text("now()")
    )


class DocumentResultRow(Base):
    """Cultural Translation + Lifestyle Action 결과(F-DOC-5/6/7/8) 1:1."""

    __tablename__ = "document_results"

    document_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("documents.id", ondelete="CASCADE"), primary_key=True
    )
    summary_native: Mapped[str | None] = mapped_column(Text)
    terms: Mapped[list] = mapped_column(JSONB, nullable=False, server_default=text("'[]'::jsonb"))
    action_supplies: Mapped[list] = mapped_column(
        JSONB, nullable=False, server_default=text("'[]'::jsonb")
    )
    calendar_events: Mapped[list] = mapped_column(
        JSONB, nullable=False, server_default=text("'[]'::jsonb")
    )
    reply_draft_ko: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=text("now()")
    )
