"""문서 처리 = Chain A (F-DOC-1~8, SSOT §11). 호출하는 엔드포인트가 곧 체인 선택 — 별도
/orchestrate 없음. 업로드 즉시 응답하고 BackgroundTasks로 Chain A를 실행한다(§12)."""

from __future__ import annotations

import uuid

from fastapi import APIRouter, BackgroundTasks, Depends, File, HTTPException, UploadFile, status
from gaon_shared import ActionCard as ActionCardSchema
from gaon_shared import AmountItem, CalendarEvent, Checkbox, DateItem
from gaon_shared import Document as DocumentSchema
from gaon_shared import ExtractedItem as ExtractedItemSchema
from gaon_shared import Supply, Term
from gaon_shared import TranslatedContent as TranslatedContentSchema
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.chain_deps import get_llm_client, get_retriever
from app.db import SessionLocal, get_db
from app.models import Document, DocumentResultRow, ExtractedItemRow, User
from app.security import get_current_user
from app.storage import object_key, upload_image
from gaon_ai.chain_a import ChainAResult, run_chain_a_core

router = APIRouter(tags=["documents"])


class DocumentUploadResponse(BaseModel):
    document_id: str
    status: str


class DocumentResultResponse(BaseModel):
    document: DocumentSchema
    extracted: ExtractedItemSchema | None
    translated: TranslatedContentSchema | None
    action_card: ActionCardSchema | None


def _get_owned_document(db: Session, document_id: uuid.UUID, current_user: User) -> Document:
    document = db.get(Document, document_id)
    if document is None or document.user_id != current_user.id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="문서를 찾을 수 없습니다")
    return document


def _extracted_schema(document: Document, row: ExtractedItemRow) -> ExtractedItemSchema:
    return ExtractedItemSchema(
        doc_type=document.doc_type,
        title=document.title or "",
        dates=[DateItem(**d) for d in row.dates],
        amounts=[AmountItem(**a) for a in row.amounts],
        supplies=row.supplies,
        deadline=row.deadline,
        requires_reply=row.requires_reply,
        checkboxes=[Checkbox(**c) for c in row.checkboxes],
        raw_text=row.raw_text or "",
    )


def _translated_schema(row: DocumentResultRow) -> TranslatedContentSchema:
    return TranslatedContentSchema(
        summary_native=row.summary_native or "",
        terms=[Term(**t) for t in row.terms],
    )


def _action_card_schema(row: DocumentResultRow) -> ActionCardSchema:
    return ActionCardSchema(
        supplies=[Supply(**s) for s in row.action_supplies],
        calendar_events=[CalendarEvent(**e) for e in row.calendar_events],
        reply_draft_ko=row.reply_draft_ko,
    )


def _persist_chain_a_result(db: Session, document: Document, result: ChainAResult) -> None:
    document.doc_type = result.extracted.doc_type
    document.title = result.extracted.title

    db.add(
        ExtractedItemRow(
            document_id=document.id,
            deadline=result.extracted.deadline,
            requires_reply=result.extracted.requires_reply,
            dates=[d.model_dump(mode="json") for d in result.extracted.dates],
            amounts=[a.model_dump(mode="json") for a in result.extracted.amounts],
            supplies=result.extracted.supplies,
            checkboxes=[c.model_dump(mode="json") for c in result.extracted.checkboxes],
            raw_text=result.extracted.raw_text,
        )
    )
    db.add(
        DocumentResultRow(
            document_id=document.id,
            summary_native=result.translated.summary_native,
            terms=[t.model_dump(mode="json") for t in result.translated.terms],
            action_supplies=[s.model_dump(mode="json") for s in result.action_card.supplies],
            calendar_events=[e.model_dump(mode="json") for e in result.action_card.calendar_events],
            reply_draft_ko=result.action_card.reply_draft_ko,
        )
    )


async def _run_chain_a_and_persist(document_id: uuid.UUID) -> None:
    """BackgroundTasks 진입점. 요청 세션이 이미 닫혔으므로 새 세션을 연다."""
    db = SessionLocal()
    try:
        document = db.get(Document, document_id)
        if document is None:
            return
        user = db.get(User, document.user_id)
        if user is None:
            document.status = "failed"
            document.error = "사용자를 찾을 수 없습니다"
            db.commit()
            return

        def on_status(s: str) -> None:
            # 체인이 emit하는 "done"은 여기서 무시한다 — persist 전에 커밋되면 "status=done인데
            # 결과 행이 없는" 폴링 레이스가 생긴다(§18.4). done은 아래에서 persist 성공 후 세팅한다.
            if s == "done":
                return
            document.status = s
            db.commit()

        try:
            result = await run_chain_a_core(
                document.to_schema(),
                user.to_schema(),
                llm=get_llm_client(),
                retriever=get_retriever(),
                on_status=on_status,
            )
            _persist_chain_a_result(db, document, result)
            document.status = "done"
            db.commit()
        except Exception as exc:
            # ChainError(에이전트 실패)뿐 아니라 persist 단계의 실패(제약 위반 등)도 여기로 온다.
            # done과 persist를 한 커밋으로 묶어야 "status=done인데 결과 행이 없는" 폴링 레이스가
            # 안 생기고(§18.4), try로 persist까지 감싸야 그 실패도 failed로 남는다.
            db.rollback()
            document.status = "failed"
            document.error = str(exc)
            db.commit()
    finally:
        db.close()


@router.post("/documents", response_model=DocumentUploadResponse)
async def upload_document(
    background_tasks: BackgroundTasks,
    image: UploadFile = File(...),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> DocumentUploadResponse:
    if current_user.needs_onboarding:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="온보딩이 필요합니다")
    if not (image.content_type or "").startswith("image/"):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail="이미지 파일만 업로드할 수 있습니다"
        )

    data = await image.read()
    key = object_key(str(current_user.id), image.filename or "upload")
    upload_image(key, data, image.content_type)

    document = Document(user_id=current_user.id, image_ref=key, status="uploaded")
    db.add(document)
    db.commit()
    db.refresh(document)

    background_tasks.add_task(_run_chain_a_and_persist, document.id)

    return DocumentUploadResponse(document_id=str(document.id), status=document.status)


@router.get("/documents/{document_id}/status")
def get_document_status(
    document_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    document = _get_owned_document(db, document_id, current_user)
    # Document.status 자체가 단계명(parsing/translating/action/done/failed)이라 step과 동일하게 노출한다(§11 F-DOC-4).
    return {"status": document.status, "step": document.status}


@router.get("/documents/{document_id}/result", response_model=DocumentResultResponse)
def get_document_result(
    document_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> DocumentResultResponse:
    document = _get_owned_document(db, document_id, current_user)
    extracted_row = db.get(ExtractedItemRow, document_id)
    result_row = db.get(DocumentResultRow, document_id)

    return DocumentResultResponse(
        document=document.to_schema(),
        extracted=_extracted_schema(document, extracted_row) if extracted_row else None,
        translated=_translated_schema(result_row) if result_row else None,
        action_card=_action_card_schema(result_row) if result_row else None,
    )


@router.get("/documents", response_model=list[DocumentSchema])
def list_documents(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> list[DocumentSchema]:
    rows = (
        db.execute(
            select(Document)
            .where(Document.user_id == current_user.id)
            .order_by(Document.created_at.desc())
        )
        .scalars()
        .all()
    )
    return [r.to_schema() for r in rows]
