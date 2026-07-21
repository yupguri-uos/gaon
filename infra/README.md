# GAON 인프라 (infra)

GAON 백엔드 스택을 미니PC 한 대에서 운영하기 위한 배포·네트워크·데이터베이스 설정입니다. 이 폴더가 배포 정본이며, 호스트는 이 저장소를 clone한 뒤 `infra/`에서 스택을 실행합니다. 데이터는 named volume로 관리되어 clone 위치와 무관하게 영속됩니다.

## 구성

- 위치/운영: 온프레미스 미니PC 1대 상시 호스팅, 100% 원격 운영 + 현장 remote hands 병행
- 네트워크: 팀 내부 접속은 Tailscale(비공개), 공개 백엔드는 Cloudflare Tunnel. 둘 다 아웃바운드 연결이라 포트포워딩이 필요 없습니다.
- 스토리지/DB: 이미지 저장 MinIO(S3 호환), PostgreSQL + pgvector, 마이그레이션은 Alembic
- 푸시: FCM
- 자동복구: 백엔드·DB·Tailscale·cloudflared를 모두 systemd로 자동 기동하고, BIOS 설정으로 정전 후 자동 부팅합니다.

## 기술 스택

- Docker Compose, Dockerfile (FastAPI 이미지)
- PostgreSQL 16 + pgvector
- MinIO (S3 호환 객체 스토리지)
- nginx (리버스 프록시)
- Cloudflare Tunnel, Tailscale
- Alembic (DB 마이그레이션)

## 파일 구성

```
infra/
  docker-compose.yml         데이터층(postgres+pgvector, minio) + migrate + app
  Dockerfile                 FastAPI(be) 이미지 — shared → ai → be 순 설치
  deploy.sh                  git pull → build → migrate → up
  .env.example               배포용 env 템플릿 (compose 인프라 키 + 앱 키 병합)
  db/init/01-extensions.sql  pgvector 확장 생성 (최초 1회)
```

시크릿을 담는 `.env`는 `.gitignore` 처리되어 커밋되지 않습니다. 이전에는 `/opt/gaon`에 ad-hoc 파일로 두던 방식이었으나, 저장소 관리 방식으로 이관했습니다.

## 실행 방법

호스트(미니PC)에서 다음 순서로 배포합니다.

1. 저장소를 clone하고 infra 폴더로 이동합니다.

```bash
git clone <repo-url> /opt/gaon && cd /opt/gaon/infra
```

2. env 템플릿을 복사해 값을 채웁니다. 비밀번호·키·`TAILNET_IP`를 입력합니다.

```bash
cp .env.example .env && nano .env
```

3. 배포 스크립트를 실행합니다.

```bash
./deploy.sh
```

`migrate` 단계가 `alembic upgrade head`(0001–0003)를 적용한 뒤 `app`이 기동됩니다. 배포 스크립트는 pull → build → 백업 → 가드 마이그레이션 → 기동 → 헬스체크 순으로 진행됩니다.

## 검증

배포 후 다음 명령으로 상태를 확인합니다.

```bash
docker compose ps
docker compose logs migrate
docker exec -it gaon-postgres-1 psql -U gaon -d gaon -c '\dt'
sudo ss -tlnp | grep -E '5432|8000|9000|9001'   # tailnet IP 바인딩 확인
```

## 주의사항

- 컨테이너 내부 호스트명을 사용합니다. `DATABASE_URL`의 host는 `postgres`, `S3_ENDPOINT`는 `http://minio:9000`입니다(localhost 아님).
- compose의 `env_file`은 `${}` 확장을 하지 않습니다. `.env`의 `DATABASE_URL`·S3 키에는 실제 값을 직접 적고, `POSTGRES_*`·`MINIO_*` 값과 수기로 일치시켜야 합니다.
- 포트는 tailnet IP 전용으로 바인딩됩니다. 공개 노출은 cloudflared 터널이 담당합니다.
- `migrate`는 `app`보다 먼저 1회만 실행됩니다(`service_completed_successfully`). 실패하면 `app`이 기동되지 않습니다(의도된 동작).
- `LLM_API_KEY`가 비어 있어도 배포는 됩니다. 인증·업로드·DB는 정상 동작하고 AI 체인만 미동작합니다.
