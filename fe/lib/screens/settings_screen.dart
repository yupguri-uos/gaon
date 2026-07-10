import 'package:flutter/material.dart';

import '../data/app_lang.dart';
import '../data/locator.dart';
import '../data/profile_store.dart';
import '../data/notification_service.dart';
import '../models/display.dart';
import '../models/schema.dart';
import '../models/schema.dart' as schema; // Notification이 material과 겹침
import '../theme/tokens.dart';
import '../widgets/common.dart';
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
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // ── S15: 회원탈퇴 확인 다이얼로그 ──
  void _showDeleteDialog() {
    showDialog<void>(
      context: context,
      barrierColor: const Color(0x80011D14),
      builder: (context) => Dialog(
        backgroundColor: GaonColors.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(GaonRadius.xxl)),
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
                child: const Icon(Icons.delete_outline_rounded,
                    size: 26, color: GaonColors.warning),
              ),
              const SizedBox(height: GaonSpace.sm),
              Text('정말 탈퇴하시겠어요?',
                  textAlign: TextAlign.center,
                  style: GaonType.h2.copyWith(color: GaonColors.textPrimary)),
              const SizedBox(height: 6),
              Text(bi('Bạn có chắc chắn muốn xóa tài khoản?', '确定要注销账号吗？'),
                  textAlign: TextAlign.center,
                  style: GaonType.label
                      .copyWith(color: GaonColors.textSecondary)),
              const SizedBox(height: GaonSpace.md),
              for (final w in const [
                '모든 번역 기록이 삭제됩니다',
                '캘린더 저장 항목이 사라집니다',
                '이 작업은 되돌릴 수 없습니다',
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: GaonColors.warning,
                        ),
                      ),
                      const SizedBox(width: GaonSpace.xs),
                      Text(w,
                          style: GaonType.label
                              .copyWith(color: GaonColors.textPrimary)),
                    ],
                  ),
                ),
              const SizedBox(height: GaonSpace.sm),
              Row(
                children: [
                  Expanded(
                    child: _dialogButton(
                      label: '취소 · ${bi('Hủy', '取消')}',
                      bg: GaonColors.primaryLight,
                      fg: GaonColors.textPrimary,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: GaonSpace.xs),
                  Expanded(
                    child: _dialogButton(
                      label: '탈퇴 · ${bi('Xóa', '注销')}',
                      bg: GaonColors.warning,
                      fg: Colors.white,
                      onTap: () {
                        Navigator.of(context).pop();
                        _snack('회원탈퇴는 Kakao 로그인 연동 후 제공돼요');
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
          child: Text(label,
              style: GaonType.body
                  .copyWith(fontWeight: FontWeight.w700, color: fg)),
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
              message: '프로필을 불러오지 못했어요',
              subMessage: '네트워크 확인 후 다시 시도해 주세요',
              onRetry: () => setState(() => _future = _load()),
            );
          }
          if (!snap.hasData) {
            return const Center(
                child: CircularProgressIndicator(
                    color: GaonColors.textSecondary));
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
                    vertical: GaonSpace.lg, horizontal: GaonSpace.md),
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
                          style: GaonType.h1
                              .copyWith(color: GaonColors.textPrimary)),
                    ),
                    const SizedBox(width: GaonSpace.sm),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$name 님',
                            style: GaonType.h2
                                .copyWith(color: GaonColors.onPrimary)),
                        Text(
                            '${user.originCountry.label.split(' ').last} '
                            '${user.nativeLanguage.label}$childDesc',
                            style: GaonType.caption
                                .copyWith(color: GaonColors.primary)),
                      ],
                    ),
                  ],
                ),
              ),

              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(GaonSpace.sm),
                  children: [
                    _section('프로필', [
                      _row(
                        icon: Icons.person_outline_rounded,
                        label: '개인정보 수정',
                        sub: bi('Chỉnh sửa hồ sơ', '修改个人信息'),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const ProfileEditScreen(
                                  section: ProfileSection.profile)),
                        ),
                      ),
                      _row(
                        icon: Icons.family_restroom_rounded,
                        label: '자녀 관리',
                        sub: bi('Quản lý con', '子女管理'),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const ProfileEditScreen(
                                  section: ProfileSection.children)),
                        ),
                      ),
                    ]),
                    _section('언어 · ${bi('Ngôn ngữ', '语言')}', [
                      // 병기 언어 즉시 전환(시연용) — 서버 프로필과 별개로 UI만 바꾼다
                      _row(
                        icon: Icons.translate_rounded,
                        label: '병기 언어',
                        sub: bi('Tiếng Việt', '中文'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final (lang, name) in const [
                              (NativeLanguage.vi, 'Việt'),
                              (NativeLanguage.zh, '中文'),
                            ])
                              GestureDetector(
                                onTap: () {
                                  appLanguage.value = lang;
                                  ProfileStore.saveLanguage(lang); // 재시작 유지
                                },
                                child: Container(
                                  margin: const EdgeInsets.only(left: 6),
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 6, horizontal: 12),
                                  decoration: BoxDecoration(
                                    color: appLanguage.value == lang
                                        ? GaonColors.textPrimary
                                        : GaonColors.primaryLight,
                                    borderRadius: BorderRadius.circular(
                                        GaonRadius.pill),
                                  ),
                                  child: Text(name,
                                      style: GaonType.label.copyWith(
                                          color: appLanguage.value == lang
                                              ? GaonColors.onPrimary
                                              : GaonColors.textPrimary)),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ]),
                    _section('알림', [
                      // 시연용: 5초 후 로컬 알림 발화 → 기기를 잠그면 잠금화면에서 확인
                      _row(
                        icon: Icons.lock_clock_rounded,
                        label: '잠금화면 알림 미리보기',
                        sub: bi('Xem trước thông báo (5s)', '通知预览 (5秒)'),
                        onTap: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          // BE notifications 미구현(§11 P2) — 서버 목록에 기대지 않고
                          // 저장된 캘린더 일정(마감 우선)으로 로컬 구성한다.
                          var notification =
                              (await repository.getNotifications())
                                  .firstOrNull;
                          if (notification == null) {
                            List<CalendarEvent> events = const [];
                            try {
                              events = await repository.getCalendarEvents();
                            } catch (_) {} // 네트워크 실패해도 기본 문구로 진행
                            final target = events
                                    .where((e) =>
                                        e.type == CalendarEventType.deadline)
                                    .firstOrNull ??
                                events.firstOrNull;
                            notification = schema.Notification(
                              notificationId: 'preview',
                              userId: '',
                              type: NotificationType.deadlineD2,
                              titleNative: '⏰ 마감 임박 · ${bi('Sắp đến hạn', '截止临近')}',
                              bodyNative: target != null
                                  ? '「${target.title}」 — ${target.date.month}월 ${target.date.day}일까지예요. 미리 준비해 주세요!'
                                  : '가정통신문 회신 마감이 다가오고 있어요. 앱에서 확인해 주세요!',
                              scheduledAt: repository.now(),
                            );
                          }
                          await NotificationService.instance
                              .schedulePreview(notification,
                                  delay: const Duration(seconds: 3));
                          messenger.showSnackBar(const SnackBar(
                              content: Text(
                                  '지금 화면을 잠가보세요 — 곧 알림이 도착해요 🔒')));
                        },
                      ),
                      _row(
                        icon: Icons.notifications_none_rounded,
                        label: '푸시 알림',
                        sub: bi('Thông báo đẩy', '推送通知'),
                        trailing: GestureDetector(
                          onTap: () => setState(
                              () => _pushEnabled = !_pushEnabled),
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
                              borderRadius:
                                  BorderRadius.circular(GaonRadius.pill),
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
                    _section('계정', [
                      _row(
                        icon: Icons.logout_rounded,
                        label: '로그아웃',
                        sub: bi('Đăng xuất', '退出登录'),
                        onTap: () =>
                            _snack('로그아웃은 Kakao 로그인 연동 후 제공돼요'),
                      ),
                      _row(
                        icon: Icons.delete_outline_rounded,
                        label: '회원탈퇴',
                        sub: bi('Xóa tài khoản', '注销账号'),
                        danger: true,
                        onTap: _showDeleteDialog,
                      ),
                    ]),
                    const SizedBox(height: GaonSpace.md),
                    Center(
                      child: Column(
                        children: [
                          Text('GAON v1.0.0',
                              style: GaonType.micro.copyWith(
                                  color: GaonColors.textSecondary)),
                        ],
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
                left: GaonSpace.xs, bottom: GaonSpace.xxs),
            child: Text(title,
                style: GaonType.caption.copyWith(
                    fontWeight: FontWeight.w600,
                    color: GaonColors.textSecondary)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
                vertical: GaonSpace.xs, horizontal: GaonSpace.md),
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
              child: Icon(icon,
                  size: 16,
                  color:
                      danger ? GaonColors.warning : GaonColors.textPrimary),
            ),
            const SizedBox(width: GaonSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: GaonType.body.copyWith(
                          fontWeight: FontWeight.w600,
                          color: danger
                              ? GaonColors.warning
                              : GaonColors.textPrimary)),
                  Text(sub,
                      style: GaonType.micro
                          .copyWith(color: GaonColors.textSecondary)),
                ],
              ),
            ),
            trailing ??
                const Icon(Icons.chevron_right_rounded,
                    size: 16, color: GaonColors.textSecondary),
          ],
        ),
      ),
    );
  }
}
