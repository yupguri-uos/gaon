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
  // 초기 미선택(QA A-1: '2학년' 등 기본 선택 금지) — 고르기 전엔 등록 불가.
  ChildGrade? grade;
  // 자유 입력(숫자 반·순우리말 반 모두 지원, QA 2026-07-11). DB도 text라 그대로 저장.
  final classNo = TextEditingController();

  /// 이름·학교·학년·반 모두 채워졌는가(QA A-1 필수화).
  bool get complete =>
      name.text.trim().isNotEmpty &&
      school.text.trim().isNotEmpty &&
      grade != null &&
      classNo.text.trim().isNotEmpty;

  void dispose() {
    school.dispose();
    name.dispose();
    classNo.dispose();
  }
}

/// '시작하기' 검증 팝업용 — 자녀 하나의 미입력 항목 묶음.
class _MissingChild {
  const _MissingChild(this.index, this.fields);
  final int index; // 0-based (표시 시 +1)
  final List<String> fields; // 병기 라벨(biLine)
}

class _OnboardingChildScreenState extends State<OnboardingChildScreen> {
  static const _maxChildren = 5; // BE MAX_CHILDREN과 동일(자녀 수 상한, QA 2026-07-11)
  final _children = [_ChildForm()];

  // 제출 중 재진입 가드(적대적 리뷰 C-2) — POST /onboarding·/children은
  // 멱등이 아니라 더블 탭이 자녀 중복 등록을 만든다.
  bool _submitting = false;

  bool get _formsComplete => _children.every((f) => f.complete);

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
              // 작은 화면(키보드 위 시트)에서도 넘치지 않게 목록만 스크롤(QA A-1)
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final g in ChildGrade.values)
                      ListTile(
                        onTap: () => Navigator.of(context).pop(g),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(GaonRadius.md),
                        ),
                        tileColor: g == form.grade
                            ? GaonColors.primaryLight
                            : null,
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
            ],
          ),
        ),
      ),
    );
    if (picked != null) setState(() => form.grade = picked);
  }

  /// 미입력 항목을 자녀별로 모은다 — '시작하기' 검증용. 모두 채워졌으면 빈 리스트.
  List<_MissingChild> _missingChildren() {
    final result = <_MissingChild>[];
    for (final (i, f) in _children.indexed) {
      final fields = <String>[
        if (f.name.text.trim().isEmpty) biLine('이름', 'Tên', '姓名'),
        if (f.school.text.trim().isEmpty) biLine('학교명', 'Tên trường', '学校名称'),
        if (f.grade == null) biLine('학년', 'Lớp', '年级'),
        if (f.classNo.text.trim().isEmpty) biLine('반', 'Số lớp', '班级'),
      ];
      if (fields.isNotEmpty) result.add(_MissingChild(i, fields));
    }
    return result;
  }

  /// 어떤 정보가 비었는지 자녀별로 알려주는 팝업(요청) —
  /// 비활성 버튼 대신, '시작하기'를 누르면 빠진 항목을 능동적으로 안내한다.
  Future<void> _showMissingDialog(List<_MissingChild> missing) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: GaonColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GaonRadius.xl),
        ),
        title: Text(
          biLines(
            '입력하지 않은 정보가 있어요',
            'Còn thông tin chưa điền',
            '还有信息未填写',
          ),
          style: GaonType.h3.copyWith(color: GaonColors.textPrimary),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final m in missing) ...[
                Text(
                  biLine(
                    '자녀 ${m.index + 1}',
                    'Con ${m.index + 1}',
                    '孩子 ${m.index + 1}',
                  ),
                  style: GaonType.label.copyWith(
                    fontWeight: FontWeight.w700,
                    color: GaonColors.textPrimary,
                  ),
                ),
                const SizedBox(height: GaonSpace.xxs),
                for (final field in m.fields)
                  Padding(
                    padding: const EdgeInsets.only(
                      left: GaonSpace.xs,
                      bottom: 2,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 6),
                          child: Icon(
                            Icons.circle,
                            size: 5,
                            color: GaonColors.warning,
                          ),
                        ),
                        const SizedBox(width: GaonSpace.xs),
                        Expanded(
                          child: Text(
                            field,
                            style: GaonType.caption.copyWith(
                              color: GaonColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: GaonSpace.sm),
              ],
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(
          GaonSpace.md,
          0,
          GaonSpace.md,
          GaonSpace.md,
        ),
        actions: [
          GaonButton(
            label: biLine('확인', 'Đã hiểu', '知道了'),
            variant: GaonButtonVariant.ghost,
            fullWidth: false,
            onTap: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  /// 입력한 자녀들을 등록하고 메인으로 진입(F-ON-1). 첫 자녀 = POST /onboarding.
  /// 호출 전 필수 항목이 모두 채워졌음이 보장된다(_missingChildren 검증 통과).
  Future<void> _submit() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _submitting = true);
    try {
      // API 모드: 첫 자녀 = POST /onboarding(프로필+자녀), 나머지는 POST /children.
      final repo = repository;
      for (final (i, form) in _children.indexed) {
        final name = form.name.text.trim();
        final school = form.school.text.trim();
        final classNo = form.classNo.text.trim();
        if (i == 0 && repo is ApiRepository) {
          // 언어=국가 통합: vi→VN, zh→CN 자동 매핑
          final lang = appLanguage.value;
          await repo.submitOnboarding(
            originCountry: lang == NativeLanguage.zh
                ? OriginCountry.cn
                : OriginCountry.vn,
            nativeLanguage: lang,
            childGrade: form.grade!,
            childName: name,
            childClassNo: classNo,
            childSchoolName: school,
          );
        } else {
          await repo.addChild(
            grade: form.grade!,
            name: name,
            classNo: classNo,
            schoolName: school,
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
              '登记失败——请检查网络',
            ),
          ),
        ),
      );
      // 실패 시 버튼 복구 — 재시도 가능(C-2)
      if (mounted) setState(() => _submitting = false);
      return;
    }
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MainShell()),
      (route) => false,
    );
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
                // 스크롤로 키보드 닫기(QA T-4 — iOS 공통 처리)
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
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
                  // 학교명만 한국어(학교 검색·소통용). 자녀 이름은 구분용 —
                  // 실명 불필요(별명 가능, 결정 #7-PII 최소 수집, 2026-07-14).
                  Text(
                    biLine(
                      '학교명은 한국어로, 이름은 구분하기 쉬우면 돼요',
                      'Tên trường bằng tiếng Hàn; tên con chỉ cần dễ phân biệt',
                      '学校名请用韩语；孩子名称易区分即可',
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
              // 이름·학교·학년·반 필수(QA A-1) — 텍스트 변경에도 버튼 상태가
              // 즉시 갱신되게 전 컨트롤러를 구독한다.
              child: ListenableBuilder(
                listenable: Listenable.merge([
                  for (final f in _children) ...[f.name, f.school, f.classNo],
                ]),
                builder: (context, _) => Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!_formsComplete) ...[
                      Text(
                        biLine(
                          '이름·학교·학년·반을 모두 입력하면 시작할 수 있어요',
                          'Điền đủ tên, trường, lớp và số lớp để bắt đầu',
                          '填写姓名、学校、年级和班级后即可开始',
                        ),
                        textAlign: TextAlign.center,
                        style: GaonType.micro.copyWith(
                          color: GaonColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: GaonSpace.xxs),
                    ],
                    GaonButton(
                      label: _submitting
                          ? biLine('등록 중...', 'Đang đăng ký...', '登记中…')
                          : '${bi('Bắt đầu', '开始')} →',
                      subLabel: _submitting ? null : '시작하기',
                      // 미완성이어도 누를 수 있게 두고(제출 중만 비활성, C-2),
                      // 누르면 빠진 항목을 자녀별 팝업으로 안내한다(요청) → 완성 시 등록.
                      onTap: _submitting
                          ? null
                          : () async {
                              final missing = _missingChildren();
                              if (missing.isNotEmpty) {
                                await _showMissingDialog(missing);
                                return;
                              }
                              await _submit();
                            },
                    ),
                  ],
                ),
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
            // 실명이 아닌 '구분용 이름'(별명 가능) — PII 최소화(결정 #7-PII)
            biLine('자녀를 구분할 이름', 'Tên để phân biệt con', '区分孩子的名称'),
            form.name,
            // 입력칸 안내는 모국어만(한국어 제거) — '…' 잘림 방지(요청).
            bi(
              'Biệt danh cũng được (VD: bé lớn)',
              '昵称也可以（例：老大）',
            ),
            maxLength: 5, // 자녀 이름 5글자 제한(넘으면 카운터·입력 차단으로 경고)
          ),
          const SizedBox(height: GaonSpace.xs),
          Text(
            biLine('학년·반', 'Lớp · Số lớp', '年级·班'),
            style: GaonType.micro.copyWith(
              fontWeight: FontWeight.w600,
              color: GaonColors.textSecondary,
            ),
          ),
          const SizedBox(height: 3),
          Row(
            children: [
              Expanded(
                child: _darkSelector(
                  // 초기 미선택(QA A-1) — 고르기 전엔 플레이스홀더 표시
                  form.grade?.label ?? biLine('학년 선택', 'Chọn lớp', '选择年级'),
                  onPickGrade,
                ),
              ),
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
                    textInputAction: TextInputAction.done, // QA T-4
                    style: GaonType.body.copyWith(
                      color: GaonColors.textPrimary,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: biLine('반 (예: 3, 다솜)', 'Số lớp', '班'),
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

  Widget _field(
    String label,
    TextEditingController controller,
    String hint, {
    int? maxLength, // 지정 시 최대 글자수 제한 + 'N/max' 카운터 표시
  }) {
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
            maxLength: maxLength, // null이면 제한 없음
            textInputAction: TextInputAction.done, // 완료로 키보드 닫기(QA T-4)
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
