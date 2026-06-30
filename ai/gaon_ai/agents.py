"""
GAON AI — 에이전트 (Chain A 핵심: Document Parsing + Cultural Translation)

- 에이전트는 shared-schema(§7)의 *Input을 받아 출력 모델을 돌려준다(§8).
- 내부 호출 표준 봉투 AgentResponse[T](§7·§11) + 지연시간/에러 처리는 base가 일괄 제공.
- 프롬프트는 각 에이전트 옆 상수로 둔다.
- 모델 티어(결정 #4): 추출=FAST, 문화 해설=QUALITY 기본값(생성자에서 변경 가능).
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from time import perf_counter
from typing import Generic, TypeVar
from urllib.parse import quote

from gaon_shared import (
    ActionCard,
    AgentResponse,
    CulturalTranslationInput,
    DocParsingInput,
    ExtractedItem,
    LifestyleActionInput,
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
이주배경 학부모가 '바로 행동'할 수 있는 ActionCard를 만드는 시스템입니다(F-DOC-6/7/8).

규칙:
- supplies: 준비물마다
  {name_ko(한국어 원문), name_native(모국어 이름), explanation_native(무엇이고 왜 필요한지 모국어 설명),
   spec(규격이 명시됐으면, 없으면 null), ecommerce_keyword(쿠팡에서 검색할 키워드)}.
  ecommerce_deeplink는 비워 둔다(시스템이 채운다).
- calendar_events: 문서의 날짜·마감에서 일정을 만든다.
  {title, date(YYYY-MM-DD), type('deadline' 또는 'event')}. child_id는 비워 둔다(시스템이 채운다).
- reply_draft_ko: 회신이 필요하면(requires_reply=true) 학부모가 학교에 보낼 수 있는
  정중한 한국어 회신 초안을 작성한다. 필요 없으면 null.
- 출력 언어: name_native·explanation_native는 모국어(__LANG__), reply_draft_ko는 한국어.
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
        f"[회신 필요] {ext.requires_reply}",
        f"[모국어 요약] {data.translated.summary_native}",
        "",
        f"위를 바탕으로 ActionCard를 만드세요. 준비물 설명은 {lang}, 회신 초안(필요 시)은 한국어로.",
    ]
    return "\n".join(lines)


class LifestyleActionAgent(Agent[LifestyleActionInput, ActionCard]):
    name = "lifestyle_action"

    def __init__(self, llm: LLMClient, *, tier: ModelTier = ModelTier.FAST) -> None:
        self._llm = llm
        # 결정 #4: 준비물·일정 구조화는 고빈도 → 기본 FAST.
        # 단 reply_draft_ko(경어체)는 품질 민감 부분 — 추후 별도 QUALITY 호출로 분리 여지(팀 결정).
        self._tier = tier

    async def _run(self, data: LifestyleActionInput) -> ActionCard:
        lang = LANG_NAME.get(data.native_language, data.native_language)
        sys_prompt = LIFESTYLE_SYSTEM.replace("__LANG__", lang)
        messages = [system(sys_prompt), user_text(_render_lifestyle_user(data))]
        card = await self._llm.generate_structured(
            messages=messages, output_model=ActionCard, tier=self._tier
        )
        # 시스템이 채우는 값: 쿠팡 딥링크(키워드 기반 결정적 조립)
        for supply in card.supplies:
            if not supply.ecommerce_deeplink:
                supply.ecommerce_deeplink = coupang_search_url(supply.ecommerce_keyword)
        # 불변식: 회신이 필요 없으면 초안을 비운다
        if not data.extracted_item.requires_reply:
            card.reply_draft_ko = None
        return card
