import 'api_repository.dart';
import 'repository.dart';

/// 전역 저장소 인스턴스 — 구현은 ApiRepository(실 BE, gaon.uk/api) 단일.
///
/// Kakao 로그인(F-ON-3)이 토큰을 주입하므로 별도 플래그 없이 실서버로 동작한다.
/// 앱 번들에 목·데모 데이터 없음(팀 결정: API 단일화).
/// 테스트는 이 전역을 test/fakes/FakeRepository로 갈아끼워 화면을 격리한다.
GaonRepository repository = ApiRepository();
