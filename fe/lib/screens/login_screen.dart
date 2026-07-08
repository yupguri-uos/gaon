import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'onboarding_self_screen.dart';

/// S1 로그인 (F-ON-3) — GAON 로고 + 카카오 OAuth 진입점.
/// 현재는 UI만: 버튼 탭 시 온보딩으로 이동. 실제 OAuth 연동은 BE 준비 후.
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GaonColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            // 히어로 — GAON 로고
            Expanded(
              child: Center(
                child: Image.asset(
                  'assets/images/gaon_logo.png',
                  width: 210,
                  fit: BoxFit.contain,
                ),
              ),
            ),

            // 카카오 CTA
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  GaonSpace.lg, 0, GaonSpace.lg, GaonSpace.xl),
              child: Column(
                children: [
                  Material(
                    color: GaonColors.kakao,
                    borderRadius: BorderRadius.circular(GaonRadius.pill),
                    child: InkWell(
                      onTap: () => Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                            builder: (_) => const OnboardingSelfScreen()),
                      ),
                      borderRadius: BorderRadius.circular(GaonRadius.pill),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        decoration: BoxDecoration(
                          borderRadius:
                              BorderRadius.circular(GaonRadius.pill),
                          boxShadow: GaonShadow.kakao,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.chat_bubble,
                                size: 20, color: Color(0xFF1A1A1A)),
                            const SizedBox(width: GaonSpace.xs),
                            Text('카카오로 시작하기',
                                style: GaonType.h3.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF1A1A1A))),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: GaonSpace.xs),
                  Text('계속하면 서비스 약관에 동의합니다',
                      style: GaonType.micro
                          .copyWith(color: GaonColors.textSecondary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
