"""shared-schema 계약 고정 — 타입 존재/기본값/필수/Literal 가드/직렬화 라운드트립.

SSOT §7·§8·§17.4 대응. 폐기된 UserProfile(§17.4에서 User+Child로 분리)이 남지 않았는지 포함.
실제 동작을 그대로 pytest로 고정한다 — 스키마 계약은 코드가 아니라 SSOT가 정한다.
"""

from datetime import date, datetime

import pytest
from pydantic import ValidationError

import gaon_shared
from gaon_shared import (
    AgentResponse,
    DateItem,
    Document,
    DocParsingInput,
    ExtractedItem,
    User,
)


def test_user_child_present_userprofile_removed():
    # 1) User·Child 존재, 폐기된 UserProfile 없음(§17.4)
    assert hasattr(gaon_shared, "User")
    assert hasattr(gaon_shared, "Child")
    assert not hasattr(gaon_shared, "UserProfile")


def test_document_has_child_id_and_default_status():
    # 2) Document는 child_id를 갖고 status 기본값은 "uploaded"
    document = Document(
        document_id="doc-1",
        user_id="u1",
        image_ref="minio://bucket/doc-1.jpg",
        created_at=datetime(2026, 6, 30, 9, 0),
    )
    assert "child_id" in Document.model_fields
    assert document.child_id is None
    assert document.status == "uploaded"


def test_docparsing_input_requires_received_date():
    # 3) DocParsingInput.received_date 필수 — 빠지면 ValidationError
    user = User(
        user_id="u1",
        origin_country="VN",
        native_language="vi",
        created_at=datetime(2026, 6, 30, 9, 0),
    )
    with pytest.raises(ValidationError):
        DocParsingInput(image_ref="minio://bucket/doc-1.jpg", user_profile=user)


def test_user_origin_country_literal_guard():
    # 4) Literal 가드: origin_country="KR"는 ValidationError
    with pytest.raises(ValidationError):
        User(
            user_id="u1",
            origin_country="KR",
            native_language="vi",
            created_at=datetime(2026, 6, 30, 9, 0),
        )


def test_agent_response_roundtrip_preserves_nested_data():
    # 5) AgentResponse[ExtractedItem] JSON 라운드트립 시 중첩 data(dates/supplies) 보존
    item = ExtractedItem(
        doc_type="notice",
        title="현장학습 안내",
        dates=[DateItem(label="현장학습일", date=date(2026, 7, 10))],
        supplies=["도시락", "물통", "돗자리"],
        deadline=date(2026, 7, 5),
        requires_reply=True,
        raw_text="(이미지 원문)",
    )
    envelope = AgentResponse[ExtractedItem](
        agent="document_parsing", status="ok", data=item, latency_ms=12
    )
    restored = AgentResponse[ExtractedItem].model_validate_json(envelope.model_dump_json())
    assert isinstance(restored.data, ExtractedItem)
    assert restored.data.supplies == ["도시락", "물통", "돗자리"]
    assert isinstance(restored.data.dates[0], DateItem)
    assert restored.data.dates[0].date == date(2026, 7, 10)
    assert restored.data.deadline == date(2026, 7, 5)
