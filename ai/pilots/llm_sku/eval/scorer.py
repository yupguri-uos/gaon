"""
채점기 — 순수 함수만(실 API 없음). tests/test_scorer.py로 회귀 고정 (§6).

필드별 규칙(모두 골드 기준):
- deadline: 정확 일치(둘 다 null 포함해 비교).
- requires_reply: bool 일치.
- dates: 골드의 각 date가 출력 dates[].date 집합에 존재하면 hit(라벨 무시).
  출력에는 있으나 골드에 없는 date는 '환각'으로 별도 카운트.
- amounts: value 집합 비교(라벨 무시) + 환각 금액 카운트. int/float 동치(15000 == 15000.0).
- supplies: 정규화(strip·내부 공백 제거) 후, 골드 항목이 출력 항목 중 하나에
  부분문자열로 포함되면 hit. 집합 recall/precision 둘 다 기록. (크리티컬 미스 미포함)
- doc_type: 일치 여부만 기록. (크리티컬 미스 미포함)
- title·raw_text·checkboxes: 자동 채점 제외 — 리포트에 원문 병기(수동 검토).

크리티컬 미스 = deadline 불일치(1) + requires_reply 불일치(1)
             + dates 누락 각 1 + dates 환각 각 1 + amounts 동일.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

from gaon_shared import ExtractedItem


@dataclass
class SetScore:
    """집합 비교 결과(dates·amounts 공용). 값은 표시용 문자열."""

    hits: list[str] = field(default_factory=list)
    missing: list[str] = field(default_factory=list)  # 골드에 있으나 출력에 없음(누락)
    hallucinated: list[str] = field(default_factory=list)  # 출력에 있으나 골드에 없음(환각)


@dataclass
class SupplyScore:
    hits: list[str] = field(default_factory=list)  # 매칭된 골드 항목
    missing: list[str] = field(default_factory=list)  # 매칭 안 된 골드 항목
    recall: float | None = None  # 골드가 비어 있으면 None(N/A)
    precision: float | None = None  # 출력이 비어 있으면 None(N/A)


@dataclass
class DocScore:
    doc_id: str
    doc_type_match: bool
    deadline_match: bool
    requires_reply_match: bool
    dates: SetScore
    amounts: SetScore
    supplies: SupplyScore
    critical_misses: int
    hallucination_count: int  # dates+amounts 환각 합 — 판정 규칙 §7-3용


def normalize_supply(s: str) -> str:
    """strip + 내부 공백 전부 제거 — '물 통'과 '물통'을 같게 본다."""
    return "".join(s.split())


def _score_set(gold: list[str], output: list[str]) -> SetScore:
    gold_set, out_set = set(gold), set(output)
    return SetScore(
        hits=sorted(gold_set & out_set),
        missing=sorted(gold_set - out_set),
        hallucinated=sorted(out_set - gold_set),
    )


def _fmt_amount(v: Any) -> str:
    # 15000과 15000.0을 같은 표기('15000')로 정규화해 집합 비교
    return f"{float(v):g}"


def _score_supplies(gold: list[str], output: list[str]) -> SupplyScore:
    gold_norm = [(g, normalize_supply(g)) for g in gold]
    out_norm = [normalize_supply(o) for o in output]
    hits = [g for g, gn in gold_norm if any(gn in on for on in out_norm)]
    missing = [g for g, gn in gold_norm if not any(gn in on for on in out_norm)]
    matched_out = sum(1 for on in out_norm if any(gn in on for _, gn in gold_norm))
    return SupplyScore(
        hits=hits,
        missing=missing,
        recall=len(hits) / len(gold) if gold else None,
        precision=matched_out / len(output) if output else None,
    )


def score_document(doc_id: str, output: ExtractedItem, gold: dict[str, Any]) -> DocScore:
    """문서 1건 채점. gold는 manifest.json의 gold 객체(§5)."""
    deadline_out = output.deadline.isoformat() if output.deadline else None
    deadline_match = deadline_out == gold.get("deadline")
    requires_reply_match = output.requires_reply == gold.get("requires_reply", False)
    dates = _score_set(
        [str(d) for d in gold.get("dates", [])],
        [d.date.isoformat() for d in output.dates],
    )
    amounts = _score_set(
        [_fmt_amount(v) for v in gold.get("amounts", [])],
        [_fmt_amount(a.value) for a in output.amounts],
    )
    supplies = _score_supplies(list(gold.get("supplies", [])), list(output.supplies))
    hallucination_count = len(dates.hallucinated) + len(amounts.hallucinated)
    critical = (
        (0 if deadline_match else 1)
        + (0 if requires_reply_match else 1)
        + len(dates.missing)
        + len(amounts.missing)
        + hallucination_count
    )
    return DocScore(
        doc_id=doc_id,
        doc_type_match=output.doc_type == gold.get("doc_type"),
        deadline_match=deadline_match,
        requires_reply_match=requires_reply_match,
        dates=dates,
        amounts=amounts,
        supplies=supplies,
        critical_misses=critical,
        hallucination_count=hallucination_count,
    )
