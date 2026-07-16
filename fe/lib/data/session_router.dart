import 'api_repository.dart';
import 'app_lang.dart';

/// 로그인 후 목적지 — 저장 토큰 복구(main.dart)와 로그인 버튼(login_screen)이 공유한다(F-ON-3).
enum PostLoginDestination { main, onboarding }

/// 보유 토큰으로 GET /me를 확인해 로그인 이후 목적지를 정한다.
///
/// login_screen과 시작 복구가 같은 판정을 쓰도록 로직을 한 곳으로 모은 것(중복 금지).
/// - /me 성공(온보딩 완료): 표시 언어를 서버 프로필 기준으로 맞춰 저장(서버 우선) → [main]
/// - /me null(온보딩 전): [onboarding]
///
/// 만료·무효 토큰이면 [AuthRequiredException]을 던지므로 호출자가 토큰을 폐기한다.
/// 그 외 오류(네트워크 등)는 그대로 전파해 호출자가 폴백을 정한다(토큰은 유지).
Future<PostLoginDestination> resolvePostLoginDestination(
  ApiRepository repo,
) async {
  final me = await repo.fetchMe();
  if (me == null) return PostLoginDestination.onboarding;
  await AppLangStore.save(me.nativeLanguage);
  return PostLoginDestination.main;
}
