import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

import 'data/api_repository.dart';
import 'data/app_lang.dart';
import 'data/auth_store.dart';
import 'data/locator.dart';
import 'data/teacher_store.dart';
import 'screens/language_select_screen.dart';
import 'screens/login_screen.dart';
import 'screens/main_shell.dart';
import 'screens/onboarding_child_screen.dart';
import 'theme/tokens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AuthStore.init(); // 저장된 세션 토큰(F-ON-3) 로드 — ApiRepository가 사용
  await AppLangStore.init(); // 선택 언어(F-ON-1) 로드 — 미선택이면 언어 선택부터
  await TeacherStore.load(); // 받는 사람(교사) 목록 — 기기 로컬 관리(F-TCH)
  runApp(const GaonApp());
}

/// GAON — 이주배경 학부모를 위한 알림장 AI 에이전트.
/// v2 디자인(5 Flows · 15 Screens): 언어 선택(첫 실행) → 로그인 →
/// 온보딩(자녀) → 탭 셸(알림장 챗봇 / 캘린더 / 문자 / 설정).
class GaonApp extends StatefulWidget {
  const GaonApp({super.key});

  @override
  State<GaonApp> createState() => _GaonAppState();
}

class _GaonAppState extends State<GaonApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<Uri>? _linkSub;

  // 첫 화면 결정은 시작 시 1회 고정 — 언어 선택 중 저장(hasChoice 변경)으로
  // home이 로그인으로 갈아끼워지는 화면 점프를 막는다('다음' 버튼으로만 진행).
  late final bool _startAtLogin = AppLangStore.hasChoice;

  @override
  void initState() {
    super.initState();
    // Kakao OAuth 복귀 딥링크(F-ON-3): BE /auth/kakao/callback이
    // gaon://auth/callback?token=...&needs_onboarding=... 으로 리다이렉트한다
    // (be/app/routers/auth.py APP_CALLBACK_URL과 일치).
    // app_links 6.x의 uriLinkStream은 초기(cold start) 링크도 함께 흘려준다.
    _linkSub = AppLinks().uriLinkStream.listen(_onUri, onError: (_) {});
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    super.dispose();
  }

  void _onUri(Uri uri) {
    if (uri.scheme == 'gaon' && uri.host == 'auth') {
      unawaited(_handleAuthCallback(uri));
    }
  }

  Future<void> _handleAuthCallback(Uri uri) async {
    final token = uri.queryParameters['token'];
    if (token == null || token.isEmpty) return;
    await AuthStore.save(token);

    final needsOnboarding = uri.queryParameters['needs_onboarding'] == 'true';
    if (!needsOnboarding) {
      // 기가입 사용자: 표시 언어(vi/zh)를 프로필(서버 값) 기준으로 맞추고
      // 로컬에도 저장한다 — 서버 우선, PATCH 동기화 없음(BE 무변경). 실패해도 진행.
      final repo = repository;
      if (repo is ApiRepository) {
        try {
          final me = await repo.fetchMe();
          if (me != null) await AppLangStore.save(me.nativeLanguage);
        } catch (_) {}
      }
    }

    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;
    if (needsOnboarding) {
      // 언어 선택을 루트에 깔고 자녀 등록을 올린다 — 자녀 등록에서 뒤로가기 시
      // 언어 선택으로 복귀(L-3), 언어를 바꿔도 '다음'으로 다시 자녀 등록 진입.
      navigator.pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => const LanguageSelectScreen(toChildOnboarding: true),
        ),
        (_) => false,
      );
      navigator.push(
        MaterialPageRoute(builder: (_) => const OnboardingChildScreen()),
      );
    } else {
      navigator.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainShell()),
        (_) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: appLanguage, // 모국어(vi/zh) 변경 시 전 화면 병기 갱신
      builder: (context, _, _) => _buildApp(),
    );
  }

  Widget _buildApp() {
    return MaterialApp(
      title: 'GAON',
      debugShowCheckedModeBanner: false,
      navigatorKey: _navigatorKey, // 딥링크 복귀 내비게이션용
      // 입력창 밖 탭으로 키보드 닫기 — 전 화면 공통(QA: iOS에서 키보드 못 닫음)
      builder: (context, child) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: child ?? const SizedBox.shrink(),
      ),
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: GaonColors.bg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: GaonColors.primary,
          surface: GaonColors.bg,
        ),
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: GaonColors.textPrimary,
          behavior: SnackBarBehavior.floating,
        ),
      ),
      // 첫 실행(언어 미선택)은 언어 선택부터 — 이후 재실행은 저장 언어로 로그인부터
      home: _startAtLogin ? const LoginScreen() : const LanguageSelectScreen(),
    );
  }
}
