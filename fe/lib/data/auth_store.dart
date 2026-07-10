import 'package:shared_preferences/shared_preferences.dart';

/// 카카오 로그인(F-ON-3)으로 발급받은 GAON JWT의 로컬 저장소.
/// 값이 있으면 dart-define 토큰(GAON_API_TOKEN)보다 우선한다.
class AuthStore {
  static const _key = 'auth.token';

  static String? token;

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    token = prefs.getString(_key);
  }

  static Future<void> save(String value) async {
    token = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, value);
  }

  static Future<void> clear() async {
    token = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
