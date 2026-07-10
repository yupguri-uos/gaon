import 'package:shared_preferences/shared_preferences.dart';

/// 세션 토큰 저장소(F-ON-3) — Kakao 로그인으로 받은 GAON JWT를 영속화한다.
///
/// 우선순위: 저장된 로그인 토큰 > --dart-define=GAON_API_TOKEN(개발용 수동 주입).
/// dart-define 토큰은 로그인 플로우 없이 실서버를 붙이는 개발·리허설 용도로만 남긴다.
class AuthStore {
  AuthStore._();

  static const _key = 'gaon_session_token';
  static const _devToken = String.fromEnvironment(
    'GAON_API_TOKEN',
    defaultValue: '',
  );

  static String? _token;

  /// 앱 시작 시 1회 호출(main.dart) — 저장된 토큰을 메모리로 올린다.
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_key);
    _token = (stored == null || stored.isEmpty) ? null : stored;
  }

  /// 현재 유효 토큰. 로그인 토큰이 없으면 개발용 dart-define으로 폴백.
  static String get token => _token ?? _devToken;

  static bool get hasToken => token.isNotEmpty;

  /// 로그인 성공(딥링크 콜백) 시 저장.
  static Future<void> save(String token) async {
    _token = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, token);
  }

  /// 로그아웃·토큰 만료 시 폐기(§12: stateless JWT — 클라 폐기가 곧 로그아웃).
  static Future<void> clear() async {
    _token = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
