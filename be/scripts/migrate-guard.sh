#!/usr/bin/env bash
# GAON migrate 가드
# - pending 마이그레이션에 "데이터 파괴 DDL"이 있으면 CONFIRM_DESTRUCTIVE=1 없이는 upgrade를 막는다.
# - deploy.sh 와 compose up(재부팅 자가복구) 양쪽이 이 스크립트를 타므로, 어느 경로로도 우회 불가.
# - 안전(additive/CHECK 교체 등)한 마이그레이션은 그냥 통과 → 기본 자동, 위험한 것만 게이트.
set -euo pipefail
cd /app

# 현재 배포된 리비전 (빈 DB면 공백)
CUR="$(alembic current 2>/dev/null | grep -oE '^[0-9a-zA-Z_]+' | head -1 || true)"

if [ -n "$CUR" ]; then
  HITS="$(python /app/scripts/scan_destructive.py "$CUR" || true)"
  if [ -n "$HITS" ] && [ "${CONFIRM_DESTRUCTIVE:-0}" != "1" ]; then
    echo "=============================================================="
    echo " ⛔ 차단: 데이터 파괴 가능성이 있는 마이그레이션이 대기 중입니다."
    echo "    대상 리비전: $HITS"
    echo "    내용을 검토한 뒤, 확인했다면 CONFIRM_DESTRUCTIVE=1 로 재실행하세요."
    echo "    예)  CONFIRM_DESTRUCTIVE=1 bash infra/deploy.sh"
    echo "=============================================================="
    exit 3
  fi
fi

echo "[migrate-guard] upgrade head 실행 (current=${CUR:-none})"
alembic upgrade head
alembic current
