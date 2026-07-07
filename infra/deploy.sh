#!/usr/bin/env bash
# GAON 배포 — 미니PC에서 실행. repo clone 위치의 /infra 안에서 돌린다.
# 전제: /infra/.env 가 이미 있어야 함(.env.example 복사 후 값 채움, 커밋 금지).
#       tailnet·Docker는 이미 떠 있음(인계 완료).
set -euo pipefail
cd "$(dirname "$0")"                 # /infra 로 이동

if [ ! -f .env ]; then
  echo "ERROR: /infra/.env 없음. 'cp .env.example .env' 후 값 채우고 다시 실행." >&2
  exit 1
fi

echo "== 1) git pull =="
git -C .. pull --ff-only

echo "== 2) build =="
docker compose build

echo "== 3) migrate + up (migrate가 alembic upgrade head 후 app 기동) =="
docker compose up -d

echo "== 4) status =="
docker compose ps

cat <<'EOF'

완료. 검증:
  docker compose logs migrate           # alembic upgrade 결과
  docker exec -it gaon-postgres-1 psql -U gaon -d gaon -c '\dt'   # 테이블
  sudo ss -tlnp | grep -E '5432|8000|9000|9001'                  # tailnet IP 바인딩 확인
  curl -s http://gaon-minipc:8000/health || echo '(헬스 엔드포인트 없으면 무시)'
EOF
