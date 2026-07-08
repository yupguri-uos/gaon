import 'mock_repository.dart';
import 'repository.dart';

/// 전역 저장소 인스턴스.
/// BE 연동 시 여기서 MockRepository → ApiRepository로 교체하면 끝
/// (화면 코드는 GaonRepository 인터페이스만 알므로 무변경).
/// ApiRepository의 base URL은 api_config.dart의 gaonApiBase(= https://gaon.uk/api).
/// 테스트에서는 이 값을 갈아끼워 화면을 격리한다.
GaonRepository repository = MockRepository();
