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
  // 사용자가 직접 추가한 상황(custom 활용). 세션 한정 — 선택 시 wire=custom으로 보내고
  // 라벨은 input_native 앞에 붙여 AI에 맥락 전달(스키마 변경 없음, QA 2026-07-11).
  final List<String> _customSituations = [];
  String? _selectedCustom; // 선택된 커스텀 라벨. null이면 프리셋 _situation 사용.

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
  // 받는 사람(교사) — 자녀별 로컬 목록(TeacherStore, 팀 결정 2026-07-13).
  int _teacherIndex = 0;
  List<Child> _children = const [];
  Child? _selectedChild; // Chain B child_info(§8) 필수 — 어느 자녀 건인지
  TeacherMessage? _message;
  bool _generating = false;

  /// 선택된 자녀의 교사 목록 — 자녀 미선택이면 빈 목록.
  List<Teacher> get _teachers {
    final child = _selectedChild;
    return child == null ? const [] : TeacherStore.forChild(child.childId);
  }

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
                biLine('자녀 선택', 'Chọn con', '选择孩子'),
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
    if (picked != null) {
      setState(() {
        _selectedChild = picked;
        _teacherIndex = 0; // 자녀가 바뀌면 그 자녀의 교사 목록으로 초기화
      });
    }
  }

  Future<void> _generate() async {
    final child = _selectedChild;
    if (_generating || child == null) return;
    if (_inputController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            biLine('보낼 내용을 먼저 입력해 주세요', 'Hãy nhập nội dung', '请先输入内容'),
          ),
        ),
      );
      return;
    }
    setState(() {
      _generating = true;
      _message = null;
    });
    // 커스텀 상황이면 wire는 custom, 라벨을 입력 앞에 붙여 AI에 맥락 전달.
    final custom = _selectedCustom;
    final message = await repository.generateTeacherMessage(
      situation: custom != null ? MessageSituation.custom : _situation,
      inputNative: custom != null
          ? '[$custom] ${_inputController.text}'
          : _inputController.text,
      childId: child.childId,
    );
    if (!mounted) return;
    setState(() {
      _message = message;
      _generating = false;
    });
  }

  /// 상황 칩 — 모국어(주) + 한국어(병기). [sub]가 없으면 단일 라벨(커스텀 상황).
  Widget _situationChip({
    required String text,
    String? sub,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected ? GaonColors.textPrimary : GaonColors.primaryLight,
      borderRadius: BorderRadius.circular(GaonRadius.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(GaonRadius.pill),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                text,
                style: GaonType.label.copyWith(
                  color: selected
                      ? GaonColors.onPrimary
                      : GaonColors.textPrimary,
                ),
              ),
              if (sub != null)
                Text(
                  sub,
                  style: GaonType.micro.copyWith(
                    color: selected
                        ? GaonColors.primary
                        : GaonColors.textSecondary,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _addCustomSituation() async {
    final controller = TextEditingController();
    final label = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: GaonColors.surface,
        title: Text(biLine('상황 직접 추가', 'Thêm tình huống', '添加情况')),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 20,
          decoration: InputDecoration(
            hintText: bi(
              'VD: hỏi đồ dùng học tập, tư vấn chuyển trường',
              '例: 咨询学习用品、转学咨询',
            ),
          ),
          onSubmitted: (v) => Navigator.of(dialogContext).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(biLine('취소', 'Hủy', '取消')),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: Text(biLine('추가', 'Thêm', '添加')),
          ),
        ],
      ),
    );
    if (label == null || label.isEmpty) return;
    if (!mounted) return;
    setState(() {
      // 중복이면 기존 것을 선택만.
      if (!_customSituations.contains(label)) _customSituations.add(label);
      _selectedCustom = label;
    });
  }

  Future<void> _copyMessage() async {
    final message = _message;
    if (message == null) return;
    await Clipboard.setData(ClipboardData(text: message.outputKo));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(biLine('메시지를 복사했어요', 'Đã sao chép', '已复制'))),
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
                  biLine('받는 사람', 'Người nhận', '收件人'),
                  style: GaonType.h3.copyWith(color: GaonColors.textPrimary),
                ),
                const SizedBox(height: GaonSpace.sm),
                // 빈 목록 — 교사 추가 유도(QA T-1: 데모 프리셋 제거, 초기 상태 빈 목록)
                if (_teachers.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: GaonSpace.md),
                    child: BiText(
                      native: bi(
                        'Hãy thêm giáo viên của con',
                        '请添加孩子的老师',
                      ),
                      ko: '교사를 추가해주세요',
                      align: TextAlign.center,
                      nativeStyle: GaonType.body,
                      koStyle: GaonType.caption,
                    ),
                  ),
                for (final (i, t) in _teachers.indexed)
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
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 수정(QA T-1)
                        IconButton(
                          icon: const Icon(
                            Icons.edit_outlined,
                            size: 18,
                            color: GaonColors.textSecondary,
                          ),
                          onPressed: () =>
                              _editTeacherDialog(setSheetState, editIndex: i),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            size: 18,
                            color: GaonColors.textSecondary,
                          ),
                          onPressed: () async {
                            final child = _selectedChild;
                            if (child == null) return;
                            await TeacherStore.removeAt(child.childId, i);
                            if (!context.mounted) return;
                            setSheetState(() {});
                            setState(() => _teacherIndex = 0);
                          },
                        ),
                      ],
                    ),
                  ),
                // 받는 사람 추가 — 자녀별 기기 로컬 관리(팀 결정 2026-07-13)
                TextButton.icon(
                  onPressed: () => _editTeacherDialog(setSheetState),
                  icon: const Icon(
                    Icons.add_rounded,
                    size: 18,
                    color: GaonColors.textPrimary,
                  ),
                  label: Text(
                    biLine('받는 사람 추가', 'Thêm người nhận', '添加收件人'),
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

  /// 받는 사람 추가/수정 다이얼로그(QA T-1) — 이름·직책 입력 후 자녀별 로컬 저장.
  /// [editIndex]가 null이면 추가, 있으면 해당 교사 수정.
  Future<void> _editTeacherDialog(
    StateSetter setSheetState, {
    int? editIndex,
  }) async {
    final child = _selectedChild;
    if (child == null) return;
    final editing = editIndex == null ? null : _teachers[editIndex];
    final nameCtrl = TextEditingController(text: editing?.name ?? '');
    final roleCtrl = TextEditingController(text: editing?.role ?? '');
    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: GaonColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GaonRadius.xl),
        ),
        title: Text(
          editing == null
              ? biLine('받는 사람 추가', 'Thêm người nhận', '添加收件人')
              : biLine('받는 사람 수정', 'Sửa người nhận', '修改收件人'),
          style: GaonType.h3.copyWith(color: GaonColors.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                hintText: '${bi('VD', '例')}) 최수민 선생님',
              ),
            ),
            TextField(
              controller: roleCtrl,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => Navigator.of(dialogContext).pop(true),
              decoration: InputDecoration(
                hintText: '${bi('VD', '例')}) 3학년 1반 담임',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              biLine('취소', 'Hủy', '取消'),
              style: GaonType.body.copyWith(color: GaonColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              editing == null
                  ? biLine('추가', 'Thêm', '添加')
                  : biLine('저장', 'Lưu', '保存'),
              style: GaonType.body.copyWith(
                fontWeight: FontWeight.w700,
                color: GaonColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
    if (submitted == true && nameCtrl.text.trim().isNotEmpty) {
      final teacher = Teacher(
        name: nameCtrl.text.trim(),
        // 직책 미입력 기본값 — 저장 데이터라 병기 없이 한국어 고정('선생님')
        role: roleCtrl.text.trim().isEmpty ? '선생님' : roleCtrl.text.trim(),
      );
      if (editIndex == null) {
        await TeacherStore.add(child.childId, teacher);
      } else {
        await TeacherStore.update(child.childId, editIndex, teacher);
      }
      setSheetState(() {});
      if (mounted) setState(() {});
    }
    // 다이얼로그 닫힘 애니메이션 후 정리(profile_edit 시트와 동일 패턴)
    Future.delayed(const Duration(seconds: 1), () {
      nameCtrl.dispose();
      roleCtrl.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    final teachers = _teachers;
    // 삭제 직후 인덱스가 목록 밖을 가리킬 수 있어 방어. 빈 목록이면 null.
    final teacher = teachers.isEmpty
        ? null
        : teachers[_teacherIndex < teachers.length ? _teacherIndex : 0];

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
                        bi('Nhắn cho giáo viên', '给老师发消息'),
                        style: GaonType.h3.copyWith(
                          color: GaonColors.textPrimary,
                        ),
                      ),
                      Text(
                        '선생님께 문자',
                        style: GaonType.micro.copyWith(
                          color: GaonColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                // 받는 사람 — 선택된 자녀의 교사(없으면 추가 유도, QA T-1)
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
                          Icon(
                            teacher == null
                                ? Icons.person_add_alt_rounded
                                : Icons.person_rounded,
                            size: 13,
                            color: GaonColors.textPrimary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            teacher?.name ??
                                biLine('선생님 추가', 'Thêm giáo viên', '添加老师'),
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
              // 스크롤로 키보드 닫기(QA T-4 ① — iOS에서 키보드 못 닫는 문제)
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.all(GaonSpace.md),
              children: [
                // 자녀 선택 — Chain B child_info(§8) 필수
                if (_selectedChild != null) ...[
                  Row(
                    children: [
                      Text(
                        // 'Con' 하드코딩(zh에서도 베트남어 노출되던 버그) → bi()로 수정
                        biLine('자녀', 'Con', '孩子'),
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
                  biLine('상황 선택', 'Chọn tình huống', '选择情况'),
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
                    // 프리셋 상황 — 모국어(주)·한국어(병기), 선택 시 커스텀 해제.
                    for (final s in MessageSituation.values)
                      _situationChip(
                        text: s.label.$1,
                        sub: s.label.$2,
                        selected: _selectedCustom == null && _situation == s,
                        onTap: () => setState(() {
                          _situation = s;
                          _selectedCustom = null;
                        }),
                      ),
                    // 사용자가 추가한 상황(custom) — 입력한 언어 그대로.
                    for (final c in _customSituations)
                      _situationChip(
                        text: c,
                        selected: _selectedCustom == c,
                        onTap: () => setState(() => _selectedCustom = c),
                      ),
                    // 직접 추가.
                    _situationChip(
                      text: '+ ${bi('Thêm', '添加')}',
                      sub: '직접 추가',
                      selected: false,
                      onTap: _addCustomSituation,
                    ),
                  ],
                ),
                const SizedBox(height: GaonSpace.md),

                // 모국어 입력
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      biLine('내 언어로 입력', 'Nhập bằng tiếng Việt', '用中文输入'),
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
                    // 여러 줄 입력이라 완료 대신 줄바꿈(QA T-4 ③) —
                    // 닫기는 스크롤(onDrag)·빈 영역 탭(main.dart 전역)으로.
                    textInputAction: TextInputAction.newline,
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
                      biLine('한국어 번역 결과', 'Bản dịch tiếng Hàn', '韩语翻译结果'),
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
                    _message?.outputKo ??
                        biLines(
                          '아래 ↓ 버튼을 누르면 정중한 한국어로 번역돼요',
                          'Nhấn nút ↓ để dịch sang tiếng Hàn lịch sự',
                          '点击 ↓ 按钮即可翻译成礼貌的韩语',
                        ),
                    style: GaonType.body.copyWith(
                      color: _message != null
                          ? GaonColors.textPrimary
                          : GaonColors.textSecondary,
                      height: 1.7,
                    ),
                  ),
                ),

                if (_message != null) ...[
                  // 행정 절차 안내(admin_guide_native) 표시 제거 — 학교마다 절차가
                  // 달라 오정보 위험(팀 결정 #13, 2026-07-13: F-TCH-4 기능 비활성).
                  // 필드·AI 출력·BE 저장은 유지(결정 #11·#12와 동일한 코드 잔존 방식).
                  const SizedBox(height: GaonSpace.sm),
                  Row(
                    children: [
                      Expanded(
                        child: GaonButton(
                          variant: GaonButtonVariant.ghost,
                          label: bi('Sao chép', '复制'),
                          subLabel: '복사',
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
                          label: bi('Chia sẻ', '分享'),
                          subLabel: '카톡 공유',
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
