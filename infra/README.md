# infra — 배포 · 네트워크 · DB

미니PC 기반 배포. 자세한 운영 노트는 노션 "개발" 페이지 인프라 섹션.

- **위치/운영**: 미니PC = 이태권 집 → 손수빈 100% 원격, 이태권 remote hands
- **네트워크**: 팀 접속 = Tailscale(비공개) / 공개 백엔드 = Cloudflare Tunnel. 둘 다 아웃바운드(포트포워딩 불필요).
- **스토리지/DB**: 이미지 MinIO(S3 호환), PostgreSQL + pgvector, 마이그레이션 Alembic
- **푸시**: FCM
- **자동복구**: 백엔드·DB·Tailscale·cloudflared 전부 systemd 자동기동 + BIOS 정전 후 자동부팅

> 시크릿은 `.env`(커밋 금지) / `.env.example` 템플릿 참조. 배포 스크립트·설정파일은 이 폴더.

---

## 배포 (repo-managed)

이 폴더가 **배포 정본**이다. 미니PC는 이 repo를 clone 후 `/infra`에서 실행한다.
(이전 `/opt/gaon` ad-hoc 파일 방식 → repo 관리로 이관. 데이터는 named volume로 영속.)

### 파일
```
infra/
  docker-compose.yml         # 데이터층(postgres+pgvector, minio) + migrate + app
  Dockerfile                 # FastAPI(be) 이미지 — shared→ai→be 순 설치
  deploy.sh                  # git pull → build → migrate → up
  .env.example               # 배포용 env 템플릿 (compose 인프라 키 + 앱 키 병합)
  db/init/01-extensions.sql  # pgvector 확장(최초 1회)
```
`.env`(시크릿)는 `.gitignore` 처리됨 — 커밋 금지.

### 절차
```bash
# 미니PC
git clone <repo-url> /opt/gaon && cd /opt/gaon/infra
cp .env.example .env && nano .env      # 비번·키·TAILNET_IP 채움
./deploy.sh
```
`migrate`가 `alembic upgrade head`(0001–0003)를 적용한 뒤 `app` 기동.

### 검증
```bash
docker compose ps
docker compose logs migrate
docker exec -it gaon-postgres-1 psql -U gaon -d gaon -c '\dt'
sudo ss -tlnp | grep -E '5432|8000|9000|9001'   # tailnet IP 바인딩 확인
```

### 주의
- **컨테이너 내부 호스트명**: DATABASE_URL host=`postgres`, S3_ENDPOINT=`http://minio:9000` (localhost 아님).
- **env_file은 ${} 확장 안 함** → `.env`의 DATABASE_URL·S3 키는 실제 값을 직접 적고 POSTGRES_*/MINIO_* 와 수기 일치.
- **포트는 tailnet IP 전용** 바인딩. 공개 노출은 본가 cloudflared 담당.
- **migrate는 app보다 먼저·1회만**(`service_completed_successfully`). 실패 시 app 안 뜸(의도).
- **LLM_API_KEY 비어도 배포는 뜸** — auth·업로드·DB는 동작, AI 체인만 미동작(결정 #4 대기).