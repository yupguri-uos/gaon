import 'package:flutter/material.dart';

import 'screens/login_screen.dart';
import 'theme/tokens.dart';

void main() {
  runApp(const GaonApp());
}

/// GAON — 이주배경 학부모를 위한 알림장 AI 에이전트.
/// v2 디자인(5 Flows · 15 Screens): 로그인 → 온보딩(본인·자녀) →
/// 탭 셸(알림장 챗봇 / 캘린더 / 문자 / 설정).
class GaonApp extends StatelessWidget {
  const GaonApp({super.key});

  @override
  Widget build(BuildContext context) {
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
      home: const LoginScreen(),
    );
  }
}
