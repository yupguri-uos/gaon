"""라우터 공용 응답 모델 — 개별 라우터에 중복 정의하지 말고 여기서 가져다 쓴다."""

from __future__ import annotations

from pydantic import BaseModel


class OkResponse(BaseModel):
    """부수효과만 있는 엔드포인트의 형식적 확인 응답: {"ok": true}."""

    ok: bool = True
