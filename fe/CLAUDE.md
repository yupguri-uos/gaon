# CLAUDE.md — fe (Flutter 앱)

> fe/ 안에서 작업할 때 루트 CLAUDE.md에 추가로 적용되는 FE 규칙.

## 구조
lib/models/   shared-schema Dart 미러(schema.dart) + 표시 라벨(display.dart)
lib/data/     GaonRepository 인터페이스 · MockRepository · demo_data · locator
lib/theme/    디자인 토큰 (GaonColors · GaonType · GaonSpace · GaonRadius · GaonShadow)
lib/widgets/  공용 컴포넌트 (BiText · GaonButton · SurfaceCard 등)
lib/screens/  화면 (v2 시안: 5 Flows · 15 Screens)

## 규칙
- **데이터 접근은 GaonRepository 인터페이스만.** 화면에서 mock/demo 데이터 직접 import 금지
  (예외: schema에 없는 UI 전용 데모 — 교사 목록·학교명 — 는 주석으로 표시).
  BE 연동 = lib/data/locator.dart에서 MockRepository → ApiRepository 교체. 화면 코드 무변경이 원칙.
- **models/schema.dart는 shared-schema의 1:1 미러.** 필드·값 임의 추가 금지.
  변경은 SSOT → schema.py → schema.dart 순. JSON은 snake_case, date는 'yyyy-MM-dd',
  enum wire 문자열은 Pydantic Literal과 동일해야 함 (test/models/schema_test.dart가 검증).
- **색·크기 하드코딩 금지** — theme/tokens.dart의 토큰만 사용. 시안에만 있는 일회성 색은 예외로 인라인 허용.
- **이중언어**: 주 텍스트 + 병기(작게, textSecondary). 고정 높이 금지 — 베트남어는 길고 성조 기호가 있다.
- **데모 데이터는 data/demo_data.dart에만.** 화면에 시나리오 문자열 하드코딩 금지.
- D-day 등 날짜 계산 기준일은 `repository.now()` — DateTime.now() 직접 사용 금지(데모 기준일 6/10 고정).
- Chain B(교사 메시지)는 생성·복사·공유까지만. 전송 버튼 금지(제품 결정, 루트 CLAUDE.md 참조).

## schema보다 앞서간 UI (SSOT 결정 대기 — schema 반영 전까지 UI 전용)
- 출신국 필리핀·태국·한국 / 모국어 Filipino·태국어 (schema: VN/CN · vi/zh)
- 교사 목록(문자 받는 사람) (Teacher 엔티티 없음)
- ~~학년 초1~6~~ · ~~학교명~~ → schema 정본 반영 완료(마이그레이션 0007·0009), FE 미러 동기화됨

## BE 연동 (INF 공지 2026-07-08)
- 공개 URL https://gaon.uk — API base는 data/api_config.dart의 gaonApiBase(`https://gaon.uk/api`).
  nginx가 /api 프리픽스를 벗겨 FastAPI로 전달. 로컬 BE는 --dart-define=GAON_API_BASE로 오버라이드.

## 명령
- 실행:   `flutter run --dart-define-from-file=env.json` — **기본이 실서버(API) 모드**.
  env.json(gitignore)에 `{"GAON_API_TOKEN": "BE 발급 토큰"}` 필요. 없으면 인증 오류 화면.
  모의 데이터 실행: `flutter run --dart-define=GAON_USE_API=false`
- 검사:   `flutter analyze`
- 테스트: `flutter test`
