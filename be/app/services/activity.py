import logging
import uuid
from datetime import datetime, timezone
from typing import Literal

from app.db import SessionLocal
from app.models.activity import ActivityEventRow

logger = logging.getLogger(__name__)

ActivityKind = Literal[
    "document_processed",
    "event_participated",
    "item_missed",
]


def log_activity(
    user_id: uuid.UUID,
    activity_kind: ActivityKind,
    related_id: uuid.UUID | None = None,
    occurred_at: datetime | None = None,
) -> None:
    """
    append-only activity log

    BackgroundTasks 진입점이므로,
    기록 실패가 메인 흐름에 영향을 주면 안 된다.
    """

    db = SessionLocal()

    try:
        row = ActivityEventRow(
            user_id=user_id,
            activity_kind=activity_kind,
            related_id=related_id,
            occurred_at=occurred_at or datetime.now(timezone.utc),
        )
        db.add(row)
        db.commit()

    except Exception:
        db.rollback()
        logger.exception(
            "activity 기록 실패: user_id=%s, activity_kind = %s, related_id = %s",
            user_id,
            activity_kind,
            related_id,
        )
    finally:
        db.close()
