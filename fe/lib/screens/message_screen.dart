import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/demo_data.dart';
import '../data/locator.dart';
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
  final _inputController =
      TextEditingController(text: 'Ngày mai con bị sốt nên xin phép nghỉ học.');
  MessageSituation _situation = MessageSituation.absence;
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
    return '${c.name ?? '자녀'} · $gradeNo학년 ${c.classNo ?? '?'}반';
  }

  Future<void> _pickChild() async {
    final picked = await showModalBottomSheet<Child>(
      context: context,
      backgroundColor: GaonColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(GaonRadius.xxl)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(GaonSpace.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('자녀 선택 · Chọn con',
                  style: GaonType.h3.copyWith(color: GaonColors.textPrimary)),
              const SizedBox(height: GaonSpace.sm),
              for (final c in _children)
                ListTile(
                  onTap: () => Navigator.of(context).pop(c),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(GaonRadius.md)),
                  tileColor: c.childId == _selectedChild?.childId
                      ? GaonColors.primaryLight
                      : null,
                  title: Text(_childLabel(c),
                      style: GaonType.bodyLg
                          .copyWith(color: GaonColors.textPrimary)),
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

  Future<void> _copyMessage() async {
    final message = _message;
    if (message == null) return;
    await Clipboard.setData(ClipboardData(text: message.outputKo));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('메시지를 복사했어요 · Đã sao chép')),
    );
  }

  // ── S12: 받는 사람 선택 시트 ──
  // 교사 목록은 schema에 없어 UI 데모 데이터(demoTeachers) 사용.
  Future<void> _pickTeacher() async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: GaonColors.surface,
      barrierColor: const Color(0x59011D14),
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(GaonRadius.xxl)),
      ),
      builder: (context) => SafeArea(
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
              Text('받는 사람 · Người nhận',
                  style: GaonType.h3.copyWith(color: GaonColors.textPrimary)),
              const SizedBox(height: GaonSpace.sm),
              // 검색(데모)
              Container(
                padding: const EdgeInsets.symmetric(
                    vertical: 10, horizontal: 14),
                decoration: BoxDecoration(
                  color: GaonColors.bg,
                  borderRadius: BorderRadius.circular(GaonRadius.pill),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.search_rounded,
                        size: 14, color: GaonColors.textSecondary),
                    const SizedBox(width: GaonSpace.xs),
                    Text('선생님 이름 검색...',
                        style: GaonType.body
                            .copyWith(color: GaonColors.textSecondary)),
                  ],
                ),
              ),
              const SizedBox(height: GaonSpace.xs),
              for (final (i, t) in demoTeachers.indexed)
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
                        ? const Icon(Icons.check_rounded,
                            size: 16, color: GaonColors.onPrimary)
                        : const Icon(Icons.person_rounded,
                            size: 16, color: GaonColors.textSecondary),
                  ),
                  title: Text(t.name,
                      style: GaonType.body.copyWith(
                          fontWeight: i == _teacherIndex
                              ? FontWeight.w700
                              : FontWeight.w400,
                          color: GaonColors.textPrimary)),
                  subtitle: Text(t.role,
                      style: GaonType.caption
                          .copyWith(color: GaonColors.textSecondary)),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) setState(() => _teacherIndex = picked);
  }

  @override
  Widget build(BuildContext context) {
    final teacher = demoTeachers[_teacherIndex];

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
                vertical: GaonSpace.sm, horizontal: GaonSpace.md),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('선생님께 문자',
                          style: GaonType.h3
                              .copyWith(color: GaonColors.textPrimary)),
                      Text('Nhắn cho giáo viên',
                          style: GaonType.micro
                              .copyWith(color: GaonColors.textSecondary)),
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
                          vertical: 6, horizontal: 12),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.person_rounded,
                              size: 13, color: GaonColors.textPrimary),
                          const SizedBox(width: 4),
                          Text(teacher.name,
                              style: GaonType.label.copyWith(
                                  color: GaonColors.textPrimary)),
                          const Icon(Icons.keyboard_arrow_down_rounded,
                              size: 14, color: GaonColors.textPrimary),
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
                      Text('자녀 · Con',
                          style: GaonType.caption.copyWith(
                              fontWeight: FontWeight.w600,
                              color: GaonColors.textSecondary)),
                      const SizedBox(width: GaonSpace.xs),
                      Material(
                        color: GaonColors.textPrimary,
                        borderRadius:
                            BorderRadius.circular(GaonRadius.pill),
                        child: InkWell(
                          onTap: _pickChild,
                          borderRadius:
                              BorderRadius.circular(GaonRadius.pill),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                vertical: 5, horizontal: 12),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(_childLabel(_selectedChild!),
                                    style: GaonType.label.copyWith(
                                        color: GaonColors.onPrimary)),
                                const Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                    size: 14,
                                    color: GaonColors.onPrimary),
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
                Text('상황 선택 · Chọn tình huống',
                    style: GaonType.caption.copyWith(
                        fontWeight: FontWeight.w600,
                        color: GaonColors.textSecondary)),
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
                        borderRadius:
                            BorderRadius.circular(GaonRadius.pill),
                        child: InkWell(
                          onTap: () => setState(() => _situation = s),
                          borderRadius:
                              BorderRadius.circular(GaonRadius.pill),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                vertical: 7, horizontal: 14),
                            child: Text(s.label.$2,
                                style: GaonType.label.copyWith(
                                    color: _situation == s
                                        ? GaonColors.onPrimary
                                        : GaonColors.textPrimary)),
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
                    Text('내 언어로 입력 · Nhập bằng tiếng Việt',
                        style: GaonType.caption.copyWith(
                            fontWeight: FontWeight.w600,
                            color: GaonColors.textSecondary)),
                    const Text('🇻🇳', style: TextStyle(fontSize: 13)),
                  ],
                ),
                const SizedBox(height: GaonSpace.xs),
                Container(
                  constraints: const BoxConstraints(minHeight: 80),
                  padding: const EdgeInsets.symmetric(
                      vertical: GaonSpace.xs, horizontal: GaonSpace.sm),
                  decoration: BoxDecoration(
                    color: GaonColors.surface,
                    borderRadius: BorderRadius.circular(GaonRadius.lg),
                    border:
                        Border.all(width: 2, color: GaonColors.primary),
                    boxShadow: GaonShadow.card,
                  ),
                  child: TextField(
                    controller: _inputController,
                    maxLines: null,
                    style: GaonType.bodyLg.copyWith(
                        color: GaonColors.textPrimary, height: 1.7),
                    decoration: const InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: 'Nhập bằng tiếng Việt...',
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
                                    color: GaonColors.onPrimary),
                              )
                            : const Icon(Icons.arrow_downward_rounded,
                                size: 18, color: GaonColors.onPrimary),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: GaonSpace.sm),

                // 한국어 결과
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('한국어 번역 결과 · Bản dịch tiếng Hàn',
                        style: GaonType.caption.copyWith(
                            fontWeight: FontWeight.w600,
                            color: GaonColors.textSecondary)),
                    const Text('🇰🇷', style: TextStyle(fontSize: 13)),
                  ],
                ),
                const SizedBox(height: GaonSpace.xs),
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(minHeight: 64),
                  padding: const EdgeInsets.symmetric(
                      vertical: GaonSpace.sm, horizontal: GaonSpace.sm),
                  decoration: BoxDecoration(
                    color: GaonColors.primaryLight,
                    borderRadius: BorderRadius.circular(GaonRadius.lg),
                    border:
                        Border.all(width: 2, color: GaonColors.primary),
                  ),
                  child: Text(
                    _message?.outputKo ??
                        '아래 ↓ 버튼을 누르면 정중한 한국어로 번역돼요',
                    style: GaonType.body.copyWith(
                        color: _message != null
                            ? GaonColors.textPrimary
                            : GaonColors.textSecondary,
                        height: 1.7),
                  ),
                ),

                if (_message != null) ...[
                  const SizedBox(height: GaonSpace.sm),
                  // 행정 안내 (RAG)
                  InfoBanner(
                    vi: _message!.adminGuideNative,
                    ko: '행정 절차 안내',
                    color: GaonColors.textSecondary,
                    bg: GaonColors.successLight,
                  ),
                  const SizedBox(height: GaonSpace.sm),
                  Row(
                    children: [
                      Expanded(
                        child: GaonButton(
                          variant: GaonButtonVariant.ghost,
                          label: '복사',
                          icon: const Icon(Icons.copy_rounded,
                              size: 14, color: GaonColors.textPrimary),
                          onTap: _copyMessage,
                        ),
                      ),
                      const SizedBox(width: GaonSpace.xs),
                      Expanded(
                        child: GaonButton(
                          label: '카톡 공유',
                          icon: const Icon(Icons.share_rounded,
                              size: 14, color: GaonColors.onPrimary),
                          onTap: () {
                            // 직접 전송 금지 — 공유 시트로 사용자가 직접 보낸다.
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        '카카오톡 공유 시트가 열립니다 (데모)')));
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
