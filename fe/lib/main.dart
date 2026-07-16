import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

import 'data/api_repository.dart';
import 'data/app_lang.dart';
import 'data/auth_store.dart';
import 'data/locator.dart';
import 'data/session_router.dart';
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
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSub;

  // 초기 링크(getInitialAppLink)와 스트림이 같은 URI를 겹쳐 줄 수 있어(app_links 특성)
  // 마지막 처리 URI를 기억해 딥링크 중복 라우팅을 막는다.
  String? _lastHandledUri;
  // navigator 미준비 시 딥링크 라우팅 결정을 잠시 보관 → 마운트 후 소비(콜드스타트 방어).
  bool? _pendingNeedsOnboarding;

  // 첫 화면은 시작 시 1회 고정(재빌드로 갈아끼워지는 화면 점프 방지).
  // 저장 토큰이 있으면 /me 확인 동안 스플래시 → _bootstrap이 목적지로 교체(세션 복구).
  // 토큰이 없으면 기존과 동일하게 즉시 로그인/언어선택(첫 실행 = 언어 선택부터).
  late final Widget _initialHome = _decideInitialHome();

  Widget _decideInitialHome() {
    if (AuthStore.hasToken && repository is ApiRepository) {
      return const _SplashScreen();
    }
    return AppLangStore.hasChoice
        ? const LoginScreen()
        : const LanguageSelectScreen();
  }

  @override
  void initState() {
    super.initState();
    // Kakao OAuth 복귀 딥링크(F-ON-3): BE /auth/kakao/callback이
    // gaon://auth/callback?token=...&needs_onboarding=... 으로 리다이렉트한다
    // (be/app/routers/auth.py APP_CALLBACK_URL과 일치).
    //
    // 앱이 살아있는 동안(warm) 오는 링크는 스트림으로,
    // 앱이 죽었다 켜지는(cold start) 초기 링크는 _bootstrap의 getInitialLink로 받는다.
    _linkSub = _appLinks.uriLinkStream.listen(_onUri, onError: (_) {});
    // 첫 프레임(navigator 준비) 이후 시작 오케스트레이션 실행.
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_bootstrap()));
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    super.dispose();
  }

  /// 시작 오케스트레이션: ① 콜드스타트 초기 딥링크 → ② 저장 토큰 복구 → (없으면 home 유지).
  Future<void> _bootstrap() async {
    // ① 콜드스타트 초기 딥링크: OAuth 복귀로 앱이 새로 켜진 경우.
    //    있으면 딥링크가 라우팅을 가져가고(가장 신선한 토큰·needs_onboarding), 토큰 게이트는 건너뛴다.
    Uri? initial;
    try {
      initial = await _appLinks.getInitialLink();
    } catch (_) {
      initial = null; // 플랫폼 미지원(테스트 등) — 초기 링크 없음으로 처리
    }
    if (initial != null && _isAuthUri(initial)) {
      await _handleAuthCallback(initial);
      return;
    }

    // ② 저장 토큰 복구 — login_screen과 동일한 /me 검증 로직 재사용(session_router).
    //    이 분기는 home이 스플래시인 경우에만 진입한다(위 _decideInitialHome).
    final repo = repository;
    if (AuthStore.hasToken && repo is ApiRepository) {
      try {
        final dest = await resolvePostLoginDestination(repo);
        _replaceRoot(
          dest == PostLoginDestination.main
              ? const MainShell()
              : const OnboardingChildScreen(),
        );
        return;
      } on AuthRequiredException {
        await AuthStore.clear(); // 유효하지 않은(만료) 토큰 폐기 → 로그인 폴백
      } catch (_) {
        // 네트워크 등 일시 실패: 토큰은 유지하고 로그인 화면으로(재시도는 버튼에서 /me 재확인)
      }
      // 스플래시에서 시작했으므로 반드시 실 화면으로 교체한다(스플래시 멈춤 방지).
      _replaceRoot(
        AppLangStore.hasChoice
            ? const LoginScreen()
            : const LanguageSelectScreen(),
      );
    }
    // 토큰이 없으면 home이 이미 로그인/언어선택 — 아무것도 하지 않는다(기존 흐름 유지).
  }

  bool _isAuthUri(Uri uri) => uri.scheme == 'gaon' && uri.host == 'auth';

  void _onUri(Uri uri) {
    if (_isAuthUri(uri)) unawaited(_handleAuthCallback(uri));
  }

  Future<void> _handleAuthCallback(Uri uri) async {
    // 초기 링크 + 스트림이 같은 로그인 URI를 중복 전달해도 한 번만 처리한다
    // (같은 로그인은 토큰이 같아 URI가 동일 — 다른 로그인은 토큰이 달라 통과).
    final key = uri.toString();
    if (key == _lastHandledUri) return;
    _lastHandledUri = key;

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

    _routeAfterAuth(needsOnboarding);
  }

  /// 딥링크 인증 후 라우팅. navigator 미준비면 결정을 pending으로 보관해
  /// 마운트 이후 소비한다(콜드스타트에서 링크가 navigator보다 먼저 도착하는 경우 방어).
  void _routeAfterAuth(bool needsOnboarding) {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) {
      _pendingNeedsOnboarding = needsOnboarding;
      WidgetsBinding.instance.addPostFrameCallback((_) => _drainPending());
      return;
    }
    _navigateAfterAuth(navigator, needsOnboarding);
  }

  void _drainPending() {
    final pending = _pendingNeedsOnboarding;
    final navigator = _navigatorKey.currentState;
    if (pending == null || navigator == null) return;
    _pendingNeedsOnboarding = null;
    _navigateAfterAuth(navigator, pending);
  }

  void _navigateAfterAuth(NavigatorState navigator, bool needsOnboarding) {
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

  /// 스플래시(세션 복구 대기 화면)를 실 화면으로 교체한다.
  void _replaceRoot(Widget screen) {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => screen),
      (_) => false,
    );
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
      // 토큰 보유 시 스플래시로 시작해 세션 복구(F-ON-3), 아니면 첫 실행 흐름 그대로.
      home: _initialHome,
    );
  }
}

/// 저장 토큰으로 세션을 복구하는 동안 잠깐 보여주는 대기 화면(F-ON-3).
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: GaonColors.bg,
      body: Center(child: CircularProgressIndicator(color: GaonColors.primary)),
    );
  }
}
