"""
판정 규칙 적용 — 정본: 노션 'AI 모델 조사 — 결정 #4' §11 (2026-07-06 사전 등록).

절차(정본 그대로):
⓪ 결격 게이트(벤더 중립, 판정 전 적용). 하나라도 해당하면 그 벤더 탈락:
   (i)   손글씨 전멸 — manifest tag 'handwritten' 문서 전부에서 크리티컬 미스 [자동]
   (ii)  dates·amounts 환각(골드에 없는 값 생성) 합계 3건 이상 [자동]
   (iii) 존대 오류 — QUALITY 출력에 반말 혼입·비문 존대 [수동 입력]
   양쪽 다 탈락 시 '판정 불가' 플래그(사람 에스컬레이션).
① 크리티컬 미스 총합 차 ≥2 → 적은 쪽 채택(벤더 대칭).
② 차 ≤1 → 블라인드 A/B 만장일치급 우세면 그쪽 채택.
   수치화: 무승부 제외 승패가 갈린 항목에서 전승 + 승리 항목 수 ≥3.
③ 그 외(둘 다 근소/불명확) → Gemini.

불변: verdict는 판정을 스스로 바꾸지 않는다 — 규칙 개정이 필요해 보이면 '개정 필요'
플래그와 사유만 출력(개정 결정은 탕지수). 코드는 개정 필요를 자동 판단하지 않으며
Verdict.revision_needed 필드만 유지한다. 리포트에는 원자료 전체를 첨부한다.

수동 입력 인터페이스 — results/manual_review.json (없으면 pending 잠정 판정):
  {"politeness_violations": {"gemini": 0, "claude": 0},
   "ab_results": [{"item_id": "1", "winner": "A" | "B" | "tie"}]}
verdict가 ab_key.json과 조합해 A/B→벤더 매핑을 수행한다(평가자는 키를 열지 않는다).

단독 실행 — 수동 평가를 API 재호출 없이 반영(results/ 원출력 덤프를 재채점):
    python ai/pilots/llm_sku/eval/verdict.py [--results DIR] [--manifest PATH]
    → results/verdict_final.md
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass, field
from pathlib import Path

_LLM_SKU_DIR = Path(__file__).resolve().parents[1]
if str(_LLM_SKU_DIR) not in sys.path:
    # 단독 실행(python .../eval/verdict.py)에서도 eval/ 절대 import가 되도록
    sys.path.insert(0, str(_LLM_SKU_DIR))

from gaon_shared import ExtractedItem  # noqa: E402

from eval.scorer import DocScore, score_document  # noqa: E402

_RESULTS_DIR_DEFAULT = _LLM_SKU_DIR / "results"
_MANIFEST_DEFAULT = _LLM_SKU_DIR / "dataset" / "manifest.json"

_VENDORS = ("gemini", "claude")


@dataclass
class VendorStats:
    vendor: str
    doc_scores: list[DocScore]
    tags_by_doc: dict[str, list[str]]  # doc_id → manifest tags(실패 유형 분석용, §5)
    failed_docs: list[str] = field(default_factory=list)  # 파싱 자체 실패(빈 출력으로 채점됨)

    @property
    def total_critical(self) -> int:
        return sum(d.critical_misses for d in self.doc_scores)

    @property
    def total_hallucination(self) -> int:
        return sum(d.hallucination_count for d in self.doc_scores)


@dataclass
class Verdict:
    winner: str | None  # "gemini" | "claude" | None(판정 불가·보류)
    provisional: bool  # 수동 평가 대기 등으로 잠정 여부
    rationale: list[str]
    revision_needed: bool = False  # §11 불변 — 자동 설정하지 않는다(개정 판단은 사람)
    risks: list[str] = field(default_factory=list)


@dataclass
class ManualReview:
    """results/manual_review.json — 평가자 수동 입력. 키 누락은 '미평가'로 취급."""

    politeness_violations: dict[str, int] = field(default_factory=dict)
    ab_results: list[dict[str, str]] = field(default_factory=list)


# ── 수동 입력 로드 ──────────────────────────────────────────────────────────
def load_manual_review(results_dir: Path) -> ManualReview | None:
    path = results_dir / "manual_review.json"
    if not path.exists():
        return None
    raw = json.loads(path.read_text(encoding="utf-8"))
    return ManualReview(
        politeness_violations=dict(raw.get("politeness_violations", {})),
        ab_results=list(raw.get("ab_results", [])),
    )


def load_ab_key(results_dir: Path) -> dict[str, dict[str, str]] | None:
    path = results_dir / "ab_key.json"
    if not path.exists():
        return None
    return json.loads(path.read_text(encoding="utf-8"))


def tally_ab(
    ab_results: list[dict[str, str]], ab_key: dict[str, dict[str, str]] | None
) -> tuple[dict[str, int], int, list[str]]:
    """A/B 라벨 기록을 ab_key와 조합해 벤더별 승수로 매핑한다(평가자는 키를 열지 않는다)."""
    wins = {v: 0 for v in _VENDORS}
    ties = 0
    lines: list[str] = []
    for r in ab_results:
        item = str(r.get("item_id"))
        winner = r.get("winner")
        if winner == "tie":
            ties += 1
            lines.append(f"문항 {item}: 무승부")
            continue
        if winner not in ("A", "B"):
            raise ValueError(f"ab_results의 winner는 'A'|'B'|'tie'만 허용: {r!r}")
        if not ab_key or item not in ab_key:
            raise ValueError(f"ab_key.json에 문항 {item} 배정이 없음 — A/B→벤더 매핑 불가")
        vendor = ab_key[item].get(winner)
        if vendor not in wins:
            raise ValueError(f"ab_key 문항 {item}의 '{winner}' 벤더가 유효하지 않음: {vendor!r}")
        wins[vendor] += 1
        lines.append(f"문항 {item}: {winner}={vendor} 승")
    return wins, ties, lines


def unanimous_ab_winner(wins: dict[str, int]) -> str | None:
    """§11-② 수치화: 무승부 제외 승패가 갈린 항목에서 전승 + 승리 항목 수 ≥3."""
    g, c = wins["gemini"], wins["claude"]
    if g >= 3 and c == 0:
        return "gemini"
    if c >= 3 and g == 0:
        return "claude"
    return None


# ── ⓪ 결격 게이트 ───────────────────────────────────────────────────────────
def _handwritten_docs(stats: VendorStats) -> list[DocScore]:
    return [d for d in stats.doc_scores if "handwritten" in stats.tags_by_doc.get(d.doc_id, [])]


def _handwritten_status(stats: VendorStats) -> str:
    hw = _handwritten_docs(stats)
    if not hw:
        return "대상 문서 없음"
    miss = sum(1 for d in hw if d.critical_misses > 0 or d.doc_id in stats.failed_docs)
    return f"{len(hw)}건 중 {miss}건 크리티컬 미스"


def disqualifications(stats: VendorStats, politeness: int | None) -> list[str]:
    """⓪ 결격 게이트 — 해당 사유 목록(비면 통과). politeness=None은 미평가(게이트 보류)."""
    reasons: list[str] = []
    hw = _handwritten_docs(stats)
    if hw and all(d.critical_misses > 0 or d.doc_id in stats.failed_docs for d in hw):
        reasons.append(f"(i) 손글씨 전멸 — handwritten {len(hw)}건 전부 크리티컬 미스")
    if stats.total_hallucination >= 3:
        reasons.append(f"(ii) 환각 날짜/금액 합계 {stats.total_hallucination}건(≥3)")
    if politeness is not None and politeness > 0:
        reasons.append(f"(iii) 존대 오류 {politeness}건(수동 평가)")
    return reasons


def _fmt_pol(v: int | None) -> str:
    return "미평가" if v is None else f"{v}건"


# ── 판정 ────────────────────────────────────────────────────────────────────
def decide(
    gemini: VendorStats | None,
    claude: VendorStats | None,
    *,
    results_dir: Path | None = None,
    manual_review: ManualReview | None = None,  # None이면 results_dir에서 파일 로드 시도
    ab_key: dict[str, dict[str, str]] | None = None,  # None이면 results_dir에서 파일 로드 시도
) -> Verdict:
    """§11 절차를 순서대로 적용해 판정을 돌려준다. 수동 입력이 없으면 pending 잠정 판정."""
    risks = [
        "vi(베트남어) 해설 품질은 미검증 리스크 — A/B 결과와 별개로 vi 출력 원문"
        "(ab_pairs.md)을 육안 점검할 것."
    ]
    if gemini is None or claude is None:
        present = gemini if gemini is not None else claude
        who = present.vendor if present else "없음"
        return Verdict(
            winner=None,
            provisional=True,
            rationale=[f"한쪽 벤더만 실행됨({who}) — 비교 판정 불가(스모크 실행)."],
            risks=risks,
        )

    rd = Path(results_dir) if results_dir is not None else _RESULTS_DIR_DEFAULT
    if manual_review is None:
        manual_review = load_manual_review(rd)
    if ab_key is None:
        ab_key = load_ab_key(rd)

    pol = manual_review.politeness_violations if manual_review else {}
    pol_g, pol_c = pol.get("gemini"), pol.get("claude")

    # 판정 경로가 요구하는 수동 신호가 비어 있으면 [대기]로 표기하고 잠정 처리
    gaps: list[str] = []
    if pol_g is None or pol_c is None:
        gaps.append("⓪-(iii) 존대 오류 수동 평가 없음(results/manual_review.json)")

    wins: dict[str, int] | None = None
    ties = 0
    ab_lines: list[str] = []
    if manual_review and manual_review.ab_results:
        wins, ties, ab_lines = tally_ab(manual_review.ab_results, ab_key)

    g_total, c_total = gemini.total_critical, claude.total_critical
    diff = abs(g_total - c_total)

    # 원자료 전체 첨부(§11 불변)
    rationale = [
        f"크리티컬 미스 총합: gemini={g_total}, claude={c_total} (차={diff})",
        f"환각(날짜+금액): gemini={gemini.total_hallucination}, "
        f"claude={claude.total_hallucination}",
        f"파싱 실패: gemini={len(gemini.failed_docs)}건, claude={len(claude.failed_docs)}건",
        f"handwritten 게이트: gemini={_handwritten_status(gemini)}, "
        f"claude={_handwritten_status(claude)}",
        f"존대 오류(수동): gemini={_fmt_pol(pol_g)}, claude={_fmt_pol(pol_c)}",
    ]
    if wins is not None:
        rationale.append(
            f"A/B 집계: gemini {wins['gemini']}승 · claude {wins['claude']}승 · 무승부 {ties}"
        )
        rationale += [f"  {ln}" for ln in ab_lines]
    else:
        rationale.append("A/B 집계: 미평가(manual_review.json 없음 또는 ab_results 비어 있음)")

    g_dq = disqualifications(gemini, pol_g)
    c_dq = disqualifications(claude, pol_c)
    rationale += [f"[결격] gemini: {r}" for r in g_dq]
    rationale += [f"[결격] claude: {r}" for r in c_dq]

    def _with_gaps(lines: list[str], extra: list[str] | None = None) -> tuple[list[str], bool]:
        all_gaps = gaps + (extra or [])
        return lines + [f"[대기] {g}" for g in all_gaps], bool(all_gaps)

    # ⓪ 결격 게이트 — 판정 전 적용
    if g_dq and c_dq:
        return Verdict(
            winner=None,
            provisional=True,
            rationale=rationale + ["적용: ⓪ 양쪽 모두 결격 — 판정 불가, 사람 에스컬레이션."],
            risks=risks,
        )
    if g_dq or c_dq:
        winner, loser = ("claude", "gemini") if g_dq else ("gemini", "claude")
        lines, provisional = _with_gaps(
            rationale + [f"적용: ⓪ {loser} 결격 → 개수 무관 탈락, {winner} 채택."]
        )
        return Verdict(winner=winner, provisional=provisional, rationale=lines, risks=risks)

    # ① 크리티컬 미스 총합 차 ≥2 → 적은 쪽(벤더 대칭)
    if diff >= 2:
        winner = "gemini" if g_total < c_total else "claude"
        lines, provisional = _with_gaps(
            rationale + [f"적용: ① 차 {diff}(≥2) → 크리티컬 미스 적은 쪽({winner}) 채택."]
        )
        return Verdict(winner=winner, provisional=provisional, rationale=lines, risks=risks)

    # ② 차 ≤1 → A/B 만장일치급 우세면 그쪽
    if wins is None:
        lines, provisional = _with_gaps(
            rationale
            + [
                "적용: ② 차 ≤1 — A/B 수동 평가 대기(만장일치급 우세 시 그쪽, 아니면 ③ Gemini).",
                "현재 잠정 기본값: Gemini(③).",
            ],
            extra=["② 블라인드 A/B 수동 평가 없음(results/manual_review.json)"],
        )
        return Verdict(winner="gemini", provisional=provisional, rationale=lines, risks=risks)

    uw = unanimous_ab_winner(wins)
    if uw is not None:
        lines, provisional = _with_gaps(
            rationale
            + [f"적용: ② 차 ≤1 + A/B 만장일치급 우세({uw} {wins[uw]}승 무패) → {uw} 채택."]
        )
        return Verdict(winner=uw, provisional=provisional, rationale=lines, risks=risks)

    # ③ 그 외(둘 다 근소/불명확) → Gemini
    lines, provisional = _with_gaps(
        rationale
        + [
            f"적용: ② 만장일치급 우세 없음(gemini {wins['gemini']}승, "
            f"claude {wins['claude']}승, 무승부 {ties}) → ③ Gemini 채택."
        ]
    )
    return Verdict(winner="gemini", provisional=provisional, rationale=lines, risks=risks)


# ── 단독 실행: results/ 덤프 재채점 → 수동 평가 반영(API 재호출 없음) ─────────
def rebuild_vendor_stats(vendor: str, docs: list[dict], results_dir: Path) -> VendorStats | None:
    """run_pilot이 덤프한 원출력({doc_id}.json/.error.txt)을 재채점해 VendorStats 복원."""
    vendor_dir = results_dir / vendor
    if not vendor_dir.is_dir():
        return None
    doc_scores: list[DocScore] = []
    failed: list[str] = []
    tags_by_doc: dict[str, list[str]] = {}
    for doc in docs:
        doc_id = doc["doc_id"]
        dump = vendor_dir / f"{doc_id}.json"
        err = vendor_dir / f"{doc_id}.error.txt"
        if dump.exists():
            item = ExtractedItem.model_validate_json(dump.read_text(encoding="utf-8"))
        elif err.exists():
            # 파싱 실패는 실행 시와 동일하게 '빈 출력'으로 채점
            item = ExtractedItem(doc_type="notice", title="", raw_text="")
            failed.append(doc_id)
        else:
            continue  # 실행 시 스킵(이미지 미투입)된 문서
        tags_by_doc[doc_id] = list(doc.get("tags", []))
        doc_scores.append(score_document(doc_id, item, doc["gold"]))
    if not doc_scores:
        return None
    return VendorStats(
        vendor=vendor, doc_scores=doc_scores, tags_by_doc=tags_by_doc, failed_docs=failed
    )


def render_verdict_text(verdict: Verdict) -> str:
    lines = ["# 최종 판정 (verdict_final.md)", ""]
    if verdict.winner is None:
        lines.append("**판정: 보류/불가**")
    else:
        status = "잠정" if verdict.provisional else "확정"
        lines.append(f"**판정({status}): {verdict.winner.upper()} 채택**")
    if verdict.revision_needed:
        lines += ["", "**[개정 필요 플래그]** 규칙 개정이 필요해 보임 — 개정 결정은 탕지수."]
    lines += ["", "## 근거 수치(원자료)"] + [f"- {r}" for r in verdict.rationale]
    lines += ["", "## 리스크"] + [f"- {r}" for r in verdict.risks]
    lines += ["", "신뢰성·비용 요약(재시도·토큰·지연)은 실행 시 리포트(results/verdict.md) 참조."]
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(
        description="§11 판정 재적용 — 수동 평가(manual_review.json) 반영, API 재호출 없음"
    )
    parser.add_argument("--results", type=Path, default=_RESULTS_DIR_DEFAULT)
    parser.add_argument("--manifest", type=Path, default=_MANIFEST_DEFAULT)
    args = parser.parse_args()

    docs = json.loads(args.manifest.read_text(encoding="utf-8"))["documents"]
    gemini = rebuild_vendor_stats("gemini", docs, args.results)
    claude = rebuild_vendor_stats("claude", docs, args.results)
    verdict = decide(gemini, claude, results_dir=args.results)

    text = render_verdict_text(verdict)
    args.results.mkdir(parents=True, exist_ok=True)
    out = args.results / "verdict_final.md"
    out.write_text(text, encoding="utf-8")
    print(text)
    print(f"저장: {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
