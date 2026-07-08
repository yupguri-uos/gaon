"""공통 테이블 ORM(SSOT §15 + §17.6): users · children · documents.

users.child_grade는 v0.6에서 children으로 이관·deprecated(§17.6) — 새 스키마라 처음부터 넣지 않는다.
extracted_items·document_results·calendar_events(이지수 스코프)와
notifications·messages·activity_events·device_tokens(박수빈 스코프)는 각자 마이그레이션에서 추가한다.
"""

from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import CheckConstraint, DateTime, Enum, ForeignKey, Index, Text, text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from gaon_shared import Child as ChildSchema
from gaon_shared import Document as DocumentSchema
from gaon_shared import User as UserSchema

from app.db import Base

DocStatus = Enum(
    "uploaded",
    "parsing",
    "translating",
    "action",
    "done",
    "failed",
    name="doc_status",
    create_type=False,
)
DocKind = Enum("notice", "consent", "survey", name="doc_kind", create_type=False)


class User(Base):
    """보호자(F-ON-1·F-ON-3)."""

    __tablename__ = "users"
    __table_args__ = (
        CheckConstraint("origin_country IN ('VN','CN')", name="ck_users_origin_country"),
        CheckConstraint("native_language IN ('vi','zh')", name="ck_users_native_language"),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, server_default=text("gen_random_uuid()")
    )
    kakao_id: Mapped[str] = mapped_column(Text, unique=True, nullable=False)
    display_name: Mapped[str | None] = mapped_column(Text)
    origin_country: Mapped[str | None] = mapped_column(Text)
    native_language: Mapped[str | None] = mapped_column(Text)
    onboarded_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=text("now()")
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=text("now()")
    )

    @property
    def needs_onboarding(self) -> bool:
        return self.origin_country is None or self.native_language is None

    def to_schema(self) -> UserSchema:
        return UserSchema(
            user_id=str(self.id),
            display_name=self.display_name,
            origin_country=self.origin_country,
            native_language=self.native_language,
            created_at=self.created_at,
        )


class Child(Base):
    """자녀(F-ON-4). name·class_no는 미성년 PII — 동의 기반(결정 #7-PII)."""

    __tablename__ = "children"
    __table_args__ = (
        CheckConstraint(
            "grade IN ('elem_1','elem_2','elem_3','elem_4','elem_5','elem_6')",
            name="ck_children_grade",
        ),
        Index("idx_children_user", "user_id"),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, server_default=text("gen_random_uuid()")
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    name: Mapped[str | None] = mapped_column(Text)
    grade: Mapped[str | None] = mapped_column(Text)
    class_no: Mapped[str | None] = mapped_column(Text)
    school_name: Mapped[str | None] = mapped_column(Text)
    color: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=text("now()")
    )

    def to_schema(self) -> ChildSchema:
        return ChildSchema(
            child_id=str(self.id),
            user_id=str(self.user_id),
            name=self.name,
            grade=self.grade,
            class_no=self.class_no,
            school_name=self.school_name,
            color=self.color,
            created_at=self.created_at,
        )


class Document(Base):
    """Chain A 처리 단위(F-DOC). child_id는 §17.4."""

    __tablename__ = "documents"
    __table_args__ = (Index("idx_documents_user_created", "user_id", "created_at"),)

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, server_default=text("gen_random_uuid()")
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    child_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("children.id", ondelete="SET NULL")
    )
    image_ref: Mapped[str] = mapped_column(Text, nullable=False)
    status: Mapped[str] = mapped_column(DocStatus, nullable=False, server_default="uploaded")
    doc_type: Mapped[str | None] = mapped_column(DocKind)
    title: Mapped[str | None] = mapped_column(Text)
    error: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=text("now()")
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=text("now()")
    )

    def to_schema(self) -> DocumentSchema:
        return DocumentSchema(
            document_id=str(self.id),
            user_id=str(self.user_id),
            child_id=str(self.child_id) if self.child_id else None,
            image_ref=self.image_ref,
            status=self.status,
            created_at=self.created_at,
        )
