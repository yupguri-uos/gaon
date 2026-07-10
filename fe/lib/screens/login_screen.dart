import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../data/api_repository.dart';
import '../data/auth_store.dart';
import '../data/locator.dart';
import '../theme/tokens.dart';
import 'kakao_login_screen.dart';
import 'main_shell.dart';
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
                      onTap: () async {
                        final navigator = Navigator.of(context);
                        // F-ON-3: 카카오 OAuth 웹뷰 — API 모드 전용.
                        // (mock 모드·웹 빌드·위젯 테스트는 아래 기존 플로우)
                        // 성공 시 JWT 저장 후 needs_onboarding으로 분기.
                        if (!kIsWeb && repository is ApiRepository) {
                          final result = await navigator
                              .push<KakaoLoginResult>(MaterialPageRoute(
                                  builder: (_) =>
                                      const KakaoLoginScreen()));
                          if (result != null) {
                            await AuthStore.save(result.accessToken);
                            navigator.pushReplacement(MaterialPageRoute(
                                builder: (_) => result.needsOnboarding
                                    ? const OnboardingSelfScreen()
                                    : const MainShell()));
                            return;
                          }
                        }
                        // 폴백(카카오 키 미설정·취소): 기존 토큰으로 홈/온보딩.
                        // 재실행마다 자녀가 중복 등록되지 않게 기가입 계정은 홈으로.
                        final repo = repository;
                        if (repo is ApiRepository) {
                          try {
                            final children = await repo.getChildren();
                            if (children.isNotEmpty) {
                              navigator.pushReplacement(MaterialPageRoute(
                                  builder: (_) => const MainShell()));
                              return;
                            }
                          } catch (_) {
                            // 네트워크/인증 실패 시 온보딩으로 진행(아래)
                          }
                        }
                        navigator.pushReplacement(MaterialPageRoute(
                            builder: (_) => const OnboardingSelfScreen()));
                      },
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
