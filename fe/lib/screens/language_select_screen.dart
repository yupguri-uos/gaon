import 'package:flutter/material.dart';

import '../data/app_lang.dart';
import '../models/schema.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import 'login_screen.dart';
import 'onboarding_child_screen.dart';

/// S2 언어 선택 (F-ON-1) — 앱 최초 실행 시 가장 먼저 뜨는 단일 화면.
///
/// 팀 결정(2026-07-13): 사용 언어 = 출신 국가 가정 — 국가/언어 2단 선택을
/// '언어 선택' 하나로 통합(vi→VN, zh→CN 자동 매핑, BE 전송은 기존대로 둘 다).
/// 선택지는 shared-schema Literal 범위(vi·zh)만 — 이전 UI의 5개국·4개 언어
/// 확장 선택지는 '언어=국가 통합' 결정으로 해소되어 제거했다.
///
/// 언어를 탭하면 appLanguage가 즉시 바뀌어 화면 표시 언어가 실시간 전환되고,
/// 선택은 기기에 저장돼(AppLangStore) 재실행 시 유지된다.
class LanguageSelectScreen extends StatefulWidget {
  const LanguageSelectScreen({super.key, this.toChildOnboarding = false});

  /// true면 온보딩 중(로그인 완료 후) 재진입 — '다음'이 자녀 등록으로 간다.
  /// false면 첫 실행 — '다음'이 카카오 로그인으로 간다.
  final bool toChildOnboarding;

  @override
  State<LanguageSelectScreen> createState() => _LanguageSelectScreenState();
}

class _LanguageSelectScreenState extends State<LanguageSelectScreen> {
  static const _options = [
    (lang: NativeLanguage.vi, flag: '🇻🇳', name: 'Tiếng Việt', ko: '베트남어'),
    (lang: NativeLanguage.zh, flag: '🇨🇳', name: '中文', ko: '중국어'),
  ];

  Future<void> _select(NativeLanguage lang) async {
    // 탭 즉시 전 화면 표시 언어 전환 + 로컬 저장(재실행 유지)
    await AppLangStore.save(lang);
    if (mounted) setState(() {});
  }

  void _next() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => widget.toChildOnboarding
            ? const OnboardingChildScreen()
            : const LoginScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GaonColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  GaonSpace.md,
                  GaonSpace.xl,
                  GaonSpace.md,
                  GaonSpace.md,
                ),
                children: [
                  // 타이틀 — 선택된 언어(주) + 한국어(병기), 탭 시 실시간 전환
                  Text(
                    bi('Vui lòng chọn ngôn ngữ', '请选择语言'),
                    style: GaonType.h1.copyWith(color: GaonColors.textPrimary),
                  ),
                  const SizedBox(height: GaonSpace.xxs),
                  Text(
                    '언어를 선택해주세요',
                    style: GaonType.label.copyWith(
                      color: GaonColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: GaonSpace.lg),

                  for (final o in _options)
                    Padding(
                      padding: const EdgeInsets.only(bottom: GaonSpace.sm),
                      child: Material(
                        color: appLanguage.value == o.lang
                            ? GaonColors.textPrimary
                            : GaonColors.surface,
                        borderRadius: BorderRadius.circular(GaonRadius.xl),
                        child: InkWell(
                          onTap: () => _select(o.lang),
                          borderRadius: BorderRadius.circular(GaonRadius.xl),
                          child: Container(
                            padding: const EdgeInsets.all(GaonSpace.md),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(
                                GaonRadius.xl,
                              ),
                              border: Border.all(
                                width: 2,
                                color: appLanguage.value == o.lang
                                    ? GaonColors.textPrimary
                                    : GaonColors.border,
                              ),
                            ),
                            child: Row(
                              children: [
                                Text(
                                  o.flag,
                                  style: const TextStyle(fontSize: 26),
                                ),
                                const SizedBox(width: GaonSpace.sm),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        o.name,
                                        style: GaonType.h3.copyWith(
                                          color: appLanguage.value == o.lang
                                              ? GaonColors.onPrimary
                                              : GaonColors.textPrimary,
                                        ),
                                      ),
                                      Text(
                                        o.ko,
                                        style: GaonType.micro.copyWith(
                                          color: appLanguage.value == o.lang
                                              ? GaonColors.primary
                                              : GaonColors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (appLanguage.value == o.lang)
                                  const Icon(
                                    Icons.check_circle_rounded,
                                    size: 22,
                                    color: GaonColors.primary,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                  const SizedBox(height: GaonSpace.xs),
                  // 안내 — 선택한 언어로 알림장이 번역된다
                  Container(
                    padding: const EdgeInsets.all(GaonSpace.sm),
                    decoration: BoxDecoration(
                      color: GaonColors.primaryLight,
                      borderRadius: BorderRadius.circular(GaonRadius.lg),
                    ),
                    child: BiText(
                      native: bi(
                        'Thông báo của trường sẽ được dịch sang ngôn ngữ này',
                        '学校通知将翻译成该语言',
                      ),
                      ko: '선택한 언어로 알림장이 번역됩니다',
                      nativeStyle: GaonType.caption,
                      koStyle: GaonType.micro,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                GaonSpace.md,
                GaonSpace.xs,
                GaonSpace.md,
                GaonSpace.lg,
              ),
              child: GaonButton(
                label: '${bi('Tiếp tục', '继续')} →',
                subLabel: '다음',
                onTap: _next,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
