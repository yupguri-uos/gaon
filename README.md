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
- 셋업: `.env.example` → `.env` 복사 후 값 채우기

### 로컬 개발 셋업 (Python: shared·ai)
설치 순서가 중요하다 — `gaon-ai`가 `gaon-shared`에 의존하므로 shared를 먼저 설치한다.

```bash
# 런타임
pip install -e shared/python && pip install -e ai
# 개발(테스트·린트 도구 포함)
pip install -e shared/python && pip install -e "ai[dev]"

python -c "import gaon_shared, gaon_ai"   # import 경로 확인(성공해야 함)
pytest                                    # 테스트(루트에서, asyncio_mode=auto)
ruff check . && black --check .           # 린트·포맷 검사
```