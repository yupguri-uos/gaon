import 'package:flutter/material.dart';

import 'data/app_lang.dart';
import 'data/auth_store.dart';
import 'data/profile_store.dart';
import 'data/teacher_store.dart';
import 'screens/login_screen.dart';
import 'theme/tokens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 온보딩에서 고른 프로필(출신국·모국어) 복원 — 재시작해도 유지
  await ProfileStore.load();
  await AuthStore.load(); // 카카오 로그인 JWT — dart-define 토큰보다 우선
  await TeacherStore.load(); // 받는 사람(교사) 목록 — 로컬 관리
  final saved = ProfileStore.language;
  if (saved != null) appLanguage.value = saved;
  runApp(const GaonApp());
}

/// GAON — 이주배경 학부모를 위한 알림장 AI 에이전트.
/// v2 디자인(5 Flows · 15 Screens): 로그인 → 온보딩(본인·자녀) →
/// 탭 셸(알림장 챗봇 / 캘린더 / 문자 / 설정).
class GaonApp extends StatelessWidget {
  const GaonApp({super.key});

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
      // 입력창 바깥을 탭하면 키보드 닫기(iOS는 기본 제스처가 없음)
      builder: (context, child) => GestureDetector(
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        behavior: HitTestBehavior.translucent,
        child: child!,
      ),
      home: const LoginScreen(),
    );
  }
}
