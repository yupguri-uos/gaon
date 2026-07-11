# CLAUDE.md — fe (Flutter 앱)

> fe/ 안에서 작업할 때 루트 CLAUDE.md에 추가로 적용되는 FE 규칙.

## 구조
lib/models/   shared-schema Dart 미러(schema.dart) + 표시 라벨(display.dart)
lib/data/     GaonRepository 인터페이스 · ApiRepository(실 BE) · auth_store · ui_placeholders · locator
lib/theme/    디자인 토큰 (GaonColors · GaonType · GaonSpace · GaonRadius · GaonShadow)
lib/widgets/  공용 컴포넌트 (BiText · GaonButton · SurfaceCard 등)
lib/screens/  화면 (v2 시안: 5 Flows · 15 Screens)
test/fakes/   테스트 대역 FakeRepository + 데모 시나리오 픽스처(demo_fixtures)

## 규칙
- **데이터 접근은 GaonRepository 인터페이스만, 구현은 ApiRepository 단일**(locator.dart).
  테스트는 locator의 전역 `repository`를 test/fakes/FakeRepository로 교체해 화면을 격리한다
  — 화면 코드 무변경이 원칙. 앱 번들(lib/)에 목·데모 데이터 금지.
  UI 전용 플레이스홀더(교사 목록 — schema에 없는 개념)만 data/ui_placeholders.dart에, 주석으로 표시.
- **models/schema.dart는 shared-schema의 1:1 미러.** 필드·값 임의 추가 금지.
  변경은 SSOT → schema.py → schema.dart 순. JSON은 snake_case, date는 'yyyy-MM-dd',
  enum wire 문자열은 Pydantic Literal과 동일해야 함 (test/models/schema_test.dart가 검증).
- **색·크기 하드코딩 금지** — theme/tokens.dart의 토큰만 사용. 시안에만 있는 일회성 색은 예외로 인라인 허용.
- **이중언어**: 주 텍스트 + 병기(작게, textSecondary). 고정 높이 금지 — 베트남어는 길고 성조 기호가 있다.
- **데모 시나리오 픽스처는 test/fakes/demo_fixtures.dart에만(테스트 전용).** 화면에 시나리오 문자열 하드코딩 금지.
- D-day 등 날짜 계산 기준일은 `repository.now()` — DateTime.now() 직접 사용 금지
  (ApiRepository는 DateTime.now(), FakeRepository는 데모 기준일 6/10 고정).
- Chain B(교사 메시지)는 생성·복사·공유까지만. 전송 버튼 금지(제품 결정, 루트 CLAUDE.md 참조).

## schema보다 앞서간 UI (SSOT 결정 대기 — schema 반영 전까지 UI 전용)
- 출신국 필리핀·태국·한국 / 모국어 Filipino·태국어 (schema: VN/CN · vi/zh)
- 교사 목록(문자 받는 사람) (Teacher 엔티티 없음 — data/ui_placeholders.dart)
- ~~학년 초1~6~~ · ~~학교명~~ → schema 정본 반영 완료(마이그레이션 0007·0009), FE 미러 동기화됨

## BE 연동 (INF 공지 2026-07-08)
- 공개 URL https://gaon.uk — API base는 data/api_config.dart의 gaonApiBase(`https://gaon.uk/api`).
  nginx가 /api 프리픽스를 벗겨 FastAPI로 전달. 로컬 BE는 --dart-define=GAON_API_BASE로 오버라이드.

## 명령
- 실행:   `flutter run -d chrome` (웹) / `open -a Simulator && flutter run` (iOS)
- 검사:   `flutter analyze`
- 테스트: `flutter test`
