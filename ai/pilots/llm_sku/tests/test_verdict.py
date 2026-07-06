"""판정 규칙(§11 정본, 2026-07-06 사전 등록) 회귀 테스트 — 순수 함수만, 실 API 없음.

경로별 고정 케이스: ⓪ 결격 게이트(손글씨 전멸·환각 ≥3·존대 오류·양쪽 탈락),
① 크리티컬 미스 차 ≥2 대칭 채택, ② A/B 만장일치급 수치화(전승+승 ≥3),
③ Gemini 폴백, 수동 입력(manual_review.json) 부재 → pending.
실행: pytest ai/pilots/llm_sku/tests
"""

from eval.scorer import DocScore, SetScore, SupplyScore
from eval.verdict import ManualReview, VendorStats, decide


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


def _stats(vendor, criticals, hallucs=None, tags=None, failed=()) -> VendorStats:
    hallucs = hallucs or [0] * len(criticals)
    docs = [_doc(f"{i:03d}", c, h) for i, (c, h) in enumerate(zip(criticals, hallucs), start=1)]
    tags_by_doc = {d.doc_id: list((tags or {}).get(d.doc_id, [])) for d in docs}
    return VendorStats(
        vendor=vendor, doc_scores=docs, tags_by_doc=tags_by_doc, failed_docs=list(failed)
    )


# run_pilot이 생성하는 ab_key.json과 같은 형태 — A/B 배정을 문항별로 섞어 매핑 로직을 검증
AB_KEY = {
    "1": {"A": "gemini", "B": "claude"},
    "2": {"A": "claude", "B": "gemini"},
    "3": {"A": "gemini", "B": "claude"},
    "4": {"A": "claude", "B": "gemini"},
    "5": {"A": "gemini", "B": "claude"},
}


def _ab_results(*winners_by_item):
    """문항 1..N의 승자(벤더명 또는 'tie')를 평가자 시점의 A/B 라벨 기록으로 변환."""
    results = []
    for i, w in enumerate(winners_by_item, start=1):
        if w == "tie":
            results.append({"item_id": str(i), "winner": "tie"})
        else:
            letter = "A" if AB_KEY[str(i)]["A"] == w else "B"
            results.append({"item_id": str(i), "winner": letter})
    return results


def _manual(g_pol=0, c_pol=0, ab=()) -> ManualReview:
    return ManualReview(
        politeness_violations={"gemini": g_pol, "claude": c_pol}, ab_results=list(ab)
    )


# ── ⓪ 결격 게이트 ───────────────────────────────────────────────────────────
def test_gate_handwritten_wipeout_disqualifies_despite_fewer_misses():
    # gemini가 크리티컬 미스는 더 적지만 handwritten 전멸 → ① 이전에 ⓪로 탈락(게이트 우선)
    gemini = _stats("gemini", [1, 1, 0], tags={"001": ["handwritten"], "002": ["handwritten"]})
    claude = _stats("claude", [2, 2, 2])
    v = decide(gemini, claude, manual_review=_manual(), ab_key=AB_KEY)
    assert v.winner == "claude"
    assert not v.provisional
    assert any("손글씨 전멸" in r for r in v.rationale if r.startswith("[결격] gemini"))


def test_gate_handwritten_requires_all_docs_missed():
    # handwritten 2건 중 1건만 미스 → 전멸 아님 → 게이트 통과, ①로 판정
    gemini = _stats("gemini", [1, 0, 0], tags={"001": ["handwritten"], "002": ["handwritten"]})
    claude = _stats("claude", [2, 2, 0])
    v = decide(gemini, claude, manual_review=_manual(), ab_key=AB_KEY)
    assert v.winner == "gemini"  # ①: 1 vs 4
    assert not any(r.startswith("[결격]") for r in v.rationale)


def test_gate_hallucination_three_or_more_disqualifies():
    gemini = _stats("gemini", [0, 0])
    claude = _stats("claude", [0, 0], hallucs=[2, 1])  # 합계 3건 → ⓪-(ii)
    v = decide(gemini, claude, manual_review=_manual(), ab_key=AB_KEY)
    assert v.winner == "gemini"
    assert any("환각" in r for r in v.rationale if r.startswith("[결격] claude"))


def test_gate_politeness_violation_disqualifies():
    # 수치가 동률이라도 존대 오류(수동)가 있으면 ⓪-(iii)로 탈락
    v = decide(
        _stats("gemini", [1]),
        _stats("claude", [1]),
        manual_review=_manual(c_pol=2),
        ab_key=AB_KEY,
    )
    assert v.winner == "gemini"
    assert not v.provisional
    assert any("존대 오류" in r for r in v.rationale if r.startswith("[결격] claude"))


def test_gate_both_disqualified_is_undecidable():
    gemini = _stats("gemini", [0], hallucs=[3])
    claude = _stats("claude", [0], hallucs=[4])
    v = decide(gemini, claude, manual_review=_manual(), ab_key=AB_KEY)
    assert v.winner is None
    assert v.provisional
    assert any("판정 불가" in r for r in v.rationale)


# ── ① 크리티컬 미스 차 ≥2 — 벤더 대칭 ──────────────────────────────────────
def test_rule1_claude_adopted_when_two_fewer():
    v = decide(
        _stats("gemini", [2, 2]), _stats("claude", [1, 1]), manual_review=_manual(), ab_key=AB_KEY
    )
    assert v.winner == "claude"
    assert not v.provisional


def test_rule1_gemini_adopted_when_two_fewer():
    v = decide(
        _stats("gemini", [1, 1]), _stats("claude", [2, 2]), manual_review=_manual(), ab_key=AB_KEY
    )
    assert v.winner == "gemini"
    assert not v.provisional


def test_rule1_pending_politeness_gate_when_manual_absent():
    # ①로 승자는 정해지지만 ⓪-(iii) 존대 평가 전이므로 잠정
    v = decide(
        _stats("gemini", [2, 2]), _stats("claude", [1, 1]), manual_review=ManualReview(), ab_key={}
    )
    assert v.winner == "claude"
    assert v.provisional
    assert any("존대 오류 수동 평가 없음" in r for r in v.rationale)


# ── ② 차 ≤1 — A/B 만장일치급 수치화(무승부 제외 전승 + 승 ≥3) ──────────────
def test_rule2_three_wins_no_loss_two_ties_adopts():
    ab = _ab_results("claude", "claude", "claude", "tie", "tie")  # 3승 0패 2무 → 채택
    v = decide(
        _stats("gemini", [1]), _stats("claude", [0]), manual_review=_manual(ab=ab), ab_key=AB_KEY
    )
    assert v.winner == "claude"
    assert not v.provisional
    assert any("만장일치급 우세" in r for r in v.rationale)


def test_rule2_four_one_is_insufficient():
    ab = _ab_results("claude", "claude", "claude", "claude", "gemini")  # 4승 1패 → 전승 아님
    v = decide(
        _stats("gemini", [1]), _stats("claude", [0]), manual_review=_manual(ab=ab), ab_key=AB_KEY
    )
    assert v.winner == "gemini"  # ③ 폴백
    assert not v.provisional


def test_rule2_two_wins_three_ties_is_insufficient():
    ab = _ab_results("claude", "claude", "tie", "tie", "tie")  # 2승 0패 3무 → 승 3개 미만
    v = decide(
        _stats("gemini", [1]), _stats("claude", [0]), manual_review=_manual(ab=ab), ab_key=AB_KEY
    )
    assert v.winner == "gemini"  # ③ 폴백
    assert not v.provisional


# ── ③ 폴백 ──────────────────────────────────────────────────────────────────
def test_rule3_all_ties_falls_back_to_gemini():
    ab = _ab_results("tie", "tie", "tie", "tie", "tie")
    v = decide(
        _stats("gemini", [1]), _stats("claude", [1]), manual_review=_manual(ab=ab), ab_key=AB_KEY
    )
    assert v.winner == "gemini"
    assert not v.provisional


# ── 수동 입력 부재 → pending 잠정 판정 ──────────────────────────────────────
def test_manual_review_absent_is_pending(tmp_path):
    # 빈 results 디렉토리로 파일 로더 경로까지 검증: manual_review.json 없음 → 잠정
    v = decide(_stats("gemini", [1]), _stats("claude", [1]), results_dir=tmp_path)
    assert v.provisional
    assert v.winner == "gemini"  # ② 평가 대기 중의 잠정 기본값 = ③ Gemini
    assert any(r.startswith("[대기]") for r in v.rationale)


def test_single_vendor_smoke_is_undecidable():
    v = decide(None, _stats("claude", [0]), manual_review=_manual(), ab_key=AB_KEY)
    assert v.winner is None
    assert v.provisional
