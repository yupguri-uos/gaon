import 'package:flutter/material.dart';

import '../data/api_repository.dart';
import '../data/locator.dart';
import '../models/display.dart';
import '../data/app_lang.dart';
import '../models/schema.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import 'main_shell.dart';

/// S3 온보딩 ② 자녀 등록 (F-ON-4) — 다자녀 지원.
/// 학년(초1~6)·학교명 모두 shared-schema 정본 반영 완료(마이그레이션 0007·0009).
/// API 모드: 첫 자녀는 POST /onboarding(프로필+자녀), 나머지는 POST /children.
/// 출신국·모국어는 언어 선택(appLanguage)에서 도출 — 언어=국가 통합(2026-07-13),
/// vi→VN·zh→CN 매핑으로 BE에는 기존대로 둘 다 전송한다(BE 무변경).
class OnboardingChildScreen extends StatefulWidget {
  const OnboardingChildScreen({super.key});

  @override
  State<OnboardingChildScreen> createState() => _OnboardingChildScreenState();
}

class _ChildForm {
  final school = TextEditingController(); // 프리필 없음 — 힌트 텍스트로 안내
  final name = TextEditingController();
  ChildGrade grade = ChildGrade.elem1; // 데모 잔재(2학년) 기본값 제거 — 1학년 기본
  // 자유 입력(숫자 반·순우리말 반 모두 지원, QA 2026-07-11). DB도 text라 그대로 저장.
  final classNo = TextEditingController();

  void dispose() {
    school.dispose();
    name.dispose();
    classNo.dispose();
  }
}

class _OnboardingChildScreenState extends State<OnboardingChildScreen> {
  static const _maxChildren = 5; // BE MAX_CHILDREN과 동일(자녀 수 상한, QA 2026-07-11)
  final _children = [_ChildForm()];

  @override
  void dispose() {
    for (final c in _children) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickGrade(_ChildForm form) async {
    final picked = await showModalBottomSheet<ChildGrade>(
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
                biLine('학년', 'Lớp', '年级'),
                style: GaonType.h3.copyWith(color: GaonColors.textPrimary),
              ),
              const SizedBox(height: GaonSpace.sm),
              for (final g in ChildGrade.values)
                ListTile(
                  onTap: () => Navigator.of(context).pop(g),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(GaonRadius.md),
                  ),
                  tileColor: g == form.grade ? GaonColors.primaryLight : null,
                  title: Text(
                    g.label,
                    style: GaonType.bodyLg.copyWith(
                      color: GaonColors.textPrimary,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) setState(() => form.grade = picked);
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
                GaonSpace.md,
                GaonSpace.sm,
                GaonSpace.md,
                0,
              ),
              child: Row(
                children: [
                  // 뒤로가기 — 본인 정보(1/2)로 복귀(QA: step 2에서 되돌아갈 길 없음)
                  Material(
                    color: GaonColors.primaryLight,
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
                          color: GaonColors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: GaonSpace.xs),
                  for (var i = 0; i < 2; i++) ...[
                    Expanded(
                      child: Container(
                        height: 5,
                        decoration: BoxDecoration(
                          color: GaonColors.textPrimary,
                          borderRadius: BorderRadius.circular(GaonRadius.pill),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    '2 / 2',
                    style: GaonType.caption.copyWith(
                      color: GaonColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  GaonSpace.md,
                  GaonSpace.sm,
                  GaonSpace.md,
                  GaonSpace.md,
                ),
                children: [
                  Text(
                    bi('Đăng ký thông tin con', '登记孩子信息'),
                    style: GaonType.h1.copyWith(color: GaonColors.textPrimary),
                  ),
                  const SizedBox(height: GaonSpace.xxs),
                  Text(
                    '자녀 정보를 등록해요',
                    style: GaonType.label.copyWith(
                      color: GaonColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: GaonSpace.xs),
                  // 학교가 한국어 문서로 소통하므로 이름·학교명은 한국어 표기 권장
                  Text(
                    biLine(
                      '이름·학교명은 한국어로 적어 주세요',
                      'Vui lòng viết tên và tên trường bằng tiếng Hàn',
                      '姓名和学校名请用韩语填写',
                    ),
                    style: GaonType.caption.copyWith(
                      color: GaonColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: GaonSpace.lg),

                  for (final (i, form) in _children.indexed)
                    _ChildCard(
                      index: i,
                      form: form,
                      onPickGrade: () => _pickGrade(form),
                      onRemove: _children.length > 1
                          ? () =>
                                setState(() => _children.removeAt(i).dispose())
                          : null,
                    ),

                  // 자녀 추가 — BE 상한(5명)과 동일. 도달 시 비활성 + 안내.
                  InkWell(
                    onTap: _children.length >= _maxChildren
                        ? null
                        : () => setState(() => _children.add(_ChildForm())),
                    borderRadius: BorderRadius.circular(GaonRadius.xl),
                    child: Container(
                      padding: const EdgeInsets.all(GaonSpace.md),
                      decoration: BoxDecoration(
                        border: Border.all(
                          width: 2,
                          color: GaonColors.primary,
                          style: BorderStyle.solid,
                        ),
                        borderRadius: BorderRadius.circular(GaonRadius.xl),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.add_rounded,
                            size: 16,
                            color: GaonColors.textSecondary,
                          ),
                          const SizedBox(width: GaonSpace.xs),
                          Text(
                            biLine('자녀 추가', 'Thêm con', '添加子女'),
                            style: GaonType.body.copyWith(
                              color: GaonColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
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
                label: '${bi('Bắt đầu', '开始')} →',
                subLabel: '시작하기',
                onTap: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final navigator = Navigator.of(context);
                  // 이름·학교 미입력이면 실수 방지 확인(QA) — 이름은 PII 선택
                  // 입력(결정 #7)이라 막지는 않고 되묻기만 한다.
                  final hasBlank = _children.any(
                    (f) =>
                        f.name.text.trim().isEmpty ||
                        f.school.text.trim().isEmpty,
                  );
                  if (hasBlank) {
                    final proceed = await showDialog<bool>(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        backgroundColor: GaonColors.surface,
                        title: Text(
                          biLines(
                            '이름·학교명 없이 등록할까요?',
                            'Đăng ký mà không có tên/trường?',
                            '不填姓名/学校继续注册吗？',
                          ),
                          style: GaonType.h3.copyWith(
                            color: GaonColors.textPrimary,
                          ),
                        ),
                        content: Text(
                          biLines(
                            '나중에 설정 > 자녀 관리에서 채울 수 있어요',
                            'Có thể bổ sung sau trong Cài đặt > Quản lý con',
                            '之后可以在 设置 > 子女管理 中补填',
                          ),
                          style: GaonType.caption.copyWith(
                            color: GaonColors.textSecondary,
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () =>
                                Navigator.of(dialogContext).pop(false),
                            child: Text(
                              biLine('계속 입력', 'Nhập tiếp', '继续填写'),
                              style: GaonType.body.copyWith(
                                color: GaonColors.textPrimary,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () =>
                                Navigator.of(dialogContext).pop(true),
                            child: Text(
                              biLine('이대로 등록', 'Đăng ký luôn', '直接注册'),
                              style: GaonType.body.copyWith(
                                fontWeight: FontWeight.w700,
                                color: GaonColors.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                    if (proceed != true) return;
                  }
                  try {
                    // 입력한 자녀들을 등록 → 이후 화면(챗봇·설정·캘린더)에 반영.
                    // API 모드: 첫 자녀 = POST /onboarding(F-ON-1, 프로필+자녀 생성).
                    final repo = repository;
                    for (final (i, form) in _children.indexed) {
                      final name = form.name.text.trim();
                      final school = form.school.text.trim();
                      final classNo = form.classNo.text.trim();
                      if (i == 0 && repo is ApiRepository) {
                        // 언어=국가 통합: 선택 언어에서 국가 자동 매핑(vi→VN, zh→CN)
                        final lang = appLanguage.value;
                        await repo.submitOnboarding(
                          originCountry: lang == NativeLanguage.zh
                              ? OriginCountry.cn
                              : OriginCountry.vn,
                          nativeLanguage: lang,
                          childGrade: form.grade,
                          childName: name.isEmpty ? null : name,
                          childClassNo: classNo.isEmpty ? null : classNo,
                          childSchoolName: school.isEmpty ? null : school,
                        );
                      } else {
                        await repo.addChild(
                          grade: form.grade,
                          name: name.isEmpty ? null : name,
                          classNo: classNo.isEmpty ? null : classNo,
                          schoolName: school.isEmpty ? null : school,
                        );
                      }
                    }
                  } catch (e) {
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(
                          biLines(
                            '등록에 실패했어요 — 네트워크를 확인해 주세요 ($e)',
                            'Đăng ký thất bại — hãy kiểm tra mạng',
                            '注册失败——请检查网络',
                          ),
                        ),
                      ),
                    );
                    return;
                  }
                  navigator.pushAndRemoveUntil(
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
    this.onRemove,
  });

  final int index;
  final _ChildForm form;
  final VoidCallback onPickGrade;
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
                child: Text(
                  biLine('자녀 ${index + 1}', 'Con ${index + 1}', '孩子 ${index + 1}'),
                  style: GaonType.body.copyWith(
                    fontWeight: FontWeight.w700,
                    color: GaonColors.textPrimary,
                  ),
                ),
              ),
              if (onRemove != null)
                GestureDetector(
                  onTap: onRemove,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 3,
                      horizontal: 10,
                    ),
                    decoration: BoxDecoration(
                      color: GaonColors.warningLight,
                      borderRadius: BorderRadius.circular(GaonRadius.pill),
                    ),
                    child: Text(
                      biLine('삭제', 'Xóa', '删除'),
                      style: GaonType.micro.copyWith(
                        fontWeight: FontWeight.w600,
                        color: GaonColors.warning,
                      ),
                    ),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 3,
                    horizontal: 10,
                  ),
                  decoration: BoxDecoration(
                    color: GaonColors.primaryLight,
                    borderRadius: BorderRadius.circular(GaonRadius.pill),
                  ),
                  child: Text(
                    biLine('등록 중', 'Đang đăng ký', '登记中'),
                    style: GaonType.micro.copyWith(
                      fontWeight: FontWeight.w600,
                      color: GaonColors.textPrimary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: GaonSpace.sm),
          _field(
            biLine('학교명', 'Tên trường', '学校名称'),
            form.school,
            '${bi('VD', '例')}) 가온초등학교',
          ),
          const SizedBox(height: GaonSpace.xs),
          _field(
            biLine('이름', 'Tên con', '孩子姓名'),
            form.name,
            biLine('자녀 이름(한국어)', 'Tên con (tiếng Hàn)', '孩子姓名（韩语）'),
          ),
          const SizedBox(height: GaonSpace.xs),
          Text(
            biLine('학년·반', 'Lớp · Ban', '年级·班'),
            style: GaonType.micro.copyWith(
              fontWeight: FontWeight.w600,
              color: GaonColors.textSecondary,
            ),
          ),
          const SizedBox(height: 3),
          Row(
            children: [
              Expanded(child: _darkSelector(form.grade.label, onPickGrade)),
              const SizedBox(width: GaonSpace.xs),
              // 반은 자유 입력 — 숫자 반 외에 순우리말 반(예: 다솜)도 있다
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: GaonColors.bg,
                    borderRadius: BorderRadius.circular(GaonRadius.md),
                    border: Border.all(color: GaonColors.border),
                  ),
                  child: TextField(
                    controller: form.classNo,
                    style: GaonType.body.copyWith(
                      color: GaonColors.textPrimary,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: biLine('반 (예: 3, 다솜)', 'Ban', '班'),
                      hintStyle: GaonType.body.copyWith(
                        color: GaonColors.textSecondary,
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController controller, String hint) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GaonType.micro.copyWith(
            fontWeight: FontWeight.w600,
            color: GaonColors.textSecondary,
          ),
        ),
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
              hintStyle: GaonType.body.copyWith(
                color: GaonColors.textSecondary,
              ),
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
          child: Text(
            label,
            style: GaonType.body.copyWith(
              fontWeight: FontWeight.w700,
              color: GaonColors.bg,
            ),
          ),
        ),
      ),
    );
  }
}
