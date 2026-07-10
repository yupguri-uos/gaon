import 'package:shared_preferences/shared_preferences.dart';

import '../models/schema.dart';

/// 온보딩에서 고른 프로필(출신국·모국어)의 로컬 저장소.
/// BE에 GET /me가 없어(§11 갭) 앱 재시작 시 프로필이 폴백으로 초기화되는 문제를
/// 막는다 — 서버 응답이 있으면 서버가 정본, 없을 때 이 값이 폴백을 대체한다.
class ProfileStore {
  static const _kCountry = 'profile.origin_country';
  static const _kLanguage = 'profile.native_language';

  static OriginCountry? _country;
  static NativeLanguage? _language;

  static OriginCountry? get country => _country;
  static NativeLanguage? get language => _language;

  /// 앱 시작 시 1회 로드(비동기 완료 전에는 null → 기존 폴백 동작).
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final c = prefs.getString(_kCountry);
    final l = prefs.getString(_kLanguage);
    try {
      if (c != null) _country = OriginCountry.fromWire(c);
      if (l != null) _language = NativeLanguage.fromWire(l);
    } catch (_) {} // 알 수 없는 값이면 무시(스키마 변경 대비)
  }

  static Future<void> saveLanguage(NativeLanguage language) async {
    _language = language;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLanguage, language.wire);
  }

  static Future<void> save({
    required OriginCountry country,
    required NativeLanguage language,
  }) async {
    _country = country;
    _language = language;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kCountry, country.wire);
    await prefs.setString(_kLanguage, language.wire);
  }
}
