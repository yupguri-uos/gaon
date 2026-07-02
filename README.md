# GAON (가온)
이주배경 학부모를 위한 능동형 교육 행정 AI 에이전트

## 구조 (monorepo)
- `fe/` — Flutter 앱
- `be/` — FastAPI (오케스트레이터 = 엔드포인트)
- `ai/` — 에이전트 4종 + RAG 파이프라인
- `shared/` — shared-schema (FE·BE·AI 공통 타입 단일 출처)
- `infra/` — 배포·터널·DB 설정

## 개발
- 상시 규칙: `CLAUDE.md`
- 전체 기획·명세: 노션 SSOT "GAON 개발 계획"
- 셋업: `env.example` → `.env` 복사 후 값 채우기

### 로컬 개발 셋업 (Python: shared·ai·be)
설치 순서가 중요하다 — `gaon-ai`는 `gaon-shared`에, `gaon-be`는 `gaon-shared`·`gaon-ai`에 의존한다.

```bash
# 개발(테스트·린트 도구 포함)
pip install -e shared/python && pip install -e "ai[dev]" && pip install -e "be[dev]"

python -c "import gaon_shared, gaon_ai, app"   # import 경로 확인(성공해야 함)
pytest                                          # 테스트(루트에서, asyncio_mode=auto)
ruff check . && black --check .                 # 린트·포맷 검사
```

### BE 실행 / DB 마이그레이션
`POST /documents`(이미지 업로드)는 MinIO가 로컬에 떠 있어야 한다 — 없으면 500 에러.

```bash
# MinIO(최초 1회 설치 후, 개발 세션마다 별도 터미널에서 계속 띄워둠)
curl -fsSL -o ~/minio https://dl.min.io/server/minio/release/darwin-arm64/minio  # arm64 기준
chmod +x ~/minio
MINIO_ROOT_USER=minioadmin MINIO_ROOT_PASSWORD=minioadmin ~/minio server ~/minio-data --console-address ":9001"
# .env의 S3_ACCESS_KEY·S3_SECRET_KEY를 위 값(minioadmin)으로 채우고, gaon-documents 버킷 생성 필요

cd be
alembic upgrade head             # DB 마이그레이션 적용
uvicorn app.main:app --reload   # http://localhost:8000
```