import 'api_repository.dart';
import 'mock_repository.dart';
import 'repository.dart';

/// 전역 저장소 인스턴스.
///
/// 기본 = ApiRepository(실서버 gaon.uk/api). 토큰은 dart-define으로 주입:
///   flutter run --dart-define-from-file=env.json   # env.json은 gitignore
///   (env.json: {"GAON_API_TOKEN": "BE 발급 테스트 토큰"})
/// Kakao 로그인(F-ON-3)이 붙으면 토큰은 로그인 플로우가 주입한다.
///
/// 모의 데이터로 실행(오프라인 데모·위젯 개발):
///   flutter run --dart-define=GAON_USE_API=false
/// 테스트에서는 repository를 MockRepository로 갈아끼워 화면을 격리한다.
const _useApi = bool.fromEnvironment('GAON_USE_API', defaultValue: true);

GaonRepository repository = _useApi ? ApiRepository() : MockRepository();
