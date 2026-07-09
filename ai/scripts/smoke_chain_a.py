"""
Chain A 실 Gemini 스모크 스크립트 — 7/11 시연 리허설용 수동 도구 (CI·pytest 대상 아님).

로컬 알림장 이미지 1장으로 실 Chain A(진짜 Gemini 호출)를 1회 실행하고
결과를 사람이 읽게 출력한다. PR #22(GeminiLLMClient 승격) end-to-end 리허설 +
PR #23(ecommerce_keyword 한국어) 실측이 목적.

실행법 (pydantic-settings는 .env를 프로세스 env로 export하지 않으므로
GOOGLE_API_KEY export 필수):

    set -a; source .env; set +a && python ai/scripts/smoke_chain_a.py --image <경로>

옵션: --lang(기본 vi) --country(기본 VN) --grade(예: elem_1 — 주면 ChildInfo 구성)
판정: 체인 성공=exit 0, ChainError/예외=exit 1(스택 출력).
"""

from __future__ import annotations

import argparse
import asyncio
import re
import sys
import traceback
from datetime import datetime, timezone
from pathlib import Path
from typing import get_args

from gaon_shared import ChildGrade, ChildInfo, Document, NativeLanguage, OriginCountry, User

from gaon_ai.chain_a import ChainAResult, run_chain_a_core
from gaon_ai.llm_gemini import GeminiLLMClient
from gaon_ai.testing import FakeRetriever

HANGUL = re.compile(r"[가-힣]")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Chain A 실 Gemini 스모크(수동, 시연 리허설용)")
    parser.add_argument("--image", required=True, help="로컬 알림장 이미지 경로(jpg/png/webp)")
    parser.add_argument(
        "--lang", default="vi", choices=get_args(NativeLanguage), help="모국어(기본 vi)"
    )
    parser.add_argument(
        "--country", default="VN", choices=get_args(OriginCountry), help="출신국(기본 VN=베트남)"
    )
    parser.add_argument(
        "--grade",
        default=None,
        choices=get_args(ChildGrade),
        help="자녀 학년(선택 — 주면 ChildInfo 구성, 예: elem_1)",
    )
    args = parser.parse_args()
    if not Path(args.image).is_file():
        parser.error(f"이미지 파일이 없습니다: {args.image}")
    return args


def print_result(result: ChainAResult) -> bool:
    """결과를 사람용으로 출력하고, ecommerce_keyword 전부 한국어면 True."""
    extracted = result.extracted
    print("\n== ExtractedItem (DocParsing) ==")
    print(f"  제목:      {extracted.title}")
    print(f"  문서 유형:  {extracted.doc_type}")
    print(f"  준비물:    {extracted.supplies or '(없음)'}")
    print(f"  날짜:      {[(d.label, str(d.date)) for d in extracted.dates] or '(없음)'}")
    print(f"  마감일:    {extracted.deadline or '(없음)'}")
    print(f"  회신 필요:  {extracted.requires_reply}")

    translated = result.translated
    print("\n== TranslatedContent (CulturalTranslation) ==")
    print(f"  요약(모국어, 앞 200자): {translated.summary_native[:200]}")
    print(f"  용어 해설 개수: {len(translated.terms)}")

    card = result.action_card
    print("\n== ActionCard (LifestyleAction) ==")
    all_keywords_korean = True
    if not card.supplies:
        print("  준비물 카드: (없음)")
    for supply in card.supplies:
        keyword = supply.ecommerce_keyword
        if keyword is None:
            # §17.11 2단-a: 비구매 항목(배부물·오기 추정 등) — 키워드·딥링크 없음이 정상
            print(f"  - {supply.name_ko} / 키워드: (없음 — 비구매) / 딥링크: (없음)")
            continue
        has_hangul = bool(HANGUL.search(keyword))
        all_keywords_korean = all_keywords_korean and has_hangul
        print(
            f"  - {supply.name_ko} / 키워드: {keyword}"
            f" / 한글여부: {'O' if has_hangul else 'X'}"
            f" / 딥링크: {supply.ecommerce_deeplink or '(없음)'}"
        )
    print(
        f"  캘린더 이벤트: {[(e.title, str(e.date), e.type) for e in card.calendar_events] or '(없음)'}"
    )
    print(f"  회신 초안(reply_draft_ko): {'있음' if card.reply_draft_ko else '없음'}")
    return all_keywords_korean


def print_metrics(llm: GeminiLLMClient) -> None:
    m = llm.metrics
    print("\n== LLM metrics ==")
    print(f"  호출 수:        {m.call_count}")
    print(f"  총 입력 토큰:    {m.total_input_tokens}")
    print(f"  총 출력 토큰:    {m.total_output_tokens}")
    print(f"  총 지연(ms):    {m.total_latency_ms}")
    print(f"  가용성 재시도:   {m.availability_retries}")
    print(f"  검증 재시도:     {m.validation_retries}")


async def main() -> int:
    args = parse_args()
    now = datetime.now(timezone.utc)
    child_info = ChildInfo(grade=args.grade) if args.grade else None

    user = User(
        user_id="smoke-user",
        display_name="스모크 테스트",
        origin_country=args.country,
        native_language=args.lang,
        created_at=now,
    )
    document = Document(
        document_id="smoke-doc",
        user_id=user.user_id,
        child_id="smoke-child" if child_info else None,
        image_ref=args.image,  # GeminiLLMClient 기본 로더가 로컬 경로를 읽는다(주입 불필요)
        created_at=now,
    )

    llm = GeminiLLMClient()
    print(f"Chain A 스모크 시작 — image={args.image} lang={args.lang} country={args.country}")
    print("RAG=fake(코퍼스 미적재) — rag_context는 fixture 문자열이며 실 검색 결과가 아님")
    print("상태 전이:")

    try:
        result = await run_chain_a_core(
            document,
            user,
            llm=llm,
            retriever=FakeRetriever(),
            child_info=child_info,
            on_status=lambda s: print(f"  → {s}"),
        )
    except Exception:
        traceback.print_exc()
        print_metrics(llm)
        print("\n❌ Chain A 실패")
        return 1

    all_keywords_korean = print_result(result)
    print_metrics(llm)
    if not all_keywords_korean:
        # 비종료 경고 — S12 12-4(키워드 한국어 강조) 판단용 신호
        print("\n⚠️  ecommerce_keyword에 한글이 없는 항목이 있습니다 (PR #23 언어 계약 확인 필요)")
    print("\n✅ Chain A 성공")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
