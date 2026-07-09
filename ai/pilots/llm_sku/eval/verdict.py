"""
판정 규칙 적용 — 정본: 조사 페이지 §11 v2 (2026-07-06, 실행 전 사전등록).

후보 구조(티어별):
  FAST(파싱) 3-way    — gemini-3-flash-preview · gemini-3.5-flash · Claude Haiku 4.5
  QUALITY(경어체) 2-way — gemini-3.1-pro-preview · Claude Sonnet 4.6

절차(정본 그대로):
⓪ 결격(티어별·후보별, 판정 전):
   FAST — (a) handwritten tag 문서 전멸(전부 크리티컬 미스) [자동, 태그 0건이면 미발동]
          (b) dates·amounts 환각(골드에 없는 값) 합계 3건 이상 [자동]
   QUALITY — 존대 오류(반말 혼입·비문 존대) [수동, manual_review.json 후보별]
   티어의 전 후보 탈락 → 판정 불가(사람 에스컬레이션).
① FAST: 후보 크리티컬 미스 집계 → 벤더별 최고 후보끼리 차 ≥3=결정승 / ≤2=근소.
   Gemini 내부 SKU: 두 SKU 차 ≥3이면 승자, ≤2이면 3 Flash(단가 1/3·무료 티어).
   (임계값은 §11 개정 2026-07-06: 입력셋 19장 확정, 채점 포인트 배증 ~40→~76에 비례해
    구 기준 대비 +1 상향. 환각 결격 게이트 ≥3은 의도적으로 불변)
② QUALITY: A/B 만장일치급(무승부 제외 전승 + 승 ≥3)=결정승 / 미만=근소.
③ 조합: (i) 양측 결정승·동일 벤더→단일 (ii) 양측 결정승·교차→혼합
   (iii) 편측 결정승→근소 티어는 결정승 벤더로 수렴 (iv) 양측 근소→Gemini 단일
   (괄호 'FAST=3 Flash·QUALITY=3.1 Pro'는 내부 근소 시 기본값 — 내부 결정승은 ①이 우선).

최종 출력: FAST SKU + QUALITY SKU + 구성(단일/혼합) + 적용 경로(i~iv) + 원자료 전체.
불변: 판정 자동 변경 금지 — 규칙 개정이 필요해 보이면 플래그·사유만
(Verdict.revision_needed는 코드가 자동 설정하지 않는다). 수동 입력 부재 시 pending.

수동 입력 — <ab-run>/manual_review.json (politeness_violations의 키는 벤더명 =
그 벤더의 QUALITY 후보를 지칭):
  {"politeness_violations": {"gemini": 0, "claude": 0},
   "ab_results": [{"item_id": "1", "winner": "A" | "B" | "tie"}]}
verdict가 <ab-run>/ab_key.json과 조합해 A/B→벤더 매핑을 수행한다(평가자는 키 미개봉).

단독 실행 — 전체 시퀀스(run1·run2·블라인드 평가) 완료 후, API 재호출 없이 덤프 재채점:
    python ai/pilots/llm_sku/eval/verdict.py \\
        --fast-run results/run1 --fast-run results/run2 --ab-run results/run1
    → <ab-run>/verdict_final.md
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

_MANIFEST_DEFAULT = _LLM_SKU_DIR / "dataset" / "manifest.json"

_VENDORS = ("gemini", "claude")
# ① 결정승 임계값(§11 개정 2026-07-06, 입력셋 19장 확정): 차 ≥3=결정승 / ≤2=근소.
#    FAST 벤더 간 비교와 Gemini 내부 타이브레이크 두 곳에 동일 적용(사전등록 고정 — 인자화 금지).
#    주의: ⓪ 환각 결격 게이트(≥3)는 비대칭 치명 결함이라 표본 비례 완화하지 않는 별개 값.
_FAST_DECISIVE_GAP = 3
# ① 내부 타이브레이크: 두 Gemini SKU 차 ≤2이면 이 SKU(단가 1/3·무료 티어, §11 v2)
_GEMINI_FAST_TIEBREAK_SKU = "gemini-3-flash-preview"


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
class FastCandidate:
    """FAST(파싱) 후보 1개 = 실행 1회분의 SKU × 재채점 결과."""

    sku: str  # 실제 사용 모델 ID(run_meta.json)
    vendor: str  # "gemini" | "claude"
    stats: VendorStats
    run: str = ""  # 출처 표기(예: results/run1)


@dataclass
class QualityCandidate:
    """QUALITY(경어체) 후보 1개. politeness_violations=None은 수동 평가 대기."""

    sku: str
    vendor: str
    politeness_violations: int | None = None


@dataclass
class Verdict:
    fast_sku: str | None  # None=판정 불가
    quality_sku: str | None
    composition: str | None  # "단일" | "혼합"
    path: str | None  # "(i)" | "(ii)" | "(iii)" | "(iv)"
    provisional: bool  # 수동 평가 대기 등으로 잠정 여부
    rationale: list[str]
    revision_needed: bool = False  # §11 불변 — 자동 설정하지 않는다(개정 판단은 사람)
    risks: list[str] = field(default_factory=list)


@dataclass
class ManualReview:
    """<ab-run>/manual_review.json — 평가자 수동 입력. 키 누락은 '미평가'로 취급."""

    politeness_violations: dict[str, int] = field(default_factory=dict)
    ab_results: list[dict[str, str]] = field(default_factory=list)


@dataclass
class TierOutcome:
    """티어(FAST/QUALITY) 하나의 판정 결과."""

    decisive_vendor: str | None  # 결정승 벤더(근소·미평가면 None)
    sku_by_vendor: dict[str, str]  # 벤더별 대표(생존) SKU
    lines: list[str]  # 원자료·근거
    gaps: list[str]  # 수동 평가 공백([대기] 표기·잠정 사유)
    undecidable: str | None  # 판정 불가 사유(None=정상)


# ── 수동 입력 로드 ──────────────────────────────────────────────────────────
def load_manual_review(path: Path) -> ManualReview | None:
    if not path.exists():
        return None
    raw = json.loads(path.read_text(encoding="utf-8"))
    return ManualReview(
        politeness_violations=dict(raw.get("politeness_violations", {})),
        ab_results=list(raw.get("ab_results", [])),
    )


def load_ab_key(path: Path) -> dict[str, dict[str, str]] | None:
    if not path.exists():
        return None
    return json.loads(path.read_text(encoding="utf-8"))


def load_run_meta(run_dir: Path) -> dict | None:
    """run_pilot이 기록한 티어별 실제 사용 모델 ID(후보 식별의 전제)."""
    path = run_dir / "run_meta.json"
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


# ── ⓪ 결격 게이트(티어별) ───────────────────────────────────────────────────
def _handwritten_docs(stats: VendorStats) -> list[DocScore]:
    return [d for d in stats.doc_scores if "handwritten" in stats.tags_by_doc.get(d.doc_id, [])]


def _handwritten_status(stats: VendorStats) -> str:
    hw = _handwritten_docs(stats)
    if not hw:
        return "대상 문서 없음"
    miss = sum(1 for d in hw if d.critical_misses > 0 or d.doc_id in stats.failed_docs)
    return f"{len(hw)}건 중 {miss}건 크리티컬 미스"


def fast_disqualifications(stats: VendorStats) -> list[str]:
    """⓪ FAST 결격[자동] — 사유 목록(비면 통과). 존대 오류는 QUALITY 티어 소관(무영향)."""
    reasons: list[str] = []
    hw = _handwritten_docs(stats)
    # 태그 0건이면 공허참으로 발동하지 않는다(hw 비면 all()이 True여도 게이트 미적용)
    if hw and all(d.critical_misses > 0 or d.doc_id in stats.failed_docs for d in hw):
        reasons.append(f"(a) 손글씨 전멸 — handwritten {len(hw)}건 전부 크리티컬 미스")
    if stats.total_hallucination >= 3:
        reasons.append(f"(b) 환각 날짜/금액 합계 {stats.total_hallucination}건(≥3)")
    return reasons


def _fmt_pol(v: int | None) -> str:
    return "미평가" if v is None else f"{v}건"


# ── ① FAST 티어 ─────────────────────────────────────────────────────────────
def _best_gemini_fast(survivors: list[FastCandidate], lines: list[str]) -> FastCandidate:
    """Gemini 내부 SKU 규칙: 두 SKU 차 ≥3이면 승자, ≤2이면 3 Flash(단가 1/3·무료 티어)."""
    if len(survivors) == 1:
        return survivors[0]
    ordered = sorted(survivors, key=lambda c: c.stats.total_critical)
    a, b = ordered[0], ordered[1]
    diff = b.stats.total_critical - a.stats.total_critical
    if diff >= _FAST_DECISIVE_GAP:
        lines.append(
            f"[FAST] Gemini 내부 SKU: {a.sku} {a.stats.total_critical} vs "
            f"{b.sku} {b.stats.total_critical} — 차 {diff}(≥{_FAST_DECISIVE_GAP}) → {a.sku}"
        )
        return a
    preferred = [c for c in survivors if c.sku == _GEMINI_FAST_TIEBREAK_SKU]
    if preferred:
        lines.append(
            f"[FAST] Gemini 내부 SKU: 차 {diff}(≤{_FAST_DECISIVE_GAP - 1}) → "
            f"{_GEMINI_FAST_TIEBREAK_SKU}(단가 1/3·무료 티어)"
        )
        return preferred[0]
    # 기본 SKU가 후보에 없으면(모델 미기록·env 교체 등) 크리티컬 최소 후보로 폴백
    lines.append(
        f"[FAST] Gemini 내부 SKU: 차 {diff}(≤{_FAST_DECISIVE_GAP - 1})·기본 SKU 부재 → "
        f"크리티컬 최소 {a.sku}"
    )
    return a


def _judge_fast(candidates: list[FastCandidate]) -> TierOutcome:
    lines = ["[FAST] 파싱 후보 집계(⓪→①):"]
    by_vendor: dict[str, list[FastCandidate]] = {}
    survivors_by_vendor: dict[str, list[FastCandidate]] = {v: [] for v in _VENDORS}
    for c in candidates:
        by_vendor.setdefault(c.vendor, []).append(c)
        src = f", {c.run}" if c.run else ""
        lines.append(
            f"  - {c.sku} [{c.vendor}{src}]: 크리티컬 {c.stats.total_critical} · "
            f"환각 {c.stats.total_hallucination} · 파싱 실패 {len(c.stats.failed_docs)}건 · "
            f"handwritten {_handwritten_status(c.stats)}"
        )
        dq = fast_disqualifications(c.stats)
        for r in dq:
            lines.append(f"    [결격/FAST] {c.sku}: {r}")
        if not dq:
            survivors_by_vendor.setdefault(c.vendor, []).append(c)

    if not candidates:
        return TierOutcome(None, {}, lines + ["[FAST] 후보 없음(실행 누락)"], [], "FAST 후보 없음")
    missing = [v for v in _VENDORS if not by_vendor.get(v)]
    if missing:
        reason = f"FAST {'/'.join(missing)} 후보 부재(부분 실행)"
        return TierOutcome(None, {}, lines + [f"[FAST] {reason} — 티어 판정 불가"], [], reason)
    if all(not survivors_by_vendor[v] for v in _VENDORS):
        return TierOutcome(
            None, {}, lines + ["[FAST] 전 후보 결격 — 티어 판정 불가"], [], "FAST 전 후보 결격"
        )

    best: dict[str, FastCandidate | None] = {}
    for vendor in _VENDORS:
        survivors = survivors_by_vendor[vendor]
        if not survivors:
            best[vendor] = None
        elif vendor == "gemini":
            best[vendor] = _best_gemini_fast(survivors, lines)
        else:
            best[vendor] = min(survivors, key=lambda c: c.stats.total_critical)

    g_best, c_best = best["gemini"], best["claude"]
    if g_best is None:
        assert c_best is not None
        lines.append("[FAST] gemini 전 후보 결격 → ⓪ 경유 결정승: claude")
        return TierOutcome("claude", {"claude": c_best.sku}, lines, [], None)
    if c_best is None:
        lines.append("[FAST] claude 전 후보 결격 → ⓪ 경유 결정승: gemini")
        return TierOutcome("gemini", {"gemini": g_best.sku}, lines, [], None)

    sku_by_vendor = {"gemini": g_best.sku, "claude": c_best.sku}
    g_total, c_total = g_best.stats.total_critical, c_best.stats.total_critical
    diff = abs(g_total - c_total)
    compare = (
        f"[FAST] 벤더 최고 후보 비교: gemini {g_total}({g_best.sku}) vs "
        f"claude {c_total}({c_best.sku}) — 차 {diff}"
    )
    if diff >= _FAST_DECISIVE_GAP:
        winner = "gemini" if g_total < c_total else "claude"
        lines.append(f"{compare}(≥{_FAST_DECISIVE_GAP}) → 결정승: {winner}")
        return TierOutcome(winner, sku_by_vendor, lines, [], None)
    lines.append(f"{compare}(≤{_FAST_DECISIVE_GAP - 1}) → 근소")
    return TierOutcome(None, sku_by_vendor, lines, [], None)


# ── ⓪+② QUALITY 티어 ────────────────────────────────────────────────────────
def _judge_quality(
    candidates: list[QualityCandidate],
    ab_results: list[dict[str, str]] | None,
    ab_key: dict[str, dict[str, str]] | None,
) -> TierOutcome:
    lines = ["[QUALITY] 경어체 후보 집계(⓪→②):"]
    gaps: list[str] = []
    by_vendor = {c.vendor: c for c in candidates}
    for c in candidates:
        lines.append(
            f"  - {c.sku} [{c.vendor}]: 존대 오류(수동) {_fmt_pol(c.politeness_violations)}"
        )

    if not candidates:
        return TierOutcome(
            None, {}, lines + ["[QUALITY] 후보 없음(A/B 실행 누락)"], [], "QUALITY 후보 없음"
        )
    missing = [v for v in _VENDORS if v not in by_vendor]
    if missing:
        reason = f"QUALITY {'/'.join(missing)} 후보 부재(부분 실행)"
        return TierOutcome(None, {}, lines + [f"[QUALITY] {reason} — 티어 판정 불가"], [], reason)

    sku_by_vendor = {v: c.sku for v, c in by_vendor.items()}
    dq: dict[str, str] = {}
    for v, c in by_vendor.items():
        if c.politeness_violations is not None and c.politeness_violations > 0:
            dq[v] = f"존대 오류 {c.politeness_violations}건(수동 평가)"
            lines.append(f"    [결격/QUALITY] {c.sku}: {dq[v]}")
        elif c.politeness_violations is None:
            gaps.append(f"⓪ 존대 오류 수동 평가 없음({v} QUALITY — manual_review.json)")

    if len(dq) == len(_VENDORS):
        return TierOutcome(
            None,
            sku_by_vendor,
            lines + ["[QUALITY] 전 후보 결격 — 티어 판정 불가"],
            gaps,
            "QUALITY 전 후보 결격",
        )
    if dq:
        survivor = next(v for v in _VENDORS if v not in dq)
        lines.append(f"[QUALITY] {'/'.join(dq)} 결격 → ⓪ 경유 결정승: {survivor}")
        return TierOutcome(survivor, sku_by_vendor, lines, gaps, None)

    if not ab_results:
        gaps.append("② 블라인드 A/B 수동 평가 없음(manual_review.json ab_results)")
        lines.append("[QUALITY] A/B 미평가 — 잠정적으로 근소 취급(② 평가 대기)")
        return TierOutcome(None, sku_by_vendor, lines, gaps, None)

    wins, ties, item_lines = tally_ab(ab_results, ab_key)
    lines.append(
        f"[QUALITY] A/B 집계: gemini {wins['gemini']}승 · claude {wins['claude']}승 "
        f"· 무승부 {ties}"
    )
    lines += [f"    {ln}" for ln in item_lines]
    uw = unanimous_ab_winner(wins)
    if uw is not None:
        lines.append(f"[QUALITY] 만장일치급 우세({uw} {wins[uw]}승 무패, 승 ≥3) → 결정승: {uw}")
        return TierOutcome(uw, sku_by_vendor, lines, gaps, None)
    lines.append("[QUALITY] 만장일치급 우세 없음 → 근소")
    return TierOutcome(None, sku_by_vendor, lines, gaps, None)


# ── ③ 조합 + 최종 판정 ──────────────────────────────────────────────────────
def decide(
    fast_candidates: list[FastCandidate],
    quality_candidates: list[QualityCandidate],
    ab_results: list[dict[str, str]] | None = None,
    ab_key: dict[str, dict[str, str]] | None = None,
) -> Verdict:
    """§11 v2 절차(⓪→①→②→③)를 적용해 티어별 SKU + 구성 + 경로를 돌려준다(순수 함수)."""
    risks = [
        "vi(베트남어) 해설 품질은 미검증 리스크 — A/B 결과와 별개로 vi 출력 원문"
        "(ab_pairs.md)을 육안 점검할 것."
    ]
    fast = _judge_fast(fast_candidates)
    quality = _judge_quality(quality_candidates, ab_results, ab_key)
    rationale = fast.lines + quality.lines
    gaps = fast.gaps + quality.gaps

    undecidable = [r for r in (fast.undecidable, quality.undecidable) if r]
    if undecidable:
        rationale.append("판정 불가(" + " / ".join(undecidable) + ") — 사람 에스컬레이션.")
        rationale += [f"[대기] {g}" for g in gaps]
        return Verdict(None, None, None, None, True, rationale, risks=risks)

    fd, qd = fast.decisive_vendor, quality.decisive_vendor
    if fd and qd:
        path = "(i)" if fd == qd else "(ii)"
        fast_vendor, quality_vendor = fd, qd
    elif fd:
        path = "(iii)"
        fast_vendor = quality_vendor = fd  # QUALITY(근소)가 FAST 결정승 벤더로 수렴
    elif qd:
        path = "(iii)"
        fast_vendor = quality_vendor = qd  # FAST(근소)가 QUALITY 결정승 벤더로 수렴
    else:
        path = "(iv)"
        fast_vendor = quality_vendor = "gemini"  # 양측 근소 → Gemini 단일

    fast_sku = fast.sku_by_vendor[fast_vendor]
    quality_sku = quality.sku_by_vendor[quality_vendor]
    composition = "단일" if fast_vendor == quality_vendor else "혼합"
    rationale.append(
        f"적용 경로 {path}: FAST={fast_vendor}({fast_sku}) · "
        f"QUALITY={quality_vendor}({quality_sku}) → 구성: {composition}"
    )
    if path == "(iv)" and fast_sku != _GEMINI_FAST_TIEBREAK_SKU:
        # (iv) 괄호 기본값(3 Flash) 대신 ① 내부 결정승 SKU 적용 — 해석은 ① 우선(정본 확인 대상)
        rationale.append(
            f"주: (iv) 기본값({_GEMINI_FAST_TIEBREAK_SKU}) 대신 ① 내부 결정승({fast_sku}) 적용."
        )
    rationale += [f"[대기] {g}" for g in gaps]
    return Verdict(
        fast_sku=fast_sku,
        quality_sku=quality_sku,
        composition=composition,
        path=path,
        provisional=bool(gaps),
        rationale=rationale,
        risks=risks,
    )


# ── 단독 실행: 다중 run 디렉토리 재채점 → §11 v2 판정(API 재호출 없음) ────────
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


def build_fast_candidates(run_dirs: list[Path], docs: list[dict]) -> list[FastCandidate]:
    """각 run 디렉토리의 벤더별 덤프 + run_meta.json(FAST 모델 ID)로 후보 목록 구성."""
    out: list[FastCandidate] = []
    seen: set[tuple[str, str]] = set()
    for rd in run_dirs:
        meta = load_run_meta(rd) or {}
        models = meta.get("models", {})
        for vendor in _VENDORS:
            stats = rebuild_vendor_stats(vendor, docs, rd)
            if stats is None:
                continue
            sku = models.get(vendor, {}).get("fast") or f"{vendor}-fast(모델 미기록)"
            key = (vendor, sku)
            if key in seen:
                print(f"[경고] 중복 FAST 후보 스킵: {sku} ({rd})")
                continue
            seen.add(key)
            out.append(FastCandidate(sku=sku, vendor=vendor, stats=stats, run=str(rd)))
    return out


def build_quality_candidates(ab_run: Path, manual: ManualReview | None) -> list[QualityCandidate]:
    """A/B 실행분의 run_meta.json(QUALITY 모델 ID) + 수동 존대 평가로 후보 목록 구성."""
    meta = load_run_meta(ab_run) or {}
    models = meta.get("models", {})
    pol = manual.politeness_violations if manual else {}
    out: list[QualityCandidate] = []
    for vendor in _VENDORS:
        if vendor not in models:
            continue  # 해당 벤더 미실행(부분 실행)
        sku = models[vendor].get("quality") or f"{vendor}-quality(모델 미기록)"
        out.append(QualityCandidate(sku=sku, vendor=vendor, politeness_violations=pol.get(vendor)))
    return out


def render_verdict_text(v: Verdict) -> str:
    lines = ["# 최종 판정 (verdict_final.md) — 조사 페이지 §11 v2(2026-07-06 사전등록)", ""]
    if v.fast_sku is None or v.quality_sku is None:
        lines.append("**판정 불가 — 사람 에스컬레이션**")
    else:
        status = "잠정" if v.provisional else "확정"
        lines += [
            f"**판정({status}) — 구성: {v.composition} / 적용 경로 {v.path}**",
            "",
            f"- FAST(파싱) SKU: `{v.fast_sku}`",
            f"- QUALITY(경어체) SKU: `{v.quality_sku}`",
        ]
    if v.revision_needed:
        lines += ["", "**[개정 필요 플래그]** 규칙 개정이 필요해 보임 — 개정 결정은 탕지수."]
    lines += ["", "## 근거 수치(원자료)"] + [f"- {r}" for r in v.rationale]
    lines += ["", "## 리스크"] + [f"- {r}" for r in v.risks]
    lines += ["", "신뢰성·비용 요약(재시도·토큰·지연)은 각 실행 리포트(run_report.md) 참조."]
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(
        description="§11 v2 판정 — 다중 run 재채점 + 수동 평가 반영(API 재호출 없음)"
    )
    parser.add_argument(
        "--fast-run",
        action="append",
        type=Path,
        default=None,
        help="FAST(파싱) 결과 디렉토리 — 반복 지정(예: run1·run2)",
    )
    parser.add_argument(
        "--ab-run",
        type=Path,
        default=None,
        help="QUALITY(A/B) 결과 디렉토리 — ab_key.json·manual_review.json 위치",
    )
    parser.add_argument("--manifest", type=Path, default=_MANIFEST_DEFAULT)
    parser.add_argument(
        "--manual-review", type=Path, default=None, help="기본: <ab-run>/manual_review.json"
    )
    parser.add_argument(
        "--out", type=Path, default=None, help="기본: <ab-run(없으면 첫 fast-run)>/verdict_final.md"
    )
    args = parser.parse_args()

    fast_runs: list[Path] = args.fast_run or []
    if not fast_runs and args.ab_run is None:
        parser.error("--fast-run 또는 --ab-run 중 최소 하나는 필요합니다")

    docs = json.loads(args.manifest.read_text(encoding="utf-8"))["documents"]
    fast_candidates = build_fast_candidates(fast_runs, docs)

    manual: ManualReview | None = None
    ab_key: dict[str, dict[str, str]] | None = None
    quality_candidates: list[QualityCandidate] = []
    if args.ab_run is not None:
        manual = load_manual_review(args.manual_review or args.ab_run / "manual_review.json")
        ab_key = load_ab_key(args.ab_run / "ab_key.json")
        quality_candidates = build_quality_candidates(args.ab_run, manual)

    verdict = decide(
        fast_candidates,
        quality_candidates,
        ab_results=(manual.ab_results or None) if manual else None,
        ab_key=ab_key,
    )

    text = render_verdict_text(verdict)
    out = args.out or (args.ab_run or fast_runs[0]) / "verdict_final.md"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(text, encoding="utf-8")
    print(text)
    print(f"저장: {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
