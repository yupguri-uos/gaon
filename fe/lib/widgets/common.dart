import 'package:flutter/material.dart';

import '../data/app_lang.dart';
import '../theme/tokens.dart';

/// 이중언어 라벨 — 모국어(주, 크게) 먼저 + 한국어(병기, 작게) 아래.
/// 언어 순서 규칙(2026-07-13 팀 결정): 시스템 전체 '모국어 → 한국어'.
/// [native]에는 appLanguage 기준 문자열(bi() 래핑)을 넘긴다.
/// 고정 높이 금지(성조 기호·긴 문장 대응) — 항상 가변 높이.
class BiText extends StatelessWidget {
  const BiText({
    super.key,
    required this.ko,
    required this.native,
    this.nativeStyle = GaonType.body,
    this.koStyle = GaonType.caption,
    this.align = TextAlign.left,
  });

  final String ko;
  final String native;
  final TextStyle koStyle;
  final TextStyle nativeStyle;
  final TextAlign align;

  @override
  Widget build(BuildContext context) {
    // 데이터 결손 방어(QA D-7): 한쪽이 비면 빈 줄을 그리지 않는다 —
    // 서버 데이터(name_ko 등)가 비어 와도 고아 줄·빈 공백이 생기지 않게.
    final hasNative = native.trim().isNotEmpty;
    final hasKo = ko.trim().isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: align == TextAlign.center
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        if (hasNative)
          Text(
            native,
            textAlign: align,
            style: nativeStyle.copyWith(
              color: GaonColors.textPrimary,
              height: 1.4,
            ),
          ),
        if (hasNative && hasKo) const SizedBox(height: GaonSpace.xxs),
        if (hasKo)
          Text(
            ko,
            textAlign: align,
            style: koStyle.copyWith(
              // 단독 표기(모국어 결손 시)면 주 텍스트 색으로 승격
              color: hasNative
                  ? GaonColors.textSecondary
                  : GaonColors.textPrimary,
              height: 1.4,
            ),
          ),
      ],
    );
  }
}

/// 버튼 변형: primary(진한 포레스트), secondary(민트), kakao(노랑), ghost(민트 틴트).
enum GaonButtonVariant { primary, secondary, kakao, ghost }

class GaonButton extends StatelessWidget {
  const GaonButton({
    super.key,
    required this.label,
    this.subLabel,
    this.variant = GaonButtonVariant.primary,
    this.fullWidth = true,
    this.icon,
    this.onTap,
  });

  final String label;
  final String? subLabel;
  final GaonButtonVariant variant;
  final bool fullWidth;
  final Widget? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, subFg) = switch (variant) {
      GaonButtonVariant.primary => (
        GaonColors.textPrimary,
        GaonColors.onPrimary,
        const Color(0xB3FFFFFF),
      ),
      GaonButtonVariant.secondary => (
        GaonColors.success,
        // 민트 bg + 흰 글씨가 저채도로 안 보인다는 지적('할 일 보기') — 진초록으로
        GaonColors.textPrimary,
        GaonColors.textSecondary,
      ),
      GaonButtonVariant.kakao => (
        GaonColors.kakao,
        GaonColors.kakaoText,
        GaonColors.textSecondary,
      ),
      GaonButtonVariant.ghost => (
        GaonColors.successLight,
        // 민트 on 연민트가 저대비('복사'·'건너뛰기' 안 보임 지적) — 진초록으로
        GaonColors.textPrimary,
        GaonColors.textSecondary,
      ),
    };

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(GaonRadius.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(GaonRadius.pill),
        child: Container(
          width: fullWidth ? double.infinity : null,
          padding: const EdgeInsets.symmetric(
            vertical: GaonSpace.sm,
            horizontal: GaonSpace.lg,
          ),
          decoration: variant == GaonButtonVariant.ghost
              // 연민트 bg가 흰 다이얼로그에 묻힌다는 지적('건너뛰기', QA D-3) —
              // 진초록 외곽선으로 버튼 경계를 확보(토큰만 사용)
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(GaonRadius.pill),
                  border: Border.all(color: GaonColors.textPrimary, width: 1.2),
                )
              : null,
          child: Row(
            mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[icon!, const SizedBox(width: GaonSpace.xs)],
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: GaonType.btn.copyWith(color: fg),
                ),
              ),
              if (subLabel != null) ...[
                const SizedBox(width: GaonSpace.xs),
                Text(subLabel!, style: GaonType.micro.copyWith(color: subFg)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 틴트 라운드 입력/드롭다운 표시 카드. 라벨 순서: 모국어 → 한국어.
class InputCard extends StatelessWidget {
  const InputCard({
    super.key,
    required this.koLabel,
    required this.nativeLabel,
    required this.value,
    this.showChevron = true,
    this.onTap,
  });

  final String koLabel;
  final String nativeLabel;
  final String value;
  final bool showChevron;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: GaonColors.primaryLight,
      borderRadius: BorderRadius.circular(GaonRadius.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(GaonRadius.lg),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: GaonSpace.sm,
            horizontal: GaonSpace.md,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$nativeLabel · $koLabel',
                      style: GaonType.micro.copyWith(
                        color: GaonColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: GaonSpace.xxs),
                    Text(
                      value,
                      style: GaonType.bodyLg.copyWith(
                        fontWeight: FontWeight.w600,
                        color: GaonColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              if (showChevron)
                const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: GaonColors.primary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// pill 필터 칩. 선택 = success 채움, 미선택 = primaryLight.
/// 언어 순서: 모국어(주) → 한국어(병기).
class GaonChip extends StatelessWidget {
  const GaonChip({
    super.key,
    required this.ko,
    required this.native,
    this.selected = false,
    this.onTap,
  });

  final String ko;
  final String native;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? GaonColors.success : GaonColors.primaryLight,
      borderRadius: BorderRadius.circular(GaonRadius.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(GaonRadius.pill),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: GaonSpace.xs,
            horizontal: GaonSpace.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                native,
                style: GaonType.label.copyWith(
                  color: selected ? Colors.white : GaonColors.primary,
                ),
              ),
              Text(
                ko,
                style: GaonType.micro.copyWith(
                  color: selected
                      ? const Color(0xB3FFFFFF)
                      : GaonColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 흰색 엘리베이티드 카드.
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({super.key, required this.child, this.margin, this.border});

  final Widget child;
  final EdgeInsetsGeometry? margin;
  final BoxBorder? border;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: margin,
      padding: const EdgeInsets.all(GaonSpace.md),
      decoration: BoxDecoration(
        color: GaonColors.surface,
        borderRadius: BorderRadius.circular(GaonRadius.xl),
        boxShadow: GaonShadow.card,
        border: border,
      ),
      child: child,
    );
  }
}

/// 화면 헤더 (뒤로가기 옵션). 언어 순서: 모국어(주) → 한국어(병기).
class GaonHeader extends StatelessWidget {
  const GaonHeader({
    super.key,
    required this.ko,
    required this.native,
    this.showBack = false,
  });

  final String ko;
  final String native;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        GaonSpace.md,
        GaonSpace.sm,
        GaonSpace.md,
        GaonSpace.xs,
      ),
      child: Row(
        children: [
          if (showBack) ...[
            Material(
              // 민트 계열 원 안 화살표가 민트 화면 배경에 묻힌다는 지적(QA D-8) —
              // 진초록 원 + 밝은 화살표로 반전(토큰만 사용, 최고 대비)
              color: GaonColors.textPrimary,
              shape: const CircleBorder(),
              child: InkWell(
                onTap: () => Navigator.of(context).maybePop(),
                customBorder: const CircleBorder(),
                child: const SizedBox(
                  width: 32,
                  height: 32,
                  child: Icon(
                    Icons.arrow_back_rounded,
                    size: 16,
                    color: GaonColors.onPrimary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: GaonSpace.xs),
          ],
          BiText(
            ko: ko,
            native: native,
            nativeStyle: GaonType.h2,
            koStyle: GaonType.micro,
          ),
        ],
      ),
    );
  }
}

/// pill 배지 (D-2, 진행중 등).
class GaonBadge extends StatelessWidget {
  const GaonBadge({
    super.key,
    required this.label,
    required this.color,
    required this.bg,
  });

  final String label;
  final Color color;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(GaonRadius.pill),
      ),
      child: Text(label, style: GaonType.label.copyWith(color: color)),
    );
  }
}

/// 원형 아이콘 컨테이너.
class IconCircle extends StatelessWidget {
  const IconCircle({
    super.key,
    required this.child,
    required this.bg,
    this.size = 32,
  });

  final Widget child;
  final Color bg;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: child,
    );
  }
}

/// 틴트 정보 배너 — 팁·AI 행정 안내용.
/// 한국어 라벨(작게) 먼저, 모국어 본문(주 내용) 아래 — 본문이 모국어로만 오는 경우용.
class InfoBanner extends StatelessWidget {
  const InfoBanner({
    super.key,
    required this.ko,
    required this.native,
    required this.color,
    required this.bg,
  });

  final String ko;
  final String native;
  final Color color;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: GaonSpace.sm,
        horizontal: GaonSpace.md,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(GaonRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(Icons.check_circle_rounded, size: 13, color: color),
          ),
          const SizedBox(width: GaonSpace.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ko,
                  style: GaonType.micro.copyWith(
                    fontWeight: FontWeight.w600,
                    color: GaonColors.textSecondary,
                  ),
                ),
                const SizedBox(height: GaonSpace.xxs),
                Text(
                  native,
                  style: GaonType.caption.copyWith(
                    color: GaonColors.textPrimary,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 비동기 로딩 실패 안내 + 재시도 — 실서버 모드에서 무한 스피너 방지(시연 가드).
class GaonAsyncError extends StatelessWidget {
  const GaonAsyncError({
    super.key,
    required this.message,
    this.subMessage,
    this.onRetry,
  });

  final String message;
  final String? subMessage;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(GaonSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🛰️', style: TextStyle(fontSize: 32)),
            const SizedBox(height: GaonSpace.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GaonType.body.copyWith(
                fontWeight: FontWeight.w600,
                color: GaonColors.textPrimary,
                height: 1.5,
              ),
            ),
            if (subMessage != null) ...[
              const SizedBox(height: GaonSpace.xxs),
              Text(
                subMessage!,
                textAlign: TextAlign.center,
                style: GaonType.caption.copyWith(
                  color: GaonColors.textSecondary,
                ),
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: GaonSpace.md),
              GaonButton(
                label: biLine('다시 시도', 'Thử lại', '重试'),
                fullWidth: false,
                onTap: onRetry,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 연한 구분선.
class GaonDivider extends StatelessWidget {
  const GaonDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      color: GaonColors.primaryLight,
      margin: const EdgeInsets.symmetric(vertical: GaonSpace.sm),
    );
  }
}
