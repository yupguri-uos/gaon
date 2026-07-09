#!/usr/bin/env bash
# GAON 미니PC 배포 스크립트
#   pull → build → backup → (가드된) migrate → up → health
# 순서 강제로 "호스트 git pull만 하고 이미지 재빌드를 빠뜨려 마이그레이션이 조용히 no-op" 함정을 차단한다.
# 파괴적 마이그레이션은 migrate-guard 가 CONFIRM_DESTRUCTIVE=1 없이 막는다.
#
# 사용:
#   bash infra/deploy.sh                      # 평상시
#   CONFIRM_DESTRUCTIVE=1 bash infra/deploy.sh # 파괴적 변경을 검토·승인한 경우만
set -euo pipefail

REPO="${GAON_REPO:-/opt/gaon}"
INFRA="$REPO/infra"
HEALTH_URL="${GAON_HEALTH_URL:-https://gaon.uk/_ok}"
BACKUP_DIR="${GAON_BACKUP_DIR:-$HOME/gaon-backups}"

echo "== 1/5 코드 최신화 =="
cd "$REPO"
git fetch origin
git checkout main
git pull --ff-only origin main
echo "HEAD $(git rev-parse --short HEAD)"

echo "== 2/5 이미지 재빌드 (호스트 pull만으론 컨테이너에 반영 안 됨) =="
cd "$INFRA"
docker compose build

echo "== 3/5 DB 백업 (마이그레이션 전 필수) =="
mkdir -p "$BACKUP_DIR"
BACKUP="$BACKUP_DIR/gaon_$(date +%Y%m%d_%H%M%S).sql"
docker compose exec -T postgres pg_dump -U gaon gaon > "$BACKUP"
echo "backup → $BACKUP"

echo "== 4/5 마이그레이션 (파괴적 변경 가드) =="
# CONFIRM_DESTRUCTIVE 는 호출자 환경값을 그대로 migrate 컨테이너로 전달.
if ! docker compose run --rm -e CONFIRM_DESTRUCTIVE="${CONFIRM_DESTRUCTIVE:-0}" migrate; then
  echo "!! 마이그레이션 중단(파괴적 변경 가드 또는 오류). 위 메시지를 확인하세요." >&2
  exit 1
fi

echo "== 5/5 재기동 + 헬스체크 =="
docker compose up -d
sleep 3
if curl -fsS "$HEALTH_URL" >/dev/null; then
  echo "✅ DEPLOY OK  ($HEALTH_URL)"
else
  echo "!! HEALTH FAIL: $HEALTH_URL 응답 없음" >&2
  exit 1
fi