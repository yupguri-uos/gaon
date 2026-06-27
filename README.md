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