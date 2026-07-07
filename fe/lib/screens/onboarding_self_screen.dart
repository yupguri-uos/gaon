import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../widgets/common.dart';
import 'onboarding_child_screen.dart';

/// S2 온보딩 ① 본인정보 (F-ON-1) — 출신국·모국어 칩 선택.
///
/// 주의: 시안은 국가 5개(베트남·중국·필리핀·태국·한국)·언어 4개를 보여주지만
/// shared-schema는 VN/CN·vi/zh만 지원한다(확장값 §16). 나머지는 UI 데모용이며
/// BE 연동 시 SSOT → schema.py 확장이 선행돼야 한다.
class OnboardingSelfScreen extends StatefulWidget {
  const OnboardingSelfScreen({super.key});

  @override
  State<OnboardingSelfScreen> createState() => _OnboardingSelfScreenState();
}

class _OnboardingSelfScreenState extends State<OnboardingSelfScreen> {
  static const _countries = ['🇻🇳 베트남', '🇨🇳 중국', '🇵🇭 필리핀', '🇹🇭 태국', '🇰🇷 한국'];
  static const _langs = ['Tiếng Việt', '中文', 'Filipino', 'ภาษาไทย'];

  int _country = 0;
  int _lang = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GaonColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            _ProgressBar(step: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                    GaonSpace.md, GaonSpace.sm, GaonSpace.md, GaonSpace.md),
                children: [
                  Text('내 정보를 알려주세요',
                      style:
                          GaonType.h1.copyWith(color: GaonColors.textPrimary)),
                  const SizedBox(height: GaonSpace.xxs),
                  Text('Cho chúng tôi biết về bạn',
                      style: GaonType.label
                          .copyWith(color: GaonColors.textSecondary)),
                  const SizedBox(height: GaonSpace.lg),

                  // 출신국
                  Text('출신국 · Quốc gia',
                      style: GaonType.label
                          .copyWith(color: GaonColors.textSecondary)),
                  const SizedBox(height: GaonSpace.xs),
                  Wrap(
                    spacing: GaonSpace.xs,
                    runSpacing: GaonSpace.xs,
                    children: [
                      for (final (i, c) in _countries.indexed)
                        _SelectChip(
                          label: c,
                          selected: _country == i,
                          onTap: () => setState(() => _country = i),
                        ),
                    ],
                  ),
                  const SizedBox(height: GaonSpace.lg),

                  // 모국어
                  Text('모국어 · Ngôn ngữ mẹ đẻ',
                      style: GaonType.label
                          .copyWith(color: GaonColors.textSecondary)),
                  const SizedBox(height: GaonSpace.xs),
                  Wrap(
                    spacing: GaonSpace.xs,
                    runSpacing: GaonSpace.xs,
                    children: [
                      for (final (i, l) in _langs.indexed)
                        _SelectChip(
                          label: l,
                          selected: _lang == i,
                          onTap: () => setState(() => _lang = i),
                        ),
                    ],
                  ),
                  const SizedBox(height: GaonSpace.lg),

                  // 안내 박스
                  Container(
                    padding: const EdgeInsets.all(GaonSpace.sm),
                    decoration: BoxDecoration(
                      color: GaonColors.primary,
                      borderRadius: BorderRadius.circular(GaonRadius.lg),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: GaonColors.textPrimary,
                          ),
                          child: const Icon(Icons.check_rounded,
                              size: 16, color: GaonColors.bg),
                        ),
                        const SizedBox(width: GaonSpace.xs),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('선택한 언어로 알림장이 번역됩니다',
                                  style: GaonType.caption.copyWith(
                                      color: GaonColors.textPrimary)),
                              Text(
                                  'Thông báo sẽ được dịch sang ngôn ngữ của bạn',
                                  style: GaonType.micro.copyWith(
                                      color: GaonColors.textSecondary)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  GaonSpace.md, GaonSpace.xs, GaonSpace.md, GaonSpace.lg),
              child: GaonButton(
                label: '다음',
                subLabel: 'Tiếp tục →',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const OnboardingChildScreen()),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 온보딩 진행 표시 (1/2, 2/2).
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.step});

  final int step;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          const EdgeInsets.fromLTRB(GaonSpace.md, GaonSpace.sm, GaonSpace.md, 0),
      child: Row(
        children: [
          for (var i = 1; i <= 2; i++) ...[
            Expanded(
              flex: i == step ? 2 : 1,
              child: Container(
                height: 5,
                decoration: BoxDecoration(
                  color: i <= step
                      ? GaonColors.textPrimary
                      : GaonColors.primaryLight,
                  borderRadius: BorderRadius.circular(GaonRadius.pill),
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text('$step / 2',
              style:
                  GaonType.caption.copyWith(color: GaonColors.textSecondary)),
        ],
      ),
    );
  }
}

class _SelectChip extends StatelessWidget {
  const _SelectChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? GaonColors.textPrimary : GaonColors.primaryLight,
      borderRadius: BorderRadius.circular(GaonRadius.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(GaonRadius.pill),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
          child: Text(label,
              style: GaonType.label.copyWith(
                  color:
                      selected ? GaonColors.bg : GaonColors.textPrimary)),
        ),
      ),
    );
  }
}
