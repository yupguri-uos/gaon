"""리포트/로그 = Memory 결과 (F-LOG-1~2, SSOT §11). activity_events를 이번 달(KST) 기준으로
집계한다. 별도 write 엔드포인트 없음 — 처리 시 자동 누적(§15, documents.py 참고).

event_participated·item_missed는 Proactive(F-PRO)와 엮여있는데 Proactive는 아직 미구현이라
지금은 항상 0으로 나온다 — enum/컬럼은 이미 있으니 Proactive가 그 종류로 이벤트를 쓰기
시작하면 이 엔드포인트는 코드 변경 없이 그대로 집계에 반영된다."""

from __future__ import annotations

from datetime import date, datetime, timedelta
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Depends
from gaon_shared import ActivityLog, WeeklyActivity
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db import get_db
from app.models import ActivityEventRow, User
from app.security import get_current_user

router = APIRouter(tags=["report"])

KST = ZoneInfo("Asia/Seoul")

_KIND_TO_FIELD = {
    "document_processed": "processed_count",
    "event_participated": "event_participation_count",
    "item_missed": "missed_count",
}


def _empty_counts() -> dict[str, int]:
    return {"processed_count": 0, "event_participation_count": 0, "missed_count": 0}


def _month_bounds_kst(today: date) -> tuple[datetime, datetime]:
    start = datetime(today.year, today.month, 1, tzinfo=KST)
    if today.month == 12:
        end = datetime(today.year + 1, 1, 1, tzinfo=KST)
    else:
        end = datetime(today.year, today.month + 1, 1, tzinfo=KST)
    return start, end


@router.get("/report/monthly", response_model=ActivityLog)
def get_monthly_report(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> ActivityLog:
    month_start, month_end = _month_bounds_kst(datetime.now(KST).date())

    rows = (
        db.execute(
            select(ActivityEventRow)
            .where(ActivityEventRow.user_id == current_user.id)
            .where(ActivityEventRow.occurred_at >= month_start)
            .where(ActivityEventRow.occurred_at < month_end)
        )
        .scalars()
        .all()
    )

    totals = _empty_counts()
    weekly: dict[date, dict[str, int]] = {}

    for row in rows:
        field = _KIND_TO_FIELD[row.activity_kind]
        totals[field] += 1

        occurred_date = row.occurred_at.astimezone(KST).date()
        week_start = occurred_date - timedelta(days=occurred_date.weekday())
        bucket = weekly.setdefault(week_start, _empty_counts())
        bucket[field] += 1

    weekly_activity = [
        WeeklyActivity(
            week_start=week_start,
            week_end=week_start + timedelta(days=6),
            processed_count=counts["processed_count"],
            event_participation_count=counts["event_participation_count"],
            missed_count=counts["missed_count"],
        )
        for week_start, counts in sorted(weekly.items())
    ]

    return ActivityLog(
        user_id=str(current_user.id),
        weekly_activity=weekly_activity,
        **totals,
    )
