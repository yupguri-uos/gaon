import 'package:flutter/material.dart';

import '../data/demo_data.dart';
import '../data/locator.dart';
import '../models/schema.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import 'main_shell.dart';

/// S3 온보딩 ② 자녀 등록 (F-ON-4) — 다자녀 지원.
///
/// 주의(SSOT 결정 대기 — fe/CLAUDE.md 참조):
/// - '학교명'은 shared-schema Child에 필드가 없어 UI 전용(로컬).
/// - 학년 초1~6은 UI 전용 — schema ChildGrade는 elem_1~3만.
///   BE 연동 전에 SSOT → schema.py(Literal)·DB CHECK 확장 필요.
class OnboardingChildScreen extends StatefulWidget {
  const OnboardingChildScreen({super.key});

  @override
  State<OnboardingChildScreen> createState() => _OnboardingChildScreenState();
}

class _ChildForm {
  final school = TextEditingController(text: demoSchoolName);
  final name = TextEditingController();
  int gradeNo = 2; // 초1~6 (UI 전용 — schema 확장 대기)
  String classNo = '3';

  void dispose() {
    school.dispose();
    name.dispose();
  }
}

class _OnboardingChildScreenState extends State<OnboardingChildScreen> {
  final _children = [_ChildForm()];

  @override
  void dispose() {
    for (final c in _children) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickGrade(_ChildForm form) async {
    final picked = await showModalBottomSheet<int>(
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
              Text('학년 · Lớp',
                  style: GaonType.h3.copyWith(color: GaonColors.textPrimary)),
              const SizedBox(height: GaonSpace.sm),
              for (var n = 1; n <= 6; n++)
                ListTile(
                  onTap: () => Navigator.of(context).pop(n),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(GaonRadius.md)),
                  tileColor:
                      n == form.gradeNo ? GaonColors.primaryLight : null,
                  title: Text('Lớp $n / 초$n',
                      style: GaonType.bodyLg
                          .copyWith(color: GaonColors.textPrimary)),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) setState(() => form.gradeNo = picked);
  }

  Future<void> _pickClassNo(_ChildForm form) async {
    final picked = await showModalBottomSheet<String>(
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
              Text('반 · Ban',
                  style: GaonType.h3.copyWith(color: GaonColors.textPrimary)),
              const SizedBox(height: GaonSpace.sm),
              for (var n = 1; n <= 5; n++)
                ListTile(
                  onTap: () => Navigator.of(context).pop('$n'),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(GaonRadius.md)),
                  tileColor:
                      '$n' == form.classNo ? GaonColors.primaryLight : null,
                  title: Text('$n반 / Ban $n',
                      style: GaonType.bodyLg
                          .copyWith(color: GaonColors.textPrimary)),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) setState(() => form.classNo = picked);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GaonColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            // 진행 표시 2/2
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  GaonSpace.md, GaonSpace.sm, GaonSpace.md, 0),
              child: Row(
                children: [
                  for (var i = 0; i < 2; i++) ...[
                    Expanded(
                      child: Container(
                        height: 5,
                        decoration: BoxDecoration(
                          color: GaonColors.textPrimary,
                          borderRadius:
                              BorderRadius.circular(GaonRadius.pill),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text('2 / 2',
                      style: GaonType.caption
                          .copyWith(color: GaonColors.textSecondary)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                    GaonSpace.md, GaonSpace.sm, GaonSpace.md, GaonSpace.md),
                children: [
                  Text('자녀 정보를 등록해요',
                      style:
                          GaonType.h1.copyWith(color: GaonColors.textPrimary)),
                  const SizedBox(height: GaonSpace.xxs),
                  Text('Đăng ký thông tin con',
                      style: GaonType.label
                          .copyWith(color: GaonColors.textSecondary)),
                  const SizedBox(height: GaonSpace.lg),

                  for (final (i, form) in _children.indexed)
                    _ChildCard(
                      index: i,
                      form: form,
                      onPickGrade: () => _pickGrade(form),
                      onPickClassNo: () => _pickClassNo(form),
                      onRemove: _children.length > 1
                          ? () => setState(() =>
                              _children.removeAt(i).dispose())
                          : null,
                    ),

                  // 자녀 추가
                  InkWell(
                    onTap: () =>
                        setState(() => _children.add(_ChildForm())),
                    borderRadius: BorderRadius.circular(GaonRadius.xl),
                    child: Container(
                      padding: const EdgeInsets.all(GaonSpace.md),
                      decoration: BoxDecoration(
                        border: Border.all(
                            width: 2,
                            color: GaonColors.primary,
                            style: BorderStyle.solid),
                        borderRadius: BorderRadius.circular(GaonRadius.xl),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.add_rounded,
                              size: 16, color: GaonColors.textSecondary),
                          const SizedBox(width: GaonSpace.xs),
                          Text('자녀 추가 · Thêm con',
                              style: GaonType.body.copyWith(
                                  color: GaonColors.textSecondary)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  GaonSpace.md, GaonSpace.xs, GaonSpace.md, GaonSpace.lg),
              child: GaonButton(
                label: '시작하기',
                subLabel: 'Bắt đầu →',
                onTap: () async {
                  // 입력한 자녀들을 저장소에 등록 → 이후 화면(챗봇·설정·캘린더)에 반영
                  for (final form in _children) {
                    final name = form.name.text.trim();
                    await repository.addChild(
                      // 초4~6은 schema(elem_1~3) 한계로 초3으로 클램프 저장 —
                      // SSOT 학년 확장 반영 시 함께 해제(fe/CLAUDE.md 참조)
                      grade: ChildGrade
                          .values[(form.gradeNo.clamp(1, 3)) - 1],
                      name: name.isEmpty ? null : name,
                      classNo: form.classNo,
                    );
                  }
                  if (!context.mounted) return;
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const MainShell()),
                    (route) => false,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChildCard extends StatelessWidget {
  const _ChildCard({
    required this.index,
    required this.form,
    required this.onPickGrade,
    required this.onPickClassNo,
    this.onRemove,
  });

  final int index;
  final _ChildForm form;
  final VoidCallback onPickGrade;
  final VoidCallback onPickClassNo;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: GaonSpace.sm),
      padding: const EdgeInsets.all(GaonSpace.md),
      decoration: BoxDecoration(
        color: GaonColors.surface,
        borderRadius: BorderRadius.circular(GaonRadius.xl),
        border: Border.all(width: 2, color: GaonColors.textPrimary),
        boxShadow: GaonShadow.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('자녀 ${index + 1}',
                    style: GaonType.body.copyWith(
                        fontWeight: FontWeight.w700,
                        color: GaonColors.textPrimary)),
              ),
              if (onRemove != null)
                GestureDetector(
                  onTap: onRemove,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: 3, horizontal: 10),
                    decoration: BoxDecoration(
                      color: GaonColors.warningLight,
                      borderRadius: BorderRadius.circular(GaonRadius.pill),
                    ),
                    child: Text('삭제',
                        style: GaonType.micro.copyWith(
                            fontWeight: FontWeight.w600,
                            color: GaonColors.warning)),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(
                      vertical: 3, horizontal: 10),
                  decoration: BoxDecoration(
                    color: GaonColors.primaryLight,
                    borderRadius: BorderRadius.circular(GaonRadius.pill),
                  ),
                  child: Text('등록 중',
                      style: GaonType.micro.copyWith(
                          fontWeight: FontWeight.w600,
                          color: GaonColors.textPrimary)),
                ),
            ],
          ),
          const SizedBox(height: GaonSpace.sm),
          _field('학교명 · Tên trường', form.school, '예) 가온초등학교'),
          const SizedBox(height: GaonSpace.xs),
          _field('이름 · Tên con', form.name, '자녀 이름'),
          const SizedBox(height: GaonSpace.xs),
          Text('학년·반 · Lớp',
              style: GaonType.micro.copyWith(
                  fontWeight: FontWeight.w600,
                  color: GaonColors.textSecondary)),
          const SizedBox(height: 3),
          Row(
            children: [
              Expanded(
                child: _darkSelector(
                    'Lớp ${form.gradeNo} / 초${form.gradeNo}', onPickGrade),
              ),
              const SizedBox(width: GaonSpace.xs),
              Expanded(
                child: _darkSelector('${form.classNo}반', onPickClassNo),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _field(
      String label, TextEditingController controller, String hint) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: GaonType.micro.copyWith(
                fontWeight: FontWeight.w600,
                color: GaonColors.textSecondary)),
        const SizedBox(height: 3),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: GaonColors.bg,
            borderRadius: BorderRadius.circular(GaonRadius.md),
            border: Border.all(color: GaonColors.border),
          ),
          child: TextField(
            controller: controller,
            style: GaonType.body.copyWith(color: GaonColors.textPrimary),
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              hintText: hint,
              hintStyle:
                  GaonType.body.copyWith(color: GaonColors.textSecondary),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),
      ],
    );
  }

  Widget _darkSelector(String label, VoidCallback onTap) {
    return Material(
      color: GaonColors.textPrimary,
      borderRadius: BorderRadius.circular(GaonRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(GaonRadius.md),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          child: Text(label,
              style: GaonType.body.copyWith(
                  fontWeight: FontWeight.w700, color: GaonColors.bg)),
        ),
      ),
    );
  }
}
