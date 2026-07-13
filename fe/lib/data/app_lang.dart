import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/schema.dart';

/// 앱 주 표시 언어 = 사용자 모국어(vi/zh).
/// 언어 선택(첫 실행)·로그인 시 세팅되고, 루트(main.dart)가 구독해 전 화면을 리빌드한다.
/// 표시 규칙(2026-07-13 팀 결정): 주 텍스트 = 모국어, 병기(작게) = 한국어.
final appLanguage = ValueNotifier<NativeLanguage>(NativeLanguage.vi);

/// 주 표시 텍스트 선택 — bi(베트남어, 중국어).
/// 서버 콘텐츠(번역 결과 등)는 이미 사용자 언어로 오므로 UI 크롬에만 쓴다.
String bi(String vi, String zh) =>
    appLanguage.value == NativeLanguage.zh ? zh : vi;

/// 한 줄 병기 라벨 — 모국어(주) · 한국어(병기).
/// 스타일 분리가 필요 없는 버튼·칩·시트 제목용 공용 패턴.
String biLine(String ko, String vi, String zh) => '${bi(vi, zh)} · $ko';

/// 두 줄 병기 문장 — 모국어 줄 + 한국어 줄(스낵바·다이얼로그 본문용).
String biLines(String ko, String vi, String zh) => '${bi(vi, zh)}\n$ko';

/// 언어 선택 영속화(F-ON-1) — 첫 실행 언어 선택을 기기에 저장해 재실행 시 유지.
class AppLangStore {
  AppLangStore._();

  static const _key = 'gaon_app_language';
  static bool _hasChoice = false;

  /// 언어를 이미 선택했는가 — false면 첫 실행(언어 선택 화면부터).
  static bool get hasChoice => _hasChoice;

  /// 앱 시작 시 1회 호출(main.dart) — 저장된 언어를 appLanguage로 올린다.
  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final wire = prefs.getString(_key);
      if (wire == null) return;
      appLanguage.value = NativeLanguage.fromWire(wire);
      _hasChoice = true;
    } catch (_) {} // 저장소 오류여도 기본(vi)으로 진행
  }

  /// 테스트 전용 — 첫 실행 상태로 초기화(정적 상태가 테스트 간 누출되지 않게).
  @visibleForTesting
  static void reset() {
    _hasChoice = false;
    appLanguage.value = NativeLanguage.vi;
  }

  /// 언어 선택·서버 프로필 동기화 시 저장 + 전 화면 즉시 반영.
  static Future<void> save(NativeLanguage lang) async {
    appLanguage.value = lang;
    _hasChoice = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, lang.wire);
    } catch (_) {} // 영속화 실패해도 세션 내 표시는 유지
  }
}
