import 'package:flutter/material.dart';

import '../data/app_lang.dart';
import '../data/app_nav.dart';
import '../data/locator.dart';
import '../models/display.dart';
import '../models/schema.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import 'login_screen.dart';
import 'profile_edit_screen.dart';

/// S13 설정 — 프로필 히어로 + 섹션 리스트, S15 탈퇴 확인 다이얼로그.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late Future<(User, List<Child>)> _future = _load();

  Future<(User, List<Child>)> _load() async {
    final user = repository.getCurrentUser();
    final children = repository.getChildren();
    return (await user, await children);
  }

  void _snack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // ── S15: 회원탈퇴 확인 다이얼로그 ──
  void _showDeleteDialog() {
    showDialog<void>(
      context: context,
      barrierColor: GaonColors.barrier,
      builder: (context) => Dialog(
        backgroundColor: GaonColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GaonRadius.xxl),
        ),
        child: Padding(
          padding: const EdgeInsets.all(GaonSpace.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: GaonColors.warningLight,
                ),
                child: const Icon(
                  Icons.delete_outline_rounded,
                  size: 26,
                  color: GaonColors.warning,
                ),
              ),
              const SizedBox(height: GaonSpace.sm),
              Text(
                bi('Bạn có chắc chắn muốn xóa tài khoản?', '确定要注销账号吗？'),
                textAlign: TextAlign.center,
                style: GaonType.h2.copyWith(color: GaonColors.textPrimary),
              ),
              const SizedBox(height: 6),
              Text(
                '정말 탈퇴하시겠어요?',
                textAlign: TextAlign.center,
                style: GaonType.label.copyWith(color: GaonColors.textSecondary),
              ),
              const SizedBox(height: GaonSpace.md),
              for (final w in [
                biLines(
                  '모든 번역 기록이 삭제됩니다',
                  'Mọi bản dịch sẽ bị xóa',
                  '所有翻译记录将被删除',
                ),
                biLines(
                  '캘린더 저장 항목이 사라집니다',
                  'Lịch đã lưu sẽ biến mất',
                  '日历保存的日程将消失',
                ),
                biLines(
                  '이 작업은 되돌릴 수 없습니다',
                  'Không thể hoàn tác',
                  '此操作无法撤销',
                ),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        margin: const EdgeInsets.only(top: 6),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: GaonColors.warning,
                        ),
                      ),
                      const SizedBox(width: GaonSpace.xs),
                      Expanded(
                        child: Text(
                          w,
                          style: GaonType.label.copyWith(
                            color: GaonColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: GaonSpace.sm),
              Row(
                children: [
                  Expanded(
                    child: _dialogButton(
                      label: biLine('취소', 'Hủy', '取消'),
                      bg: GaonColors.primaryLight,
                      fg: GaonColors.textPrimary,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: GaonSpace.xs),
                  Expanded(
                    child: _dialogButton(
                      label: biLine('탈퇴', 'Xóa', '注销'),
                      bg: GaonColors.warning,
                      fg: Colors.white,
                      onTap: () async {
                        // DELETE /auth/me → 토큰 폐기 → 로그인 화면(로그아웃과 동일 복귀).
                        // 다이얼로그 context는 pop 후 죽으므로 State의 navigator를 미리 잡는다.
                        final navigator = Navigator.of(
                          this.context,
                          rootNavigator: true,
                        );
                        Navigator.of(context).pop();
                        try {
                          await repository.deleteAccount();
                        } catch (_) {
                          _snack(
                            biLines(
                              '회원탈퇴에 실패했어요. 잠시 후 다시 시도해 주세요',
                              'Xóa tài khoản thất bại — thử lại sau',
                              '注销失败——请稍后再试',
                            ),
                          );
                          return;
                        }
                        // 전역 내비 상태 리셋(C-1) — 새 계정이 설정 탭·이전
                        // 월에서 시작하지 않게
                        resetAppNav();
                        navigator.pushAndRemoveUntil(
                          MaterialPageRoute(
                            builder: (_) => const LoginScreen(),
                          ),
                          (_) => false,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dialogButton({
    required String label,
    required Color bg,
    required Color fg,
    required VoidCallback onTap,
  }) {
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(GaonRadius.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(GaonRadius.pill),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          child: Text(
            label,
            style: GaonType.body.copyWith(
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FutureBuilder(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return GaonAsyncError(
              message: biLines(
                '프로필을 불러오지 못했어요',
                'Không tải được hồ sơ',
                '无法加载个人资料',
              ),
              subMessage: biLines(
                '네트워크 확인 후 다시 시도해 주세요',
                'Hãy kiểm tra mạng rồi thử lại',
                '请检查网络后重试',
              ),
              onRetry: () => setState(() { _future = _load(); }),
            );
          }
          if (!snap.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: GaonColors.textSecondary),
            );
          }
          final (user, children) = snap.data!;
          // GET /me의 display_name(카카오 닉네임) 표시 — null이면 '학부모' 폴백(QA A-2)
          final name = user.displayName;
          final child = children.firstOrNull;
          final childDesc = child == null
              ? ''
              : ' · ${child.name ?? '자녀'} '
                    '(${child.grade.wire.split('_').last}-${child.classNo ?? '?'})';

          return Column(
            children: [
              // 프로필 히어로
              Container(
                width: double.infinity,
                color: GaonColors.textPrimary,
                padding: const EdgeInsets.symmetric(
                  vertical: GaonSpace.lg,
                  horizontal: GaonSpace.md,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: GaonColors.primary,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        (name == null || name.isEmpty)
                            ? '👪'
                            : name[0].toUpperCase(),
                        style: GaonType.h1.copyWith(
                          color: GaonColors.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: GaonSpace.sm),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (name == null || name.isEmpty)
                              ? biLine('학부모', 'Phụ huynh', '家长')
                              : '$name 님',
                          style: GaonType.h2.copyWith(
                            color: GaonColors.onPrimary,
                          ),
                        ),
                        Text(
                          '${user.originCountry.label.split(' ').last} '
                          '${user.nativeLanguage.label}$childDesc',
                          style: GaonType.caption.copyWith(
                            color: GaonColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(GaonSpace.sm),
                  children: [
                    _section(biLine('프로필', 'Hồ sơ', '个人资料'), [
                      _row(
                        icon: Icons.person_outline_rounded,
                        label: bi('Chỉnh sửa hồ sơ', '修改个人信息'),
                        sub: '개인정보 수정',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ProfileEditScreen(),
                          ),
                        ),
                      ),
                      // '자녀 관리' 행 제거(QA A-3) — 개인정보 수정과 같은 화면이라
                      // 중복 진입점만 늘렸음. 자녀 관리는 개인정보 수정 안에서.
                    ]),
                    // 알림 섹션 제거(결정 #11, 2026-07-12·13 확정) — 선제 알림(푸시·
                    // 로컬 리마인드) 기능 전면 비활성. BE 라우터·테이블은 코드 잔존.
                    _section(biLine('계정', 'Tài khoản', '账号'), [
                      _row(
                        icon: Icons.logout_rounded,
                        label: bi('Đăng xuất', '退出登录'),
                        sub: '로그아웃',
                        onTap: () async {
                          // POST /auth/logout + 로컬 토큰 폐기(F-ON-3) → 로그인 화면 복귀
                          final navigator = Navigator.of(
                            context,
                            rootNavigator: true,
                          );
                          await repository.logout();
                          resetAppNav(); // 전역 내비 상태 리셋(C-1)
                          navigator.pushAndRemoveUntil(
                            MaterialPageRoute(
                              builder: (_) => const LoginScreen(),
                            ),
                            (_) => false,
                          );
                        },
                      ),
                      _row(
                        icon: Icons.delete_outline_rounded,
                        label: bi('Xóa tài khoản', '注销账号'),
                        sub: '회원탈퇴',
                        danger: true,
                        onTap: _showDeleteDialog,
                      ),
                    ]),
                    const SizedBox(height: GaonSpace.md),
                    Center(
                      child: Text(
                        'GAON v1.0.0',
                        style: GaonType.micro.copyWith(
                          color: GaonColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _section(String title, List<Widget> rows) {
    return Padding(
      padding: const EdgeInsets.only(bottom: GaonSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(
              left: GaonSpace.xs,
              bottom: GaonSpace.xxs,
            ),
            child: Text(
              title,
              style: GaonType.caption.copyWith(
                fontWeight: FontWeight.w600,
                color: GaonColors.textSecondary,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              vertical: GaonSpace.xs,
              horizontal: GaonSpace.md,
            ),
            decoration: BoxDecoration(
              color: GaonColors.surface,
              borderRadius: BorderRadius.circular(GaonRadius.xl),
              boxShadow: GaonShadow.card,
            ),
            child: Column(children: rows),
          ),
        ],
      ),
    );
  }

  Widget _row({
    required IconData icon,
    required String label,
    required String sub,
    Widget? trailing,
    VoidCallback? onTap,
    bool danger = false,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: danger
                    ? GaonColors.warningLight
                    : GaonColors.primaryLight,
                borderRadius: BorderRadius.circular(GaonRadius.md),
              ),
              child: Icon(
                icon,
                size: 16,
                color: danger ? GaonColors.warning : GaonColors.textPrimary,
              ),
            ),
            const SizedBox(width: GaonSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GaonType.body.copyWith(
                      fontWeight: FontWeight.w600,
                      color: danger
                          ? GaonColors.warning
                          : GaonColors.textPrimary,
                    ),
                  ),
                  Text(
                    sub,
                    style: GaonType.micro.copyWith(
                      color: GaonColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            trailing ??
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: GaonColors.textSecondary,
                ),
          ],
        ),
      ),
    );
  }
}
