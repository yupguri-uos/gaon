# be — FastAPI 백엔드

오케스트레이터 = 엔드포인트. 호출하는 엔드포인트가 곧 체인(이미지→Chain A, 교사메시지→Chain B). 별도 /orchestrate 없음.

- **엔드포인트 명세**: 노션 SSOT 11절
- **타입**: shared-schema(`../shared`)대로 Pydantic 모델 1:1. ad-hoc dict 금지.
- **비동기**: BackgroundTasks (Celery/Redis 미사용)
- **DB**: PostgreSQL + pgvector, 마이그레이션 Alembic (스키마 SSOT 15절)
- **분담**: 이지수 = 문서/라우팅·캘린더 / 박수빈 = Proactive(스케줄러·푸시)·교사소통·로그· Kakao 인증