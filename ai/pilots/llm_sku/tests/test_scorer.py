"""채점기 회귀 테스트 — 순수 함수만, 실 API 없음 (§6).

정답/누락/환각/정규화 케이스를 고정 입력으로 검증한다.
실행: pytest ai/pilots/llm_sku/tests
"""

from datetime import date

import pytest
from gaon_shared import AmountItem, DateItem, ExtractedItem

from eval.scorer import normalize_supply, score_document

GOLD = {
    "doc_type": "notice",
    "deadline": "2026-07-05",
    "requires_reply": True,
    "dates": ["2026-07-10"],
    "amounts": [15000],
    "supplies": ["도시락", "물통", "돗자리"],
}


def _item(**overrides) -> ExtractedItem:
    base: dict = dict(
        doc_type="notice",
        title="현장체험학습 안내",
        dates=[DateItem(label="행사일", date=date(2026, 7, 10))],
        amounts=[AmountItem(label="참가비", value=15000)],
        supplies=["도시락", "물통", "돗자리"],
        deadline=date(2026, 7, 5),
        requires_reply=True,
        raw_text="현장체험학습 안내 원문",
    )
    base.update(overrides)
    return ExtractedItem(**base)


def test_perfect_output_has_zero_critical_misses():
    s = score_document("001", _item(), GOLD)
    assert s.critical_misses == 0
    assert s.hallucination_count == 0
    assert s.doc_type_match and s.deadline_match and s.requires_reply_match
    assert s.supplies.recall == 1.0 and s.supplies.precision == 1.0


def test_date_label_is_ignored():
    s = score_document(
        "001", _item(dates=[DateItem(label="아무라벨", date=date(2026, 7, 10))]), GOLD
    )
    assert s.dates.hits == ["2026-07-10"]
    assert s.dates.missing == [] and s.dates.hallucinated == []


def test_missing_date_and_amount_are_critical():
    s = score_document("001", _item(dates=[], amounts=[]), GOLD)
    assert s.dates.missing == ["2026-07-10"]
    assert s.amounts.missing == ["15000"]
    assert s.critical_misses == 2


def test_hallucinated_date_and_amount_are_critical_and_counted():
    s = score_document(
        "001",
        _item(
            dates=[
                DateItem(label="행사일", date=date(2026, 7, 10)),
                DateItem(label="없는날짜", date=date(2026, 7, 20)),
            ],
            amounts=[
                AmountItem(label="참가비", value=15000),
                AmountItem(label="없는금액", value=99999),
            ],
        ),
        GOLD,
    )
    assert s.dates.hallucinated == ["2026-07-20"]
    assert s.amounts.hallucinated == ["99999"]
    assert s.hallucination_count == 2
    assert s.critical_misses == 2


def test_deadline_null_matches_null():
    gold = {**GOLD, "deadline": None, "requires_reply": False}
    s = score_document("001", _item(deadline=None, requires_reply=False), gold)
    assert s.deadline_match and s.requires_reply_match
    assert s.critical_misses == 0


def test_deadline_and_reply_mismatch_are_critical():
    s = score_document("001", _item(deadline=date(2026, 7, 6), requires_reply=False), GOLD)
    assert not s.deadline_match and not s.requires_reply_match
    assert s.critical_misses == 2


def test_amount_int_float_equivalence():
    s = score_document("001", _item(amounts=[AmountItem(label="참가비", value=15000.0)]), GOLD)
    assert s.amounts.missing == [] and s.amounts.hallucinated == []


def test_supply_normalization_and_substring_match():
    # '물 통'(내부 공백) → '물통'으로 정규화, '점심 도시락'은 '도시락'을 부분문자열로 포함
    s = score_document("001", _item(supplies=["점심 도시락", "물 통"]), GOLD)
    assert s.supplies.hits == ["도시락", "물통"]
    assert s.supplies.missing == ["돗자리"]
    assert s.supplies.recall == pytest.approx(2 / 3)
    assert s.supplies.precision == 1.0


def test_supply_precision_penalizes_extras_but_not_critical():
    s = score_document("001", _item(supplies=["도시락", "물통", "돗자리", "우산"]), GOLD)
    assert s.supplies.recall == 1.0
    assert s.supplies.precision == pytest.approx(3 / 4)
    assert s.critical_misses == 0  # supplies는 크리티컬 미스에 포함되지 않는다(§6)


def test_empty_gold_or_output_supplies_are_not_applicable():
    gold = {**GOLD, "supplies": []}
    s = score_document("001", _item(supplies=[]), gold)
    assert s.supplies.recall is None and s.supplies.precision is None


def test_normalize_supply():
    assert normalize_supply("  물 통 ") == "물통"
    assert normalize_supply("도시락") == "도시락"
