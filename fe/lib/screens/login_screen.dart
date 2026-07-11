import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/api_config.dart';
import '../data/api_repository.dart';
import '../data/app_lang.dart';
import '../data/auth_store.dart';
import '../data/locator.dart';
import '../theme/tokens.dart';
import 'main_shell.dart';
import 'onboarding_self_screen.dart';

/// S1 로그인 (F-ON-3) — GAON 로고 + 카카오 OAuth 진입점.
///
/// 실 OAuth 플로우(API 모드 기본):
///   버튼 탭 → 외부 브라우저로 BE /auth/kakao/login?client=app →
///   카카오 동의 → BE callback이 gaon:// 딥링크로 토큰 반환 →
///   main.dart가 저장·라우팅(needs_onboarding 분기).
/// 저장된 토큰(또는 개발용 GAON_API_TOKEN)이 이미 유효하면 OAuth 없이 바로 진입.
/// 테스트 대역(FakeRepository) 주입 시엔 OAuth 없이 온보딩으로 직행.
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  Future<void> _onKakaoTap(BuildContext context) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final repo = repository;

    // 테스트 대역(FakeRepository 등): OAuth 없이 온보딩 직행 — widget_test가 이 경로를 탄다
    if (repo is! ApiRepository) {
      navigator.pushReplacement(
        MaterialPageRoute(builder: (_) => const OnboardingSelfScreen()),
      );
      return;
    }

    // 토큰 보유(재실행·개발 토큰): /me로 상태 확인 후 바로 라우팅(§13 ⓪)
    if (AuthStore.hasToken) {
      try {
        final me = await repo.fetchMe();
        if (me != null) {
          appLanguage.value = me.nativeLanguage;
          navigator.pushReplacement(
            MaterialPageRoute(builder: (_) => const MainShell()),
          );
        } else {
          navigator.pushReplacement(
            MaterialPageRoute(builder: (_) => const OnboardingSelfScreen()),
          );
        }
        return;
      } on AuthRequiredException {
        await AuthStore.clear(); // 만료 토큰 폐기 → 아래 OAuth로 재로그인
      } catch (_) {
        messenger.showSnackBar(
          const SnackBar(content: Text('서버에 연결하지 못했어요 — 잠시 후 다시 시도해 주세요')),
        );
        return;
      }
    }

    // Kakao OAuth 시작 — 복귀는 gaon:// 딥링크(main.dart가 수신)
    final ok = await launchUrl(
      Uri.parse('$gaonApiBase/auth/kakao/login?client=app'),
      mode: LaunchMode.externalApplication,
    );
    if (!ok) {
      messenger.showSnackBar(const SnackBar(content: Text('브라우저를 열지 못했어요')));
    }
  }

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
                GaonSpace.lg,
                0,
                GaonSpace.lg,
                GaonSpace.xl,
              ),
              child: Column(
                children: [
                  Material(
                    color: GaonColors.kakao,
                    borderRadius: BorderRadius.circular(GaonRadius.pill),
                    child: InkWell(
                      onTap: () => _onKakaoTap(context),
                      borderRadius: BorderRadius.circular(GaonRadius.pill),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(GaonRadius.pill),
                          boxShadow: GaonShadow.kakao,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.chat_bubble,
                              size: 20,
                              color: Color(0xFF1A1A1A),
                            ),
                            const SizedBox(width: GaonSpace.xs),
                            Text(
                              '카카오로 시작하기',
                              style: GaonType.h3.copyWith(
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF1A1A1A),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: GaonSpace.xs),
                  Text(
                    '계속하면 서비스 약관에 동의합니다',
                    style: GaonType.micro.copyWith(
                      color: GaonColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
