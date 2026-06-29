# CLAUDE.md — GAON

> Claude Code가 이 repo에서 작업할 때마다 자동으로 읽는 상시 규칙 파일.
> 기획·통계·피칭·결정 배경은 노션 SSOT "GAON 개발 계획"에 있고 여기엔 두지 않는다.
> (Claude Code는 노션을 못 본다. 코딩에 필요한 것만 이 repo 안에 있어야 한다.)

## 프로젝트
GAON: 한국어가 익숙치 않은 이주배경 학부모가 학교 문서(알림장·가정통신문)를
이해하고 *필요한 행동까지* 끝내도록 돕는 능동형 AI 에이전트. 슬로건 Translation → Action.
데모지만 실서비스에 최대한 가깝게 만든다. **범위는 MVP, 품질·구조는 production-shaped.**

## 스택
- FE: Flutter (워크플로우: Figma Make → React → Flutter 변환), 다국어 ko 병기 + vi/zh
- BE: FastAPI(Python) + Pydantic, 비동기는 BackgroundTasks (Celery/Redis 미사용)
- DB: PostgreSQL + pgvector, 마이그레이션 Alembic
- AI: 멀티모달 LLM 단일 호출(이미지→구조화 JSON) + RAG(pgvector), 한 모델 패밀리
- 인증: Kakao OAuth   /   인프라: 미니PC(Linux·SSH) + 외부 터널, 이미지 저장 MinIO(S3 호환)

## 구조 (monorepo)
/fe       Flutter 앱
/be       FastAPI (오케스트레이터 = 엔드포인트 자체)
/ai       에이전트 4종 + RAG 파이프라인
/shared   shared-schema — FE·BE·AI 공통 타입의 단일 출처
/infra    배포·터널·DB 설정
(폴더별 추가 규칙이 필요하면 해당 폴더에 nested CLAUDE.md를 둔다)

## shared-schema — 가장 중요
- 모든 FE·BE·AI 인터페이스는 /shared 타입을 따른다. ad-hoc dict 주고받기 금지.
- 타입 변경 순서: **노션 SSOT → /shared → 코드.** 코드에서 필드 임의 추가 금지.
- 핵심 타입: UserProfile, Document, ExtractedItem, TranslatedContent,
  ActionCard, TeacherMessage, Notification, ActivityLog, AgentResponse<T>.

## 아키텍처 규칙
- 라우팅은 추론하지 않는다. UI 동작이 체인을 정한다:
  이미지 업로드 → Chain A(POST /documents) · 교사 메시지 → Chain B(POST /teacher-message).
  별도 /orchestrate 엔드포인트 없음.
- Chain A: DocParsing → CulturalTranslation(+RAG) → LifestyleAction → (회신 필요 시 초안).
  진행 상태는 Document.status로 노출, FE는 폴링.
- Chain B: TeacherCommunication 단독. **메시지는 생성까지만, 전송은 사용자 수동(복사/공유).**
- Proactive: 스케줄러(배치)+FCM은 체인과 독립. 마감/미회신/행사 스캔 → Notification.

## 컨벤션
- 주석·커밋·PR 설명은 한국어.
- 기능은 SSOT Feature ID로 참조(예: F-DOC-3). 커밋/PR/태스크에 ID 명시.
- Python: 타입 힌트 필수, Pydantic 모델 = shared-schema와 1:1. 포매터 ruff/black.
- DB: uuid PK, timestamptz. enum=안정값(status·situation), text+CHECK=확장값(country/language/grade).
- 비밀키·토큰 커밋 금지. .env + 시크릿 매니저.

## 하지 말 것
- 교사 메시지 자동 전송 기능 추가 금지 (생성까지만 — 제품 결정).
- 음성 입력 / 대화형(음성) 서류작성 / 이커머스 자동결제 — MVP 범위 밖, 구현 금지.
- 통계·피칭 문구를 코드·repo 문서에 박지 말 것 (대회 제출용은 노션).
- shared-schema 우회 금지.
- Claude code 세션에서 Commit 금지. Commit 메시지를 추천받아 본인 터미널에서 직접 커밋할 것.

## 명령  ← P0 셋업 후 실제 값으로 교체
- BE 실행/테스트:  (예) uvicorn app.main:app --reload  /  pytest
- FE 실행:        flutter run
- DB 마이그레이션:  alembic upgrade head

## 참조
- 전체 기획·명세·결정: 노션 SSOT "GAON 개발 계획" (repo 밖, 사람·앱이 관리)
- 변경 순서: SSOT → shared-schema → 코드