"""판정 규칙(조사 페이지 §11 v2, 2026-07-06 사전등록) 회귀 테스트 — 순수 함수, 실 API 없음.

경로별 고정 케이스: ③ 조합 4경로(i~iv) / 편측 수렴 양방향 / Gemini 내부 타이브레이커
(차 ≥3 승자·차 ≤2 → 3 Flash) / 결정승 경계(차 2=근소·차 3=결정승, §11 개정 2026-07-06) /
게이트 티어 귀속(존대 오류는 FAST 무영향) / handwritten 0건 미발동 / 3-way 집계 /
전 후보 탈락=판정 불가 / 수동 입력 부재=pending.
실행: pytest ai/pilots/llm_sku/tests
"""

from eval.scorer import DocScore, SetScore, SupplyScore
from eval.verdict import FastCandidate, QualityCandidate, decide

# §11 v2 후보 SKU
G_FLASH = "gemini-3-flash-preview"
G35_FLASH = "gemini-3.5-flash"
HAIKU = "claude-haiku-4-5"
G_PRO = "gemini-3.1-pro-preview"
SONNET = "claude-sonnet-4-6"


def _doc(doc_id: str, critical: int = 0, halluc: int = 0) -> DocScore:
    return DocScore(
        doc_id=doc_id,
        doc_type_match=True,
        deadline_match=True,
        requires_reply_match=True,
        dates=SetScore(),
        amounts=SetScore(),
        supplies=SupplyScore(),
        critical_misses=critical,
        hallucination_count=halluc,
    )


def _stats(vendor, criticals, hallucs=None, tags=None, failed=()):
    from eval.verdict import VendorStats

    hallucs = hallucs or [0] * len(criticals)
    docs = [_doc(f"{i:03d}", c, h) for i, (c, h) in enumerate(zip(criticals, hallucs), start=1)]
    tags_by_doc = {d.doc_id: list((tags or {}).get(d.doc_id, [])) for d in docs}
    return VendorStats(
        vendor=vendor, doc_scores=docs, tags_by_doc=tags_by_doc, failed_docs=list(failed)
    )


def _fast(sku, vendor, criticals, hallucs=None, tags=None, run=""):
    return FastCandidate(
        sku=sku, vendor=vendor, stats=_stats(vendor, criticals, hallucs, tags), run=run
    )


def _fast3(g_flash=0, g35=0, haiku=0):
    """표준 3-way FAST 후보(크리티컬 총합만 다르게)."""
    return [
        _fast(G_FLASH, "gemini", [g_flash], run="results/run1"),
        _fast(G35_FLASH, "gemini", [g35], run="results/run2"),
        _fast(HAIKU, "claude", [haiku], run="results/run1"),
    ]


def _quality(g_pol=0, c_pol=0):
    return [
        QualityCandidate(sku=G_PRO, vendor="gemini", politeness_violations=g_pol),
        QualityCandidate(sku=SONNET, vendor="claude", politeness_violations=c_pol),
    ]


# run_pilot이 생성하는 ab_key.json과 같은 형태 — A/B 배정을 문항별로 섞어 매핑 로직 검증
AB_KEY = {
    "1": {"A": "gemini", "B": "claude"},
    "2": {"A": "claude", "B": "gemini"},
    "3": {"A": "gemini", "B": "claude"},
    "4": {"A": "claude", "B": "gemini"},
    "5": {"A": "gemini", "B": "claude"},
}


def _ab(*winners_by_item):
    """문항 1..N의 승자(벤더명 또는 'tie')를 평가자 시점의 A/B 라벨 기록으로 변환."""
    results = []
    for i, w in enumerate(winners_by_item, start=1):
        if w == "tie":
            results.append({"item_id": str(i), "winner": "tie"})
        else:
            letter = "A" if AB_KEY[str(i)]["A"] == w else "B"
            results.append({"item_id": str(i), "winner": letter})
    return results


AB_CLAUDE_UNANIMOUS = ("claude", "claude", "claude", "tie", "tie")  # 3승 0패 2무 = 만장일치급
AB_GEMINI_UNANIMOUS = ("gemini", "gemini", "gemini", "tie", "tie")
AB_NARROW = ("claude", "claude", "tie", "tie", "tie")  # 2승 0패 3무 = 승 3개 미만 → 근소
AB_ALL_TIES = ("tie",) * 5


# ── ③ 조합 4경로 ────────────────────────────────────────────────────────────
def test_path_i_both_decisive_same_vendor_single():
    # FAST: gemini 최고 3 vs claude 0 → 결정승 claude / QUALITY: claude 만장일치급 → (i) 단일
    v = decide(_fast3(3, 4, 0), _quality(), ab_results=_ab(*AB_CLAUDE_UNANIMOUS), ab_key=AB_KEY)
    assert (v.path, v.composition) == ("(i)", "단일")
    assert v.fast_sku == HAIKU and v.quality_sku == SONNET
    assert not v.provisional


def test_path_ii_both_decisive_crossed_mixed():
    # FAST: claude 결정승 / QUALITY: gemini 만장일치급 → (ii) 혼합
    v = decide(_fast3(3, 4, 0), _quality(), ab_results=_ab(*AB_GEMINI_UNANIMOUS), ab_key=AB_KEY)
    assert (v.path, v.composition) == ("(ii)", "혼합")
    assert v.fast_sku == HAIKU and v.quality_sku == G_PRO
    assert not v.provisional


def test_path_iii_fast_decisive_quality_narrow_converges():
    # FAST: claude 결정승 / QUALITY: 2승 0패 3무 = 근소 → (iii) 단일 claude로 수렴
    v = decide(_fast3(3, 4, 0), _quality(), ab_results=_ab(*AB_NARROW), ab_key=AB_KEY)
    assert (v.path, v.composition) == ("(iii)", "단일")
    assert v.fast_sku == HAIKU and v.quality_sku == SONNET
    assert not v.provisional


def test_path_iii_quality_decisive_fast_narrow_converges():
    # FAST: 최고 후보 차 0 = 근소 / QUALITY: claude 만장일치급 → (iii) 단일 claude로 수렴
    v = decide(_fast3(1, 2, 1), _quality(), ab_results=_ab(*AB_CLAUDE_UNANIMOUS), ab_key=AB_KEY)
    assert (v.path, v.composition) == ("(iii)", "단일")
    assert v.fast_sku == HAIKU and v.quality_sku == SONNET
    assert not v.provisional


def test_path_iv_both_narrow_gemini_single():
    # 양측 근소 → (iv) Gemini 단일(FAST=3 Flash·QUALITY=3.1 Pro)
    v = decide(_fast3(1, 1, 1), _quality(), ab_results=_ab(*AB_ALL_TIES), ab_key=AB_KEY)
    assert (v.path, v.composition) == ("(iv)", "단일")
    assert v.fast_sku == G_FLASH and v.quality_sku == G_PRO
    assert not v.provisional


# ── ① Gemini 내부 타이브레이커 ──────────────────────────────────────────────
def test_gemini_internal_three_or_more_gap_picks_winner_sku():
    # 내부 차 3(≥3, 개정 경계) → 3.5 Flash 승자, 이후 vs claude 차 7 → FAST 결정승 gemini(3.5)
    v = decide(_fast3(5, 2, 9), _quality(), ab_results=_ab(*AB_ALL_TIES), ab_key=AB_KEY)
    assert v.path == "(iii)"  # QUALITY 근소 → FAST 결정승 벤더(gemini)로 수렴
    assert v.fast_sku == G35_FLASH
    assert v.quality_sku == G_PRO


def test_gemini_internal_gap_of_two_prefers_3_flash():
    # 내부 차 2(≤2, 개정 경계 — 구 기준이면 승자) → 3.5가 더 적어도 3 Flash 선택
    v = decide(_fast3(2, 0, 9), _quality(), ab_results=_ab(*AB_ALL_TIES), ab_key=AB_KEY)
    assert v.fast_sku == G_FLASH
    assert any("단가 1/3" in r for r in v.rationale)


# ── ⓪ 게이트: 티어 귀속·handwritten·전멸 ───────────────────────────────────
def test_politeness_violation_hits_quality_only_not_fast():
    # 존대 오류(gemini QUALITY)는 QUALITY 결격일 뿐 FAST 판정에 무영향
    v = decide(_fast3(1, 1, 1), _quality(g_pol=2), ab_results=None, ab_key=None)
    assert v.path == "(iii)"  # QUALITY ⓪ 경유 결정승 claude ← FAST 근소 수렴
    assert (v.fast_sku, v.quality_sku) == (HAIKU, SONNET)
    assert not any("[결격/FAST]" in r for r in v.rationale)  # FAST 결격 없음
    assert any("[결격/QUALITY]" in r and "존대 오류" in r for r in v.rationale)


def test_fast_handwritten_zero_docs_gate_not_triggered():
    # handwritten tag 문서 0건이면 ⓪-(a)는 공허참으로 발동하지 않는다
    v = decide(_fast3(2, 3, 2), _quality(), ab_results=_ab(*AB_ALL_TIES), ab_key=AB_KEY)
    assert not any("[결격/FAST]" in r for r in v.rationale)
    assert any("handwritten 대상 문서 없음" in r for r in v.rationale)


def test_fast_handwritten_wipeout_disqualifies_single_candidate():
    # 3 Flash만 handwritten 전멸 → gemini 최고 후보는 3.5로 대체(집계는 3-way 유지)
    candidates = [
        _fast(G_FLASH, "gemini", [1, 1], tags={"001": ["handwritten"], "002": ["handwritten"]}),
        _fast(G35_FLASH, "gemini", [5]),
        _fast(HAIKU, "claude", [9]),
    ]
    v = decide(candidates, _quality(), ab_results=_ab(*AB_ALL_TIES), ab_key=AB_KEY)
    assert v.fast_sku == G35_FLASH  # 결격된 3 Flash(크리티컬 2) 대신 3.5(5)
    assert any("[결격/FAST]" in r and "손글씨 전멸" in r for r in v.rationale)


def test_fast_all_candidates_disqualified_is_undecidable():
    # FAST 전 후보 환각 ≥3 → 티어 전 후보 탈락 = 판정 불가
    candidates = [
        _fast(G_FLASH, "gemini", [0], hallucs=[3]),
        _fast(G35_FLASH, "gemini", [0], hallucs=[4]),
        _fast(HAIKU, "claude", [0], hallucs=[5]),
    ]
    v = decide(candidates, _quality(), ab_results=_ab(*AB_ALL_TIES), ab_key=AB_KEY)
    assert (v.fast_sku, v.quality_sku, v.composition, v.path) == (None, None, None, None)
    assert v.provisional
    assert any("판정 불가" in r for r in v.rationale)


def test_quality_all_candidates_disqualified_is_undecidable():
    # QUALITY 두 후보 모두 존대 오류 → 티어 전 후보 탈락 = 판정 불가
    v = decide(_fast3(0, 1, 5), _quality(g_pol=1, c_pol=2), ab_results=None, ab_key=None)
    assert (v.fast_sku, v.quality_sku) == (None, None)
    assert v.provisional
    assert any("판정 불가" in r and "QUALITY" in r for r in v.rationale)


def test_fast_vendor_disqualified_gives_gate_decisive_win():
    # gemini 두 SKU 전부 결격 → ⓪ 경유 FAST 결정승 claude
    candidates = [
        _fast(G_FLASH, "gemini", [0], hallucs=[3]),
        _fast(G35_FLASH, "gemini", [0], hallucs=[3]),
        _fast(HAIKU, "claude", [7]),
    ]
    v = decide(candidates, _quality(), ab_results=_ab(*AB_CLAUDE_UNANIMOUS), ab_key=AB_KEY)
    assert (v.path, v.fast_sku) == ("(i)", HAIKU)


# ── ① 결정승 경계(§11 개정 2026-07-06: 차 3부터 결정승, 차 2는 근소) ────────
def test_fast_gap_of_two_is_now_narrow():
    # 벤더 간 차 2 = 근소(구 기준이면 결정승) → 양측 근소 → (iv) Gemini 단일
    v = decide(_fast3(0, 1, 2), _quality(), ab_results=_ab(*AB_ALL_TIES), ab_key=AB_KEY)
    assert (v.path, v.composition) == ("(iv)", "단일")
    assert any("차 2(≤2) → 근소" in r for r in v.rationale)


def test_fast_gap_of_three_is_decisive():
    # 벤더 간 차 3 = 결정승(개정 경계) → QUALITY 근소 수렴 → (iii) Gemini 단일
    v = decide(_fast3(0, 1, 3), _quality(), ab_results=_ab(*AB_ALL_TIES), ab_key=AB_KEY)
    assert (v.path, v.fast_sku) == ("(iii)", G_FLASH)
    assert any("차 3(≥3) → 결정승: gemini" in r for r in v.rationale)


# ── 3-way 집계 ──────────────────────────────────────────────────────────────
def test_three_way_aggregation_uses_best_per_vendor():
    # 후보 3개 각각 집계 → gemini 최고(내부 결정승 4) vs claude 7 — 차 3 → FAST 결정승 gemini
    v = decide(_fast3(9, 4, 7), _quality(), ab_results=_ab(*AB_GEMINI_UNANIMOUS), ab_key=AB_KEY)
    assert (v.path, v.composition) == ("(i)", "단일")
    assert v.fast_sku == G35_FLASH and v.quality_sku == G_PRO


# ── 부분 실행·수동 입력 부재 ────────────────────────────────────────────────
def test_missing_vendor_fast_candidates_is_undecidable():
    # claude FAST 후보 부재(부분 실행/스모크) → 티어 판정 불가
    candidates = [_fast(G_FLASH, "gemini", [0]), _fast(G35_FLASH, "gemini", [1])]
    v = decide(candidates, _quality(), ab_results=_ab(*AB_ALL_TIES), ab_key=AB_KEY)
    assert v.fast_sku is None
    assert any("후보 부재" in r for r in v.rationale)


def test_manual_inputs_absent_is_pending():
    # 존대·A/B 수동 평가 전 → pending 잠정 판정(양측 근소 취급 → (iv) 잠정)
    quality = [
        QualityCandidate(sku=G_PRO, vendor="gemini", politeness_violations=None),
        QualityCandidate(sku=SONNET, vendor="claude", politeness_violations=None),
    ]
    v = decide(_fast3(1, 1, 1), quality, ab_results=None, ab_key=None)
    assert v.provisional
    assert (v.path, v.fast_sku, v.quality_sku) == ("(iv)", G_FLASH, G_PRO)
    assert any(r.startswith("[대기]") for r in v.rationale)
