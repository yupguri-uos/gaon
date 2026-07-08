"""
GAON shared-schema v0.1 — FE·BE·Agent 공통 I/O 계약 (Python 정본)

단일 출처(SSOT) "GAON 개발 계획"의 §7(타입)·§8(에이전트 I/O)을 Pydantic v2로 1:1 반영한다.
v0.6 개정(§17)이 본문(§7 등)보다 우선하므로 다음을 반영했다:
  - UserProfile → User + Child (다자녀 1:N, 결정 #7)
  - Document / Notification / ActionCard.calendar_events 에 child_id(nullable) 부여
  - TeacherComm 입력 child_info = { grade, class_no?, name? }
의도적 제외(미확정): Chain C-chat / F-CHAT-1 / F-POL-1 / conversations
  — §17.8은 '제안(팀 확정 필요)'이므로 스키마에 넣지 않는다.

규칙(CLAUDE.md): 코드에서 필드 임의 추가 금지. 변경은 SSOT → 이 파일 → 각 코드 순.
country/language/grade 는 확장 포인트(DB는 text+CHECK, §16) — MVP는 아래 Literal로 고정.
"""

from __future__ import annotations

from datetime import date, datetime
from typing import Generic, Literal, TypeVar

from pydantic import BaseModel, Field

# ──────────────────────────────────────────────────────────────────────────
# A. 값 타입(Literal) — MVP 고정값
#    안정값(status·doc_type·situation·noti_type)과 확장값(country/language/grade) 구분(§16).
# ──────────────────────────────────────────────────────────────────────────
OriginCountry = Literal["VN", "CN"]  # 확장 포인트(국가 추가 시 여기 + DB CHECK)
NativeLanguage = Literal["vi", "zh"]  # 확장 포인트
ChildGrade = Literal["elem_1", "elem_2", "elem_3"]  # 확장 포인트(초등 저학년)

DocStatus = Literal["uploaded", "parsing", "translating", "action", "done", "failed"]
DocType = Literal["notice", "consent", "survey"]  # 알림장 | 동의서 | 설문·회신
CalendarEventType = Literal["deadline", "event"]
MessageSituation = Literal["absence", "sick_note", "consultation", "custom"]
NotificationType = Literal["deadline_d2", "unreplied_consent", "event_preview"]


# ──────────────────────────────────────────────────────────────────────────
# B. 사용자 / Memory  (SSOT §7 · §17.4: UserProfile → User + Child)
# ──────────────────────────────────────────────────────────────────────────
class User(BaseModel):
    """보호자(F-ON-1·F-ON-3). v0.6에서 UserProfile을 대체."""

    user_id: str
    display_name: str | None = None  # 보호자 이름(설정에서 변경, §17.4)
    origin_country: OriginCountry
    native_language: NativeLanguage
    created_at: datetime


class Child(BaseModel):
    """자녀(F-ON-4). name·class_no 는 미성년 PII → 동의 기반 저장(결정 #7-PII)."""

    child_id: str
    user_id: str  # FK → User
    name: str | None = None  # 미성년 PII, 동의 시에만
    grade: ChildGrade
    class_no: str | None = None  # 반
    school_name: str | None = None  # 학교명(PII 아님 — 동의 불필요, grade와 동일 취급)
    color: str | None = None  # 캘린더 색 구분
    created_at: datetime


# ──────────────────────────────────────────────────────────────────────────
# C. 문서 처리 단위 & 파싱 결과  (Chain A · SSOT §7)
# ──────────────────────────────────────────────────────────────────────────
class Document(BaseModel):
    """Chain A 처리 단위(F-DOC). child_id 는 §17.4."""

    document_id: str
    user_id: str
    child_id: str | None = None  # 어느 자녀 건인지(§17.4)
    image_ref: str  # 업로드 이미지 경로/키
    status: DocStatus = "uploaded"
    created_at: datetime


class DateItem(BaseModel):
    label: str
    date: date


class AmountItem(BaseModel):
    label: str
    value: float


class Checkbox(BaseModel):
    label: str
    bbox: list[float] | None = None  # 픽셀 좌표 — MVP 선택(§10, 우선순위 낮음)


class ExtractedItem(BaseModel):
    """Document Parsing Agent 출력(F-DOC-3). 자녀 귀속은 Document.child_id로(§17.4, 별도 필드 불필요)."""

    doc_type: DocType
    title: str
    dates: list[DateItem] = Field(default_factory=list)
    amounts: list[AmountItem] = Field(default_factory=list)
    supplies: list[str] = Field(default_factory=list)  # 준비물 원문(한국어)
    deadline: date | None = None
    requires_reply: bool = False
    checkboxes: list[Checkbox] = Field(default_factory=list)
    raw_text: str


# ──────────────────────────────────────────────────────────────────────────
# D. 번역 · 행동 카드  (Chain A · SSOT §7)
# ──────────────────────────────────────────────────────────────────────────
class Term(BaseModel):
    term_ko: str
    literal_native: str  # 직역(모국어)
    explanation_native: str  # 문화맥락 해설(모국어)


class TranslatedContent(BaseModel):
    """Cultural & Contextual Translation Agent 출력(F-DOC-5)."""

    summary_native: str  # 전체 요약(모국어)
    terms: list[Term] = Field(default_factory=list)


class Supply(BaseModel):
    name_ko: str
    name_native: str
    explanation_native: str
    spec: str | None = None  # 규격(예: 175mm)
    ecommerce_keyword: str  # 모국어 검색 키워드
    ecommerce_deeplink: str | None = None  # 쿠팡 검색 URL (자동결제 X)


class CalendarEvent(BaseModel):
    title: str
    date: date
    type: CalendarEventType
    child_id: str | None = None  # §17.4


class ActionCard(BaseModel):
    """Lifestyle Action Agent 출력(F-DOC-6/7/8)."""

    supplies: list[Supply] = Field(default_factory=list)
    calendar_events: list[CalendarEvent] = Field(default_factory=list)
    reply_draft_ko: str | None = None  # requires_reply=true 일 때만(F-DOC-8)


# ──────────────────────────────────────────────────────────────────────────
# E. 교사 소통  (Chain B · SSOT §7)
# ──────────────────────────────────────────────────────────────────────────
class TeacherMessage(BaseModel):
    """Teacher Communication Agent 출력(F-TCH). 전송은 사용자 수동(결정 #2)."""

    situation: MessageSituation
    input_native: str
    output_ko: str  # 경어체 한국어
    admin_guide_native: str  # 행정 절차 안내(모국어)


# ──────────────────────────────────────────────────────────────────────────
# F. 능동 알림 / 활동 로그  (SSOT §7)
# ──────────────────────────────────────────────────────────────────────────
class Notification(BaseModel):
    """Proactive(F-PRO). child_id 는 §17.4."""

    notification_id: str
    user_id: str
    child_id: str | None = None
    type: NotificationType
    title_native: str
    body_native: str
    scheduled_at: datetime
    related_document_id: str | None = None


class WeeklyActivity(BaseModel):
    week_start: date
    week_end: date
    processed_count: int = 0
    event_participation_count: int = 0
    missed_count: int = 0


class ActivityLog(BaseModel):
    """Memory 결과 → 월간 리포트(F-LOG)."""

    user_id: str
    processed_count: int = 0
    event_participation_count: int = 0
    missed_count: int = 0
    weekly_activity: list[WeeklyActivity] = Field(default_factory=list)


# ──────────────────────────────────────────────────────────────────────────
# G. 에이전트 4종 I/O 계약  (SSOT §8 · §17.4)
#    출력 타입은 위 모델 재사용. 입력은 아래 *Input 모델.
#    에이전트 '내부' 호출만 AgentResponse[T] 봉투 사용(§11 공통 규약).
# ──────────────────────────────────────────────────────────────────────────
class DocParsingInput(BaseModel):
    """1) Document Parsing: 이미지 → 구조화. out: ExtractedItem"""

    image_ref: str
    user_profile: User  # §8 필드명 유지, 타입은 §17.4로 User
    received_date: date  # 상대 날짜 해석 기준일(=Document.created_at, §8 v0.6.1)


class CulturalTranslationInput(BaseModel):
    """2) Cultural & Contextual Translation: 구조화 → 모국어 해설. out: TranslatedContent"""

    extracted_item: ExtractedItem
    native_language: NativeLanguage
    rag_context: list[str] = Field(default_factory=list)  # F-CORE-2 RAG 근거 주입


class LifestyleActionInput(BaseModel):
    """3) Lifestyle Action: 해설 → 행동 카드. out: ActionCard"""

    extracted_item: ExtractedItem
    translated: TranslatedContent
    child_info: ChildInfo | None = (
        None  # §17.10: 학년 기반 개인화. Document.child_id가 NULL이면 없음
    )
    native_language: NativeLanguage


class ChildInfo(BaseModel):
    """§17.4: child_info = { grade, class_no?, name? }. name 은 동의 시에만."""

    grade: ChildGrade
    class_no: str | None = None
    name: str | None = None


class TeacherCommInput(BaseModel):
    """4) Teacher Communication: 모국어 입력 → 경어체. out: TeacherMessage"""

    input_native: str
    situation: MessageSituation
    native_language: NativeLanguage
    child_info: ChildInfo


# ──────────────────────────────────────────────────────────────────────────
# H. 공통 에이전트 응답 봉투  (SSOT §7 AgentResponse<T>)
# ──────────────────────────────────────────────────────────────────────────
T = TypeVar("T")


class AgentResponse(BaseModel, Generic[T]):
    """에이전트 내부 호출 표준 봉투. 외부 API 응답은 단순 JSON(§11)."""

    agent: str
    status: Literal["ok", "error"]
    data: T | None = None
    error: str | None = None
    latency_ms: int
