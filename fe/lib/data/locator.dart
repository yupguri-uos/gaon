import 'api_repository.dart';
import 'mock_repository.dart';
import 'repository.dart';

/// 전역 저장소 인스턴스.
///
/// 기본 = MockRepository(데모 데이터). 실 BE(gaon.uk/api) 연동 실행:
///   flutter run --dart-define=GAON_USE_API=true \
///               --dart-define=GAON_API_TOKEN=(BE 발급 토큰)
/// Kakao 로그인(F-ON-3)이 붙으면 토큰은 로그인 플로우가 주입하고
/// GAON_USE_API=true가 기본이 된다.
/// 테스트에서는 이 값을 갈아끼워 화면을 격리한다.
const _useApi = bool.fromEnvironment('GAON_USE_API');

GaonRepository repository = _useApi ? ApiRepository() : MockRepository();
