import 'package:flutter/material.dart';

import '../data/app_lang.dart';
import '../data/locator.dart';
import '../data/notification_service.dart';
import '../models/display.dart';
import '../models/schema.dart';
import '../models/schema.dart' as schema; // Notification이 material과 겹침
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

  bool _pushEnabled = true;

  void _snack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // ── S15: 회원탈퇴 확인 다이얼로그 ──
  void _showDeleteDialog() {
    showDialog<void>(
      context: context,
      barrierColor: const Color(0x80011D14),
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
              onRetry: () => setState(() => _future = _load()),
            );
          }
          if (!snap.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: GaonColors.textSecondary),
            );
          }
          final (user, children) = snap.data!;
          final name = user.displayName ?? '';
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
                        name.isEmpty ? '?' : name[0].toUpperCase(),
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
                          '$name 님',
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
                      _row(
                        icon: Icons.family_restroom_rounded,
                        label: bi('Quản lý con', '子女管理'),
                        sub: '자녀 관리',
                        // 같은 화면이지만 자녀 섹션으로 바로 스크롤해 진입을 구분
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                const ProfileEditScreen(focusChildren: true),
                          ),
                        ),
                      ),
                    ]),
                    _section(biLine('알림', 'Thông báo', '通知'), [
                      // 시연용: 5초 후 로컬 알림 발화 → 기기를 잠그면 잠금화면에서 확인
                      _row(
                        icon: Icons.lock_clock_rounded,
                        label: bi('Xem trước thông báo', '通知预览'),
                        sub: '잠금화면 알림 미리보기',
                        onTap: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          // GET /notifications는 실배선됐지만 Proactive 스캐너(배치)가
                          // 아직 없어 목록이 비어 있을 수 있다 — 그때는 저장된 캘린더
                          // 일정(마감 우선)으로 로컬 알림을 구성한다.
                          var notification =
                              (await repository.getNotifications()).firstOrNull;
                          if (notification == null) {
                            List<CalendarEvent> events = const [];
                            try {
                              events = await repository.getCalendarEvents();
                            } catch (_) {} // 네트워크 실패해도 기본 문구로 진행
                            // GET /calendar/events는 과거 포함 전체 — '마감 임박'
                            // 미리보기는 오늘 이후 가장 가까운 마감(없으면 일정)만 쓴다.
                            final now = repository.now();
                            final today = DateTime(
                              now.year,
                              now.month,
                              now.day,
                            );
                            final upcoming =
                                events
                                    .where((e) => !e.date.isBefore(today))
                                    .toList()
                                  ..sort((a, b) => a.date.compareTo(b.date));
                            final target =
                                upcoming
                                    .where(
                                      (e) =>
                                          e.type == CalendarEventType.deadline,
                                    )
                                    .firstOrNull ??
                                upcoming.firstOrNull;
                            notification = schema.Notification(
                              notificationId: 'preview',
                              userId: '',
                              type: NotificationType.deadlineD2,
                              titleNative:
                                  '⏰ ${biLine('마감 임박', 'Sắp đến hạn', '截止临近')}',
                              bodyNative: target != null
                                  ? bi(
                                      '「${target.title}」 — hạn đến ${target.date.day}/${target.date.month}. Hãy chuẩn bị trước!',
                                      '「${target.title}」——截止到${target.date.month}月${target.date.day}日，请提前准备！',
                                    )
                                  : bi(
                                      'Sắp đến hạn trả lời thông báo của trường. Hãy kiểm tra trong ứng dụng!',
                                      '家庭通知回复截止日临近，请在应用中确认！',
                                    ),
                              scheduledAt: repository.now(),
                            );
                          }
                          await NotificationService.instance.schedulePreview(
                            notification,
                          );
                          // OS 스케줄러(배터리 최적화 등)가 수 초 지연시킬 수 있어
                          // '5초'를 약속하지 않는다(QA 2026-07-11)
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(
                                biLines(
                                  '잠시 후 알림이 와요 — 화면을 잠가보세요 🔒',
                                  'Thông báo sẽ đến ngay — hãy khóa màn hình 🔒',
                                  '通知马上就来——请锁屏查看 🔒',
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      _row(
                        icon: Icons.notifications_none_rounded,
                        label: bi('Thông báo đẩy', '推送通知'),
                        sub: '푸시 알림',
                        trailing: GestureDetector(
                          onTap: () =>
                              setState(() => _pushEnabled = !_pushEnabled),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: 42,
                            height: 24,
                            padding: const EdgeInsets.all(3),
                            alignment: _pushEnabled
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            decoration: BoxDecoration(
                              color: _pushEnabled
                                  ? GaonColors.textPrimary
                                  : GaonColors.border,
                              borderRadius: BorderRadius.circular(
                                GaonRadius.pill,
                              ),
                            ),
                            child: Container(
                              width: 18,
                              height: 18,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: GaonColors.bg,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ]),
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
