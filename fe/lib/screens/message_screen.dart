import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../data/app_lang.dart';
import '../data/locator.dart';
import '../data/teacher_store.dart';
import '../models/display.dart';
import '../models/schema.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';

/// S11 문자 번역 (F-TCH-1~4) = Chain B + S12 받는 사람 선택 시트.
/// 메시지는 생성까지만 — 전송은 사용자가 복사/공유로 직접 한다(제품 결정).
class MessageScreen extends StatefulWidget {
  const MessageScreen({super.key});

  @override
  State<MessageScreen> createState() => _MessageScreenState();
}

class _MessageScreenState extends State<MessageScreen> {
  // 프리필 없음(QA: 처음부터 문장이 들어가 있음) — 예시는 힌트로만 보여준다.
  final _inputController = TextEditingController();
  MessageSituation _situation = MessageSituation.absence;

  /// 상황별 모국어 예시문 — 상황 칩을 바꾸면 입력창 힌트가 함께 바뀐다.
  String _hintFor(MessageSituation s) => switch (s) {
    MessageSituation.absence => bi(
      'VD: Ngày mai con bị sốt nên xin phép nghỉ học.',
      '例: 孩子明天发烧，想请假一天。',
    ),
    MessageSituation.sickNote => bi(
      'VD: Con đã đi khám bệnh, tôi sẽ nộp giấy khám bệnh sau.',
      '例: 孩子已经去医院看过了，稍后会提交诊断书。',
    ),
    MessageSituation.consultation => bi(
      'VD: Tôi muốn hẹn thời gian tư vấn về việc học của con.',
      '例: 想和老师约时间咨询孩子的学习情况。',
    ),
    MessageSituation.custom => bi('Nhập bằng tiếng Việt...', '请用中文输入...'),
  };
  int _teacherIndex = 0;
  List<Child> _children = const [];
  Child? _selectedChild; // Chain B child_info(§8) 필수 — 어느 자녀 건인지
  TeacherMessage? _message;
  bool _generating = false;

  @override
  void initState() {
    super.initState();
    repository.getChildren().then((children) {
      if (!mounted) return;
      setState(() {
        _children = children;
        _selectedChild = children.firstOrNull;
      });
    });
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  String _childLabel(Child c) {
    final gradeNo = c.grade.wire.split('_').last;
    final cls = c.classNo != null ? ' ${c.classNo}반' : '';
    return '${c.name ?? '자녀'} · $gradeNo학년$cls';
  }

  Future<void> _pickChild() async {
    final picked = await showModalBottomSheet<Child>(
      context: context,
      backgroundColor: GaonColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(GaonRadius.xxl),
        ),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(GaonSpace.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '자녀 선택 · ${bi('Chọn con', '选择孩子')}',
                style: GaonType.h3.copyWith(color: GaonColors.textPrimary),
              ),
              const SizedBox(height: GaonSpace.sm),
              // 다자녀가 많아도 시트가 넘치지 않게 목록만 스크롤(QA: 10명 overflow)
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final c in _children)
                      ListTile(
                        onTap: () => Navigator.of(context).pop(c),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(GaonRadius.md),
                        ),
                        tileColor: c.childId == _selectedChild?.childId
                            ? GaonColors.primaryLight
                            : null,
                        title: Text(
                          _childLabel(c),
                          style: GaonType.bodyLg.copyWith(
                            color: GaonColors.textPrimary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) setState(() => _selectedChild = picked);
  }

  Future<void> _generate() async {
    final child = _selectedChild;
    if (_generating || child == null) return;
    if (_inputController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '보낼 내용을 먼저 입력해 주세요 · ${bi('Hãy nhập nội dung', '请先输入内容')}',
          ),
        ),
      );
      return;
    }
    setState(() {
      _generating = true;
      _message = null;
    });
    final message = await repository.generateTeacherMessage(
      situation: _situation,
      inputNative: _inputController.text,
      childId: child.childId,
    );
    if (!mounted) return;
    setState(() {
      _message = message;
      _generating = false;
    });
  }

  Future<void> _copyAdminGuide() async {
    final guide = _message?.adminGuideNative;
    if (guide == null || guide.isEmpty) return; // _message null 방어 겸용
    await Clipboard.setData(ClipboardData(text: guide));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('행정 안내를 복사했어요 · ${bi('Đã sao chép', '已复制')}')),
    );
  }

  Future<void> _copyMessage() async {
    final message = _message;
    if (message == null) return;
    await Clipboard.setData(ClipboardData(text: message.outputKo));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('메시지를 복사했어요 · ${bi('Đã sao chép', '已复制')}')),
    );
  }

  // ── S12: 받는 사람 선택 시트 ──
  // 교사 목록은 schema에 Teacher 엔티티가 없어(SSOT 대기) TeacherStore(기기 로컬)로
  // 관리한다 — 추가/삭제 가능(QA: 선생님 목록 수정).
  Future<void> _pickTeacher() async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: GaonColors.surface,
      barrierColor: const Color(0x59011D14),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(GaonRadius.xxl),
        ),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(GaonSpace.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: GaonColors.primary,
                      borderRadius: BorderRadius.circular(GaonRadius.pill),
                    ),
                  ),
                ),
                const SizedBox(height: GaonSpace.sm),
                Text(
                  '받는 사람 · ${bi('Người nhận', '收件人')}',
                  style: GaonType.h3.copyWith(color: GaonColors.textPrimary),
                ),
                const SizedBox(height: GaonSpace.sm),
                // 검색(데모)
                Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 14,
                  ),
                  decoration: BoxDecoration(
                    color: GaonColors.bg,
                    borderRadius: BorderRadius.circular(GaonRadius.pill),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.search_rounded,
                        size: 14,
                        color: GaonColors.textSecondary,
                      ),
                      const SizedBox(width: GaonSpace.xs),
                      Text(
                        '선생님 이름 검색...',
                        style: GaonType.body.copyWith(
                          color: GaonColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: GaonSpace.xs),
                for (final (i, t) in TeacherStore.teachers.value.indexed)
                  ListTile(
                    onTap: () => Navigator.of(context).pop(i),
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i == _teacherIndex
                            ? GaonColors.textPrimary
                            : GaonColors.primaryLight,
                      ),
                      alignment: Alignment.center,
                      child: i == _teacherIndex
                          ? const Icon(
                              Icons.check_rounded,
                              size: 16,
                              color: GaonColors.onPrimary,
                            )
                          : const Icon(
                              Icons.person_rounded,
                              size: 16,
                              color: GaonColors.textSecondary,
                            ),
                    ),
                    title: Text(
                      t.name,
                      style: GaonType.body.copyWith(
                        fontWeight: i == _teacherIndex
                            ? FontWeight.w700
                            : FontWeight.w400,
                        color: GaonColors.textPrimary,
                      ),
                    ),
                    subtitle: Text(
                      t.role,
                      style: GaonType.caption.copyWith(
                        color: GaonColors.textSecondary,
                      ),
                    ),
                    trailing: IconButton(
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        size: 18,
                        color: GaonColors.textSecondary,
                      ),
                      onPressed: () async {
                        await TeacherStore.removeAt(i);
                        if (!context.mounted) return;
                        setSheetState(() {});
                        setState(() => _teacherIndex = 0);
                      },
                    ),
                  ),
                // 받는 사람 추가 — 기기 로컬 관리(Teacher 엔티티 SSOT 대기)
                TextButton.icon(
                  onPressed: () => _addTeacher(setSheetState),
                  icon: const Icon(
                    Icons.add_rounded,
                    size: 18,
                    color: GaonColors.textPrimary,
                  ),
                  label: Text(
                    '받는 사람 추가 · ${bi('Thêm người nhận', '添加收件人')}',
                    style: GaonType.body.copyWith(
                      color: GaonColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (picked != null) setState(() => _teacherIndex = picked);
  }

  /// 받는 사람 추가 다이얼로그 — 이름·역할 입력 후 기기 로컬 저장.
  Future<void> _addTeacher(StateSetter setSheetState) async {
    final nameCtrl = TextEditingController();
    final roleCtrl = TextEditingController();
    final added = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: GaonColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GaonRadius.xl),
        ),
        title: Text(
          '받는 사람 추가',
          style: GaonType.h3.copyWith(color: GaonColors.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(hintText: '예) 최수민 선생님'),
            ),
            TextField(
              controller: roleCtrl,
              decoration: const InputDecoration(hintText: '예) 3학년 1반 담임'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              '취소',
              style: GaonType.body.copyWith(color: GaonColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              '추가',
              style: GaonType.body.copyWith(
                fontWeight: FontWeight.w700,
                color: GaonColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
    if (added == true && nameCtrl.text.trim().isNotEmpty) {
      await TeacherStore.add(
        nameCtrl.text.trim(),
        roleCtrl.text.trim().isEmpty ? '선생님' : roleCtrl.text.trim(),
      );
      setSheetState(() {});
    }
    // 다이얼로그 닫힘 애니메이션 후 정리(profile_edit 시트와 동일 패턴)
    Future.delayed(const Duration(seconds: 1), () {
      nameCtrl.dispose();
      roleCtrl.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    final teachers = TeacherStore.teachers.value;
    // 삭제 직후 인덱스가 목록 밖을 가리킬 수 있어 방어
    final teacher =
        teachers[_teacherIndex < teachers.length ? _teacherIndex : 0];

    return SafeArea(
      child: Column(
        children: [
          // 헤더
          Container(
            decoration: const BoxDecoration(
              color: GaonColors.surface,
              border: Border(bottom: BorderSide(color: GaonColors.border)),
            ),
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
                        '선생님께 문자',
                        style: GaonType.h3.copyWith(
                          color: GaonColors.textPrimary,
                        ),
                      ),
                      Text(
                        bi('Nhắn cho giáo viên', '给老师发消息'),
                        style: GaonType.micro.copyWith(
                          color: GaonColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                // 받는 사람
                Material(
                  color: GaonColors.primaryLight,
                  borderRadius: BorderRadius.circular(GaonRadius.pill),
                  child: InkWell(
                    onTap: _pickTeacher,
                    borderRadius: BorderRadius.circular(GaonRadius.pill),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 6,
                        horizontal: 12,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.person_rounded,
                            size: 13,
                            color: GaonColors.textPrimary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            teacher.name,
                            style: GaonType.label.copyWith(
                              color: GaonColors.textPrimary,
                            ),
                          ),
                          const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 14,
                            color: GaonColors.textPrimary,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(GaonSpace.md),
              children: [
                // 자녀 선택 — Chain B child_info(§8) 필수
                if (_selectedChild != null) ...[
                  Row(
                    children: [
                      Text(
                        '자녀 · Con',
                        style: GaonType.caption.copyWith(
                          fontWeight: FontWeight.w600,
                          color: GaonColors.textSecondary,
                        ),
                      ),
                      const SizedBox(width: GaonSpace.xs),
                      Material(
                        color: GaonColors.textPrimary,
                        borderRadius: BorderRadius.circular(GaonRadius.pill),
                        child: InkWell(
                          onTap: _pickChild,
                          borderRadius: BorderRadius.circular(GaonRadius.pill),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 5,
                              horizontal: 12,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _childLabel(_selectedChild!),
                                  style: GaonType.label.copyWith(
                                    color: GaonColors.onPrimary,
                                  ),
                                ),
                                const Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  size: 14,
                                  color: GaonColors.onPrimary,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: GaonSpace.md),
                ],

                // 상황 선택
                Text(
                  '상황 선택 · ${bi('Chọn tình huống', '选择情况')}',
                  style: GaonType.caption.copyWith(
                    fontWeight: FontWeight.w600,
                    color: GaonColors.textSecondary,
                  ),
                ),
                const SizedBox(height: GaonSpace.xs),
                Wrap(
                  spacing: GaonSpace.xs,
                  runSpacing: GaonSpace.xs,
                  children: [
                    for (final s in MessageSituation.values)
                      Material(
                        color: _situation == s
                            ? GaonColors.textPrimary
                            : GaonColors.primaryLight,
                        borderRadius: BorderRadius.circular(GaonRadius.pill),
                        child: InkWell(
                          onTap: () => setState(() => _situation = s),
                          borderRadius: BorderRadius.circular(GaonRadius.pill),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 7,
                              horizontal: 14,
                            ),
                            child: Text(
                              s.label.$2,
                              style: GaonType.label.copyWith(
                                color: _situation == s
                                    ? GaonColors.onPrimary
                                    : GaonColors.textPrimary,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: GaonSpace.md),

                // 모국어 입력
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '내 언어로 입력 · ${bi('Nhập bằng tiếng Việt', '用中文输入')}',
                      style: GaonType.caption.copyWith(
                        fontWeight: FontWeight.w600,
                        color: GaonColors.textSecondary,
                      ),
                    ),
                    Text(
                      bi('🇻🇳', '🇨🇳'),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ),
                const SizedBox(height: GaonSpace.xs),
                Container(
                  constraints: const BoxConstraints(minHeight: 80),
                  padding: const EdgeInsets.symmetric(
                    vertical: GaonSpace.xs,
                    horizontal: GaonSpace.sm,
                  ),
                  decoration: BoxDecoration(
                    color: GaonColors.surface,
                    borderRadius: BorderRadius.circular(GaonRadius.lg),
                    border: Border.all(width: 2, color: GaonColors.primary),
                    boxShadow: GaonShadow.card,
                  ),
                  child: TextField(
                    controller: _inputController,
                    maxLines: null,
                    style: GaonType.bodyLg.copyWith(
                      color: GaonColors.textPrimary,
                      height: 1.7,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: _hintFor(_situation),
                    ),
                  ),
                ),
                const SizedBox(height: GaonSpace.sm),

                // 번역 실행
                Center(
                  child: Material(
                    color: GaonColors.textPrimary,
                    shape: const CircleBorder(),
                    child: InkWell(
                      onTap: _generate,
                      customBorder: const CircleBorder(),
                      child: SizedBox(
                        width: 40,
                        height: 40,
                        child: _generating
                            ? const Padding(
                                padding: EdgeInsets.all(10),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: GaonColors.onPrimary,
                                ),
                              )
                            : const Icon(
                                Icons.arrow_downward_rounded,
                                size: 18,
                                color: GaonColors.onPrimary,
                              ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: GaonSpace.sm),

                // 한국어 결과
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '한국어 번역 결과 · ${bi('Bản dịch tiếng Hàn', '韩语翻译结果')}',
                      style: GaonType.caption.copyWith(
                        fontWeight: FontWeight.w600,
                        color: GaonColors.textSecondary,
                      ),
                    ),
                    const Text('🇰🇷', style: TextStyle(fontSize: 13)),
                  ],
                ),
                const SizedBox(height: GaonSpace.xs),
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(minHeight: 64),
                  padding: const EdgeInsets.symmetric(
                    vertical: GaonSpace.sm,
                    horizontal: GaonSpace.sm,
                  ),
                  decoration: BoxDecoration(
                    color: GaonColors.primaryLight,
                    borderRadius: BorderRadius.circular(GaonRadius.lg),
                    border: Border.all(width: 2, color: GaonColors.primary),
                  ),
                  child: Text(
                    _message?.outputKo ?? '아래 ↓ 버튼을 누르면 정중한 한국어로 번역돼요',
                    style: GaonType.body.copyWith(
                      color: _message != null
                          ? GaonColors.textPrimary
                          : GaonColors.textSecondary,
                      height: 1.7,
                    ),
                  ),
                ),

                if (_message != null) ...[
                  const SizedBox(height: GaonSpace.sm),
                  // 행정 안내 (RAG) — 복사 가능(QA 2026-07-11). 전송 없음(결정 #2).
                  InfoBanner(
                    ko: '행정 절차 안내',
                    native: _message!.adminGuideNative,
                    color: GaonColors.textSecondary,
                    bg: GaonColors.successLight,
                  ),
                  if (_message!.adminGuideNative.isNotEmpty) ...[
                    const SizedBox(height: GaonSpace.xs),
                    Align(
                      alignment: Alignment.centerRight,
                      child: GaonButton(
                        variant: GaonButtonVariant.ghost,
                        label: '안내 복사',
                        subLabel: bi('Sao chép', '复制'),
                        icon: const Icon(
                          Icons.copy_rounded,
                          size: 14,
                          color: GaonColors.textPrimary,
                        ),
                        onTap: _copyAdminGuide,
                      ),
                    ),
                  ],
                  const SizedBox(height: GaonSpace.sm),
                  Row(
                    children: [
                      Expanded(
                        child: GaonButton(
                          variant: GaonButtonVariant.ghost,
                          label: '복사',
                          subLabel: bi('Sao chép', '复制'),
                          icon: const Icon(
                            Icons.copy_rounded,
                            size: 14,
                            color: GaonColors.textPrimary,
                          ),
                          onTap: _copyMessage,
                        ),
                      ),
                      const SizedBox(width: GaonSpace.xs),
                      Expanded(
                        child: GaonButton(
                          label: '카톡 공유',
                          subLabel: bi('Chia sẻ', '分享'),
                          icon: const Icon(
                            Icons.share_rounded,
                            size: 14,
                            color: GaonColors.onPrimary,
                          ),
                          onTap: () {
                            // 직접 전송 금지(결정 #2) — OS 공유 시트를 열고
                            // 카톡 선택·전송은 사용자가 직접 한다.
                            SharePlus.instance.share(
                              ShareParams(text: _message!.outputKo),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
