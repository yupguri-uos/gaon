import 'package:flutter/material.dart';

/// GAON 디자인 토큰 — Figma Make 시안(iOS Design from Code) Layer 1을 1:1 이식.
/// 팔레트: Tints Color Palette #011D14
/// (Deep Forest · Pale Green · Mint · Light Turquoise · Baby Blue)
abstract final class GaonColors {
  // 브랜드
  static const primary = Color(0xFFA2E3DA); // Pale Green — 메인 액션
  static const primaryLight = Color(0xFFB0F2E8); // Light Turquoise — 칩·배경·필

  // 시맨틱
  static const success = Color(0xFFA2E3DA); // 완료·긍정
  static const successLight = Color(0xFFC2F1EE); // Baby Blue 틴트
  static const warning = Color(0xFFE05A2B); // 마감·긴급
  static const warningLight = Color(0xFFFEF0ED); // 긴급 배지 배경
  static const kakao = Color(0xFFFEE500); // 카카오 로그인 전용
  static const kakaoText = Color(0xFF3A1D1D);

  // 뉴트럴
  static const bg = Color(0xFFE6FFF8); // Mint — 화면 배경
  static const surface = Color(0xFFFFFFFF); // 카드·시트

  // 텍스트
  static const textPrimary = Color(0xFF011D14); // Deep Forest
  static const textSecondary = Color(0xFF3D7A6E); // Forest teal — 보조·병기
  static const onPrimary = Color(0xFFE6FFF8); // 진한 버튼 위 텍스트

  // 유틸
  static const border = Color(0x1A011D14); // rgba(1,29,20,0.10)
}

/// 타이포 스케일 — fontSize + fontWeight 페어. 색은 사용처에서 지정.
abstract final class GaonType {
  static const display = TextStyle(fontSize: 34, fontWeight: FontWeight.w700);
  static const h1 = TextStyle(fontSize: 22, fontWeight: FontWeight.w700);
  static const h2 = TextStyle(fontSize: 18, fontWeight: FontWeight.w700);
  static const h3 = TextStyle(fontSize: 16, fontWeight: FontWeight.w600);
  static const bodyLg = TextStyle(fontSize: 15, fontWeight: FontWeight.w500);
  static const body = TextStyle(fontSize: 14, fontWeight: FontWeight.w500);
  static const label = TextStyle(fontSize: 12, fontWeight: FontWeight.w600);
  static const caption = TextStyle(fontSize: 11, fontWeight: FontWeight.w400);
  static const micro = TextStyle(fontSize: 10, fontWeight: FontWeight.w400);
  static const btn = TextStyle(fontSize: 14, fontWeight: FontWeight.w700);
}

/// 간격 스케일 (8pt 그리드).
abstract final class GaonSpace {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;
}

/// 라운드 스케일.
abstract final class GaonRadius {
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 18;
  static const double xl = 22;
  static const double xxl = 28; // 바텀시트·다이얼로그
  static const double pill = 999;
}

/// 그림자 프리셋 — v2: Deep Forest 계열 그림자.
abstract final class GaonShadow {
  static const card = [
    BoxShadow(
      color: Color(0x14011D14), // rgba(1,29,20,0.08)
      blurRadius: 12,
      offset: Offset(0, 2),
    ),
  ];
  static const dark = [
    BoxShadow(
      color: Color(0x47011D14), // rgba(1,29,20,0.28)
      blurRadius: 20,
      offset: Offset(0, 4),
    ),
  ];
  static const kakao = [
    BoxShadow(
      color: Color(0x66FEE500),
      blurRadius: 16,
      offset: Offset(0, 4),
    ),
  ];
}
