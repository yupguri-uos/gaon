"""
GAON AI — 에이전트 (Chain A 핵심: Document Parsing + Cultural Translation)

- 에이전트는 shared-schema(§7)의 *Input을 받아 출력 모델을 돌려준다(§8).
- 내부 호출 표준 봉투 AgentResponse[T](§7·§11) + 지연시간/에러 처리는 base가 일괄 제공.
- 프롬프트는 각 에이전트 옆 상수로 둔다.
- 모델 티어(결정 #4): 추출=FAST, 문화 해설=QUALITY 기본값(생성자에서 변경 가능).
"""

from __future__ import annotations

import asyncio
from abc import ABC, abstractmethod
from time import perf_counter
from typing import Generic, TypeVar
from urllib.parse import quote

from pydantic import BaseModel

from gaon_shared import (
    ActionCard,
    AgentResponse,
    CulturalTranslationInput,
    DocParsingInput,
    ExtractedItem,
    LifestyleActionInput,
    TeacherCommInput,
    TeacherMessage,
    TranslatedContent,
)

from gaon_ai.llm import LLMClient, ModelTier, system, user_image_and_text, user_text

InT = TypeVar("InT")
OutT = TypeVar("OutT")

# 모국어 코드 → 사람이 읽는 이름(프롬프트 가독성용)
LANG_NAME = {"vi": "베트남어", "zh": "중국어"}


class Agent(ABC, Generic[InT, OutT]):
    """모든 에이전트 공통 골격: run()이 타이밍·에러·봉투(§11)를 표준화한다."""

    name: str

    @abstractmethod
    async def _run(self, data: InT) -> OutT: ...

    async def run(self, data: InT) -> AgentResponse[OutT]:
        start = perf_counter()
        try:
            out = await self._run(data)
            latency = int((perf_counter() - start) * 1000)
            # 제네릭은 런타임 미파라미터화로 생성(정적 타입은 반환 시그니처가 보장)
            return AgentResponse(agent=self.name, status="ok", data=out, latency_ms=latency)
        except Exception as exc:  # LLM/검증 실패 포함 — 체인이 일관되게 처리하도록 봉투로 감싼다
            latency = int((perf_counter() - start) * 1000)
            return AgentResponse(
                agent=self.name, status="error", data=None, error=str(exc), latency_ms=latency
            )


# ── 1) Document Parsing (이미지 → 구조화) ───────────────────────────────────
PARSING_SYSTEM = """당신은 한국 초등학교의 가정통신문·알림장 이미지에서 구조화 정보를 추출하는 시스템입니다.
멀티모달로 이미지를 직접 읽고(별도 OCR 없음), 주어진 스키마에 맞는 결과만 출력합니다.

규칙:
- doc_type: 일반 안내는 'notice', 회신/동의가 필요한 동의서는 'consent', 설문은 'survey'.
- supplies: 준비물을 이미지의 한국어 원문 그대로. 추측·추가 금지.
- dates: 문서의 날짜를 [{label, date}] 형태로(date는 YYYY-MM-DD).
  '다음 주' 같은 상대 표현은 아래 제공되는 기준일(문서 수신일)로 계산해 절대 날짜로 변환한다.
- amounts: 금액을 [{label, value}]로(value는 원 단위 숫자).
- deadline: 제출/회신 마감일이 있으면 그 날짜(YYYY-MM-DD), 없으면 null.
- requires_reply: 회신·동의·제출이 필요하면 true.
- checkboxes: 선택/체크 항목 라벨. 좌표(bbox)는 생략 가능.
- raw_text: 이미지의 전체 텍스트(원문).
- 환각 금지: 이미지에 없는 정보를 만들지 말 것. 불확실하면 비워둔다."""


class DocumentParsingAgent(Agent[DocParsingInput, ExtractedItem]):
    name = "document_parsing"

    def __init__(self, llm: LLMClient, *, tier: ModelTier = ModelTier.FAST) -> None:
        self._llm = llm
        self._tier = tier  # 결정 #4: 추출=고빈도 → 기본 FAST

    async def _run(self, data: DocParsingInput) -> ExtractedItem:
        user_msg = (
            f"문서 수신일(기준일)은 {data.received_date.isoformat()}입니다. "
            "'다음 주' 같은 상대 날짜 표현은 이 기준일로 계산해 절대 날짜(YYYY-MM-DD)로 변환하세요.\n"
            "이 학교 문서 이미지에서 정보를 추출해 스키마에 맞게 구조화하세요."
        )
        messages = [system(PARSING_SYSTEM), user_image_and_text(data.image_ref, user_msg)]
        return await self._llm.generate_structured(
            messages=messages, output_model=ExtractedItem, tier=self._tier
        )


# ── 2) Cultural & Contextual Translation (구조화 → 모국어 해설) ───────────────
TRANSLATION_SYSTEM = """당신은 한국 학교 문서의 구조화 결과를, 한국어가 익숙하지 않은 이주배경 학부모가
이해하도록 '문화 맥락까지' 풀어 설명하는 시스템입니다. 단순 번역을 넘어 무엇을·언제까지·무엇을
해야 하는지 행동 관점으로 해설합니다.

규칙:
- 모든 자연어 출력은 대상 모국어(__LANG__)로 작성한다.
- summary_native: 문서 핵심을 모국어로 간결 요약(무엇을·언제까지·무엇을 해야 하는지).
- terms: 한국 학교 특유의 용어·관행을 골라 각 항목을
  {term_ko(한국어 원문), literal_native(직역), explanation_native(왜 중요한지·무엇을 해야 하는지 해설)}로.
- rag_context(교육부 가이드라인·학교 관행 근거)가 주어지면 해설은 그 근거를 우선 사용한다.
  근거에 없는 내용은 일반 상식으로 보완하되 단정하지 않는다.
- 환각·과장 금지. 원문에 없는 마감/금액을 지어내지 않는다."""


def _render_translation_user(data: CulturalTranslationInput) -> str:
    ext = data.extracted_item
    lang = LANG_NAME.get(data.native_language, data.native_language)
    lines = [
        f"[문서 제목] {ext.title}",
        f"[유형] {ext.doc_type}",
        f"[준비물] {', '.join(ext.supplies) if ext.supplies else '없음'}",
        f"[마감] {ext.deadline.isoformat() if ext.deadline else '없음'}",
        f"[회신 필요] {ext.requires_reply}",
        f"[원문] {ext.raw_text}",
        "",
        "[RAG 근거]",
    ]
    lines += [f"- {c}" for c in data.rag_context] or ["- (없음)"]
    lines += ["", f"위 내용을 학부모의 모국어({lang})로 요약·용어 해설하세요."]
    return "\n".join(lines)


class CulturalTranslationAgent(Agent[CulturalTranslationInput, TranslatedContent]):
    name = "cultural_translation"

    def __init__(self, llm: LLMClient, *, tier: ModelTier = ModelTier.QUALITY) -> None:
        self._llm = llm
        self._tier = tier  # 결정 #4: 문화 해설=품질 민감 → 기본 QUALITY

    async def _run(self, data: CulturalTranslationInput) -> TranslatedContent:
        lang = LANG_NAME.get(data.native_language, data.native_language)
        sys_prompt = TRANSLATION_SYSTEM.replace("__LANG__", lang)
        messages = [system(sys_prompt), user_text(_render_translation_user(data))]
        return await self._llm.generate_structured(
            messages=messages, output_model=TranslatedContent, tier=self._tier
        )


# ── 3) Lifestyle Action (해설 → 행동 카드) ───────────────────────────────────
# 쿠팡 검색 URL은 LLM이 아니라 코드가 키워드로 조립한다(자동결제 X, F-DOC-8).
def coupang_search_url(keyword: str) -> str:
    return f"https://www.coupang.com/np/search?q={quote(keyword)}"


LIFESTYLE_SYSTEM = """당신은 한국 학교 문서의 구조화 결과와 모국어 해설을 받아,
이주배경 학부모가 '바로 행동'할 수 있는 ActionCard를 만드는 시스템입니다(F-DOC-6/7).

규칙:
- supplies: 준비물마다
  {name_ko(한국어 원문), name_native(모국어 이름), explanation_native(무엇이고 왜 필요한지 모국어 설명),
   spec(규격이 명시됐으면, 없으면 null), ecommerce_keyword(쿠팡에서 검색할 키워드)}.
  ecommerce_deeplink는 비워 둔다(시스템이 채운다).
- calendar_events: 문서의 날짜·마감에서 일정을 만든다.
  {title, date(YYYY-MM-DD), type('deadline' 또는 'event')}. child_id는 비워 둔다(시스템이 채운다).
- reply_draft_ko: null로 둔다(회신 초안은 품질 민감 단계라 별도로 생성한다).
- 출력 언어: name_native·explanation_native는 모국어(__LANG__).
- 환각 금지: 원문에 없는 준비물·일정·금액을 지어내지 않는다."""


def _render_lifestyle_user(data: LifestyleActionInput) -> str:
    ext = data.extracted_item
    lang = LANG_NAME.get(data.native_language, data.native_language)
    dates = "; ".join(f"{d.label}={d.date.isoformat()}" for d in ext.dates) or "없음"
    lines = [
        f"[제목] {ext.title}",
        f"[유형] {ext.doc_type}",
        f"[준비물] {', '.join(ext.supplies) if ext.supplies else '없음'}",
        f"[날짜] {dates}",
        f"[마감] {ext.deadline.isoformat() if ext.deadline else '없음'}",
        f"[모국어 요약] {data.translated.summary_native}",
        "",
        f"위를 바탕으로 supplies·calendar_events를 만드세요. 준비물 설명은 {lang}로.",
    ]
    return "\n".join(lines)


# 회신 초안 전용(경어체) — AI 내부 모델. shared-schema(FE·BE I/O) 아님.
class ReplyDraft(BaseModel):
    reply_draft_ko: str


REPLY_SYSTEM = """당신은 한국 학교 문서에 대한 학부모의 회신을, 학교에 그대로 보낼 수 있는
정중한 한국어(경어체)로 작성합니다.

규칙:
- 반드시 한국어 경어체로, 완결된 회신문 한 편을 쓴다(학부모가 복사해 바로 전송 가능).
- 문서가 요구하는 핵심 응답(동의/확인/일정 등)을 명확히 담되, 원문에 없는 사실은 지어내지 않는다."""


def _render_reply_user(ext: ExtractedItem) -> str:
    return "\n".join(
        [
            f"[문서 제목] {ext.title}",
            f"[유형] {ext.doc_type}",
            f"[원문] {ext.raw_text}",
            "",
            "위 문서에 대한 정중한 한국어 회신 초안을 작성하세요.",
        ]
    )


class LifestyleActionAgent(Agent[LifestyleActionInput, ActionCard]):
    name = "lifestyle_action"

    def __init__(
        self,
        llm: LLMClient,
        *,
        structuring_tier: ModelTier = ModelTier.FAST,  # 준비물·일정 = 고빈도 → 저비용
        reply_tier: ModelTier = ModelTier.QUALITY,  # 경어체 회신 = 품질 민감(결정 #4)
    ) -> None:
        self._llm = llm
        self._structuring_tier = structuring_tier
        self._reply_tier = reply_tier

    async def _run(self, data: LifestyleActionInput) -> ActionCard:
        lang = LANG_NAME.get(data.native_language, data.native_language)
        # 호출 1: 준비물·일정 구조화(FAST)
        structuring = self._llm.generate_structured(
            messages=[
                system(LIFESTYLE_SYSTEM.replace("__LANG__", lang)),
                user_text(_render_lifestyle_user(data)),
            ],
            output_model=ActionCard,
            tier=self._structuring_tier,
        )

        if data.extracted_item.requires_reply:
            # 호출 2: 경어체 회신 초안(QUALITY) — 회신 필요 시에만. 두 호출은 독립이라 동시 실행.
            reply = self._llm.generate_structured(
                messages=[system(REPLY_SYSTEM), user_text(_render_reply_user(data.extracted_item))],
                output_model=ReplyDraft,
                tier=self._reply_tier,
            )
            card, reply_out = await asyncio.gather(structuring, reply)
            card.reply_draft_ko = reply_out.reply_draft_ko
        else:
            card = await structuring
            card.reply_draft_ko = None  # 불변식: 회신 불필요 시 비움

        # 시스템이 채우는 값: 쿠팡 딥링크(키워드 기반 결정적 조립)
        for supply in card.supplies:
            if not supply.ecommerce_deeplink:
                supply.ecommerce_deeplink = coupang_search_url(supply.ecommerce_keyword)
        return card


# ── 4) Teacher Communication (모국어 입력 → 경어체 + 행정 안내) ──────────────
# Chain B(§9): 단독 에이전트, RAG 없음. 전송은 하지 않고 생성까지만(결정 #2, F-TCH-3).
# out=TeacherMessage이나 situation·input_native는 입력 에코라 LLM에 재생성시키지 않고
# 코드가 입력에서 채운다(ReplyDraft·딥링크와 같은 '결정적 필드는 코드' 불변식).
# LLM은 아래 TeacherDraft(output_ko·admin_guide_native)만 생성한다.
TEACHER_COMM_SYSTEM = """당신은 한국어가 익숙하지 않은 이주배경 학부모가 자녀의 담임 교사에게 보낼 메시지를,
학부모의 모국어 입력을 바탕으로 (1) 학교에 그대로 보낼 수 있는 정중한 한국어(경어체) 메시지와
(2) 관련 행정 절차의 모국어 안내로 만드는 시스템입니다. 전송은 하지 않습니다 — 생성까지만 합니다.

규칙:
- output_ko: 학부모가 복사해 바로 보낼 수 있는 완결된 경어체 한국어 메시지 한 편.
  · 상황별 격식·내용: 'absence'=결석 사유·기간 통지, 'sick_note'=병결/진단서 관련,
    'consultation'=상담 요청, 'custom'=학부모가 쓴 내용을 정중하게 다듬기.
  · 자녀 정보(학년·반·이름이 주어지면)를 자연스럽게 반영하되, 주어지지 않은 정보는 지어내지 않는다.
  · 학부모 입력에 담긴 사실(날짜·사유 등)만 사용한다. 원문에 없는 사실을 추가하지 않는다.
- admin_guide_native: 이 상황에서 학부모가 알아야 할 한국 학교의 행정 절차를 모국어(__LANG__)로 간결히 안내.
  · 예: 결석 시 결석계·증빙 제출 방법과 기한, 병결 시 진단서·영수증 보관, 상담 신청 방법 등(F-TCH-4).
  · 실제 한국 학교 관행에 근거하고, 불확실하면 단정하지 않는다.
- 출력 언어: output_ko는 한국어 경어체, admin_guide_native는 모국어(__LANG__).
- 환각 금지: 입력에 없는 사실·수치를 만들지 않는다."""


# ReplyDraft와 같은 AI 내부 전용 모델 — shared-schema(FE·BE I/O) 아님.
class TeacherDraft(BaseModel):
    output_ko: str  # 경어체 한국어 메시지
    admin_guide_native: str  # 행정 절차 안내(모국어)


def _render_teacher_user(data: TeacherCommInput) -> str:
    lang = LANG_NAME.get(data.native_language, data.native_language)
    ci = data.child_info
    child_desc = str(ci.grade)
    if ci.class_no:
        child_desc += f" {ci.class_no}반"
    if ci.name:
        child_desc += f" · 이름 {ci.name}"
    lines = [
        f"[상황] {data.situation}",
        f"[자녀 정보] {child_desc}",
        f"[학부모 모국어 입력] {data.input_native}",
        "",
        f"위 내용으로 (1) 경어체 한국어 메시지(output_ko)와 "
        f"(2) {lang} 행정 절차 안내(admin_guide_native)를 생성하세요.",
    ]
    return "\n".join(lines)


class TeacherCommunicationAgent(Agent[TeacherCommInput, TeacherMessage]):
    name = "teacher_communication"

    def __init__(self, llm: LLMClient, *, tier: ModelTier = ModelTier.QUALITY) -> None:
        self._llm = llm
        self._tier = tier  # 결정 #4: 경어체 = 품질 민감 → 기본 QUALITY

    async def _run(self, data: TeacherCommInput) -> TeacherMessage:
        lang = LANG_NAME.get(data.native_language, data.native_language)
        draft = await self._llm.generate_structured(
            messages=[
                system(TEACHER_COMM_SYSTEM.replace("__LANG__", lang)),
                user_text(_render_teacher_user(data)),
            ],
            output_model=TeacherDraft,
            tier=self._tier,
        )
        # situation·input_native은 입력 에코 → 코드가 채운다(원문 보존·상황 고정, LLM 재생성 금지)
        return TeacherMessage(
            situation=data.situation,
            input_native=data.input_native,
            output_ko=draft.output_ko,
            admin_guide_native=draft.admin_guide_native,
        )
