"""
판정 규칙 적용 (§7 — 사전 등록, 실행 전 고정).

1. 벤더별 크리티컬 미스 총합의 차 ≤ 1 → 근소 → Gemini 채택(기결정 규칙).
2. Claude 채택 조건: 크리티컬 미스가 2개 이상 적음 AND 경어체 블라인드 A/B에서
   열세 아님(무승부 이상).
3. 개수 무관 탈락 사유(체계적 실패): 특정 tag 그룹(2건 이상) 전멸,
   또는 환각 날짜/금액 3건 이상 반복.
4. 규칙 개정이 필요해 보이면 판정을 바꾸지 않고 '개정 필요' 플래그와 사유만 출력
   (개정 결정은 탕지수).
5. vi(베트남어) 해설 품질은 미검증 리스크로 명시.

A/B는 블라인드 수동 평가라 하네스가 자동 판정할 수 없다 — 기본값 'pending'으로
잠정 판정을 내고, 평가 완료 후 규칙 2의 확정 조건을 사람이 적용한다.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Literal

from eval.scorer import DocScore

ABOutcome = Literal["pending", "claude_not_worse", "claude_worse"]


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
    provisional: bool  # A/B 대기 등으로 잠정 여부
    rationale: list[str]
    revision_needed: bool = False  # §7-4
    risks: list[str] = field(default_factory=list)


def systematic_failures(stats: VendorStats) -> list[str]:
    """§7-3 체계적 실패 탐지. 판정 근거 문장 목록을 돌려준다(비면 해당 없음)."""
    reasons: list[str] = []
    by_tag: dict[str, list[DocScore]] = {}
    for ds in stats.doc_scores:
        for tag in stats.tags_by_doc.get(ds.doc_id, []):
            by_tag.setdefault(tag, []).append(ds)
    for tag, group in sorted(by_tag.items()):
        # 같은 tag 문서 2건 이상 전부에서 크리티컬 미스(또는 파싱 실패) 발생 → 전멸
        if len(group) >= 2 and all(
            d.critical_misses > 0 or d.doc_id in stats.failed_docs for d in group
        ):
            reasons.append(f"tag '{tag}' 그룹 전멸({len(group)}건 전부 크리티컬 미스)")
    if stats.total_hallucination >= 3:
        reasons.append(f"환각 날짜/금액 {stats.total_hallucination}건(≥3) 반복")
    return reasons


def decide(
    gemini: VendorStats | None,
    claude: VendorStats | None,
    ab: ABOutcome = "pending",
) -> Verdict:
    """§7 규칙을 순서대로 적용해 (잠정) 판정을 돌려준다."""
    risks = [
        "vi(베트남어) 해설 품질은 미검증 리스크 — A/B 결과와 별개로 vi 출력 원문을 "
        "육안 점검할 것(§7-5, ab_pairs.md 참조)."
    ]
    if gemini is None or claude is None:
        present = gemini or claude
        who = present.vendor if present else "없음"
        return Verdict(
            winner=None,
            provisional=True,
            rationale=[f"한쪽 벤더만 실행됨({who}) — 비교 판정 불가(스모크 실행)."],
            risks=risks,
        )

    g_total, c_total = gemini.total_critical, claude.total_critical
    g_sys, c_sys = systematic_failures(gemini), systematic_failures(claude)
    rationale = [
        f"크리티컬 미스 총합: gemini={g_total}, claude={c_total} (차={abs(g_total - c_total)})",
        f"환각(날짜+금액): gemini={gemini.total_hallucination}, "
        f"claude={claude.total_hallucination}",
        f"파싱 실패: gemini={len(gemini.failed_docs)}건, claude={len(claude.failed_docs)}건",
    ]
    for vendor, reasons in (("gemini", g_sys), ("claude", c_sys)):
        rationale += [f"[체계적 실패] {vendor}: {r}" for r in reasons]

    # §7-3: 체계적 실패는 개수 무관 탈락
    if g_sys and c_sys:
        return Verdict(
            winner=None,
            provisional=True,
            rationale=rationale + ["두 벤더 모두 체계적 실패 — 현행 규칙으로 판정 불가."],
            revision_needed=True,  # §7-4: 판정 대신 개정 필요 플래그
            risks=risks,
        )
    if g_sys:
        return Verdict(
            winner="claude",
            provisional=False,
            rationale=rationale + ["Gemini 체계적 실패 → 개수 무관 탈락, Claude 채택(§7-3)."],
            risks=risks,
        )
    if c_sys:
        return Verdict(
            winner="gemini",
            provisional=False,
            rationale=rationale + ["Claude 체계적 실패 → 개수 무관 탈락, Gemini 채택(§7-3)."],
            risks=risks,
        )

    # §7-2: Claude 채택 조건(2개 이상 적음 AND A/B 열세 아님)
    if g_total - c_total >= 2:
        if ab == "claude_not_worse":
            return Verdict(
                winner="claude",
                provisional=False,
                rationale=rationale
                + ["Claude 크리티컬 미스 2개 이상 적음 + A/B 열세 아님 → Claude 채택(§7-2)."],
                risks=risks,
            )
        if ab == "pending":
            return Verdict(
                winner="claude",
                provisional=True,
                rationale=rationale
                + [
                    "Claude 크리티컬 미스 2개 이상 적음 — A/B(블라인드) 평가 대기(§7-2). "
                    "열세 아님 확인 시 Claude 확정, 열세면 Gemini."
                ],
                risks=risks,
            )
        return Verdict(
            winner="gemini",
            provisional=False,
            rationale=rationale
            + ["Claude가 2개 이상 적지만 A/B 열세 → 기본값 Gemini 채택(§7-1 기결정)."],
            risks=risks,
        )

    # §7-1: 차 ≤ 1(근소) 또는 Gemini 우세 → Gemini
    return Verdict(
        winner="gemini",
        provisional=False,
        rationale=rationale + ["차 ≤ 1(근소) 또는 Gemini 우세 → Gemini 채택(§7-1 기결정)."],
        risks=risks,
    )
