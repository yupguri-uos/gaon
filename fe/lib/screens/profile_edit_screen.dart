import 'package:flutter/material.dart';

import '../data/api_repository.dart';
import '../data/app_lang.dart';
import '../data/app_nav.dart';
import '../data/locator.dart';
import '../data/repository.dart';
import '../models/display.dart';
import '../models/schema.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';

/// S14 개인정보 수정 — 학부모 정보 + 자녀 카드 관리.
/// 프로필 변경 = PATCH /profile, 자녀 추가/수정/삭제 = POST·PATCH·DELETE /children (F-ON-1·4).
class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({super.key, this.focusChildren = false});

  /// 설정의 '자녀 관리'로 진입하면 자녀 섹션으로 바로 스크롤(진입 구분, QA 2026-07-11).
  final bool focusChildren;

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  late Future<(User, List<Child>)> _future = _load();

  final _childrenSectionKey = GlobalKey();
  int _focusRetries = 30; // 초기 로드(FutureBuilder) 완료까지 프레임 단위 재시도 한도

  @override
  void initState() {
    super.initState();
    if (widget.focusChildren) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToChildren());
    }
  }

  void _scrollToChildren() {
    if (!mounted) return;
    final ctx = _childrenSectionKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 300),
      );
      return;
    }
    // 데이터 로드 전이면 섹션이 아직 없다 — 다음 프레임에 재시도
    if (_focusRetries-- > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToChildren());
    }
  }

  // 낙관적 UI — 삭제/추가 직후 서버 재조회를 기다리지 않고 즉시 화면 반영.
  // null이면 _future 결과를, 값이 있으면 이 리스트를 그린다.
  List<Child>? _childrenOverride;

  Future<(User, List<Child>)> _load() async {
    final user = repository.getCurrentUser();
    final children = repository.getChildren();
    return (await user, await children);
  }

  /// 자녀 카드 테두리 색 — 배정된 color(§17.4), 없으면 기본.
  Color _childBorder(Child c) => c.color == null
      ? GaonColors.textPrimary
      : Color(int.parse('FF${c.color!.replaceFirst('#', '')}', radix: 16));

  /// 화면 전체 리로드(스피너) 없이 자녀 목록만 서버 기준으로 재동기화.
  Future<void> _resyncChildren() async {
    try {
      final fresh = await repository.getChildren();
      if (mounted) setState(() => _childrenOverride = fresh);
      childrenVersion.value++; // 홈(챗봇)·문자 탭에 자녀 정보 변경을 알림
    } catch (_) {} // 실패 시 낙관적 상태 유지 — 다음 진입 때 재조회
  }

  void _snack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// F-ON-4: 자녀 추가/수정 폼 — 온보딩과 동일 항목(이름·학교·학년·반).
  /// [edit]가 null이면 추가(POST /children), 있으면 해당 자녀 수정(PATCH /children/{id}).
  /// (기가입 계정은 온보딩을 스킵하므로 여기가 자녀 추가 진입점)
  Future<void> _showChildSheet(int existingCount, {Child? edit}) async {
    final nameCtrl = TextEditingController(text: edit?.name ?? '');
    final schoolCtrl = TextEditingController(text: edit?.schoolName ?? '');
    // 반은 자유 입력 — 숫자 반 외에 순우리말 반(예: 다솜)도 있다(QA 2026-07-11)
    final classCtrl = TextEditingController(text: edit?.classNo ?? '');
    // 추가 모드는 초기 미선택(QA A-1 — '2학년' 기본값 금지), 수정 모드는 기존 값
    ChildGrade? grade = edit?.grade;
    bool complete() =>
        nameCtrl.text.trim().isNotEmpty &&
        schoolCtrl.text.trim().isNotEmpty &&
        classCtrl.text.trim().isNotEmpty &&
        grade != null;

    final submitted = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: GaonColors.surface,
      isScrollControlled: true, // 키보드 대응
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(GaonRadius.xxl),
        ),
      ),
      builder: (sheetContext) => StatefulBuilder(
        // 작은 화면 + 키보드에서 시트가 넘치지 않게 스크롤 허용(QA A-1 overflow)
        builder: (sheetContext, setSheetState) => SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.only(
            left: GaonSpace.lg,
            right: GaonSpace.lg,
            top: GaonSpace.lg,
            bottom:
                MediaQuery.of(sheetContext).viewInsets.bottom + GaonSpace.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                edit == null
                    ? biLine('자녀 추가', 'Thêm con', '添加子女')
                    : biLine('자녀 수정', 'Sửa thông tin con', '修改子女信息'),
                style: GaonType.h3.copyWith(color: GaonColors.textPrimary),
              ),
              const SizedBox(height: GaonSpace.xxs),
              // 학교명만 한국어(학교 검색용). 자녀 이름은 구분용 —
              // 실명 불필요(별명 가능, 결정 #7-PII 최소 수집, 2026-07-14).
              Text(
                biLine(
                  '학교명은 한국어로, 이름은 구분하기 쉬우면 돼요',
                  'Tên trường bằng tiếng Hàn; tên con chỉ cần dễ phân biệt',
                  '学校名请用韩语；孩子名称易区分即可',
                ),
                style: GaonType.micro.copyWith(
                  color: GaonColors.textSecondary,
                ),
              ),
              const SizedBox(height: GaonSpace.sm),
              _sheetField(
                biLine('자녀를 구분할 이름', 'Tên để phân biệt con', '区分孩子的名称'),
                nameCtrl,
                // 입력칸 안내는 모국어만(한국어 제거) — '…'으로 잘리지 않게(요청).
                bi(
                  'Biệt danh cũng được (VD: bé lớn)',
                  '昵称也可以（例：老大）',
                ),
                maxLength: 5, // 자녀 이름 5글자 제한(넘으면 카운터·입력 차단으로 경고)
              ),
              const SizedBox(height: GaonSpace.sm),
              _sheetField(
                biLine('학교명', 'Tên trường', '学校名称'),
                schoolCtrl,
                '${bi('VD', '例')}) 가온초등학교',
              ),
              const SizedBox(height: GaonSpace.sm),
              Text(
                biLine('학년', 'Lớp', '年级'),
                style: GaonType.micro.copyWith(
                  fontWeight: FontWeight.w600,
                  color: GaonColors.textSecondary,
                ),
              ),
              const SizedBox(height: GaonSpace.xxs),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final g in ChildGrade.values)
                    _sheetChip(
                      label: g.label,
                      selected: grade == g,
                      onTap: () => setSheetState(() => grade = g),
                    ),
                ],
              ),
              const SizedBox(height: GaonSpace.sm),
              _sheetField(
                biLine('반', 'Số lớp', '班'),
                classCtrl,
                '${bi('VD', '例')}) 3 ${bi('hoặc', '或')} 다솜',
              ),
              const SizedBox(height: GaonSpace.lg),
              // 이름·학교·학년·반 필수(QA A-1) — 미완성이면 비활성 + 인라인 안내
              ListenableBuilder(
                listenable: Listenable.merge([nameCtrl, schoolCtrl, classCtrl]),
                builder: (context, _) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!complete()) ...[
                      Text(
                        biLine(
                          '이름·학교·학년·반을 모두 입력해 주세요',
                          'Điền đủ tên, trường, lớp và số lớp',
                          '请填写姓名、学校、年级和班级',
                        ),
                        textAlign: TextAlign.center,
                        style: GaonType.micro.copyWith(
                          color: GaonColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: GaonSpace.xxs),
                    ],
                    GaonButton(
                      label: edit == null
                          ? biLine('등록하기', 'Đăng ký', '登记')
                          : biLine('저장하기', 'Lưu', '保存'),
                      onTap: complete()
                          ? () => Navigator.of(sheetContext).pop(true)
                          : null,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    // 시트 닫힘 애니메이션이 끝난 뒤 정리 — 즉시 dispose하면 닫히는 중인
    // TextField가 컨트롤러를 참조해 프레임워크 단언 크래시(_dependents.isEmpty).
    Future.delayed(const Duration(seconds: 1), () {
      nameCtrl.dispose();
      schoolCtrl.dispose();
      classCtrl.dispose();
    });
    if (submitted != true) return;

    final name = nameCtrl.text.trim();
    final school = schoolCtrl.text.trim();
    final classNo = classCtrl.text.trim();
    try {
      if (edit == null) {
        await repository.addChild(
          // 제출 버튼이 complete()일 때만 활성이라 여기선 항상 채워져 있다(QA A-1)
          grade: grade!,
          name: name,
          classNo: classNo,
          schoolName: school,
          // 색은 팔레트 순환 배정(§17.4) — 기존 자녀 수 기준
          color: childColorPalette[existingCount % childColorPalette.length],
        );
        if (!mounted) return;
        _snack(biLine('$name 등록 완료!', 'Đã đăng ký xong!', '登记完成！'));
      } else {
        await repository.updateChild(
          childId: edit.childId,
          grade: grade,
          name: name,
          classNo: classNo,
          schoolName: school,
        );
        if (!mounted) return;
        _snack(
          biLine(
            '${name.isEmpty ? '자녀' : name} 정보를 수정했어요',
            'Đã cập nhật thông tin',
            '已修改信息',
          ),
        );
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      // 400은 서버 검증 실패(자녀 수 상한·PII 동의 등) — 안내 메시지를 그대로 보여준다.
      _snack(
        e.statusCode == 400
            ? e.message
            : (edit == null
                  ? biLines(
                      '등록에 실패했어요 — 잠시 후 다시 시도해 주세요',
                      'Đăng ký thất bại — thử lại sau',
                      '登记失败——请稍后再试',
                    )
                  : biLines(
                      '수정에 실패했어요 — 잠시 후 다시 시도해 주세요',
                      'Cập nhật thất bại — thử lại sau',
                      '修改失败——请稍后再试',
                    )),
      );
    } catch (e) {
      if (!mounted) return;
      _snack(
        edit == null
            ? biLines(
                '등록에 실패했어요 — 잠시 후 다시 시도해 주세요',
                'Đăng ký thất bại — thử lại sau',
                '登记失败——请稍后再试',
              )
            : biLines(
                '수정에 실패했어요 — 잠시 후 다시 시도해 주세요',
                'Cập nhật thất bại — thử lại sau',
                '修改失败——请稍后再试',
              ),
      );
    } finally {
      // 스피너 없이 자녀 목록만 갱신(변경 사항 즉시 표시)
      if (mounted) await _resyncChildren();
    }
  }

  Widget _sheetField(
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

  Widget _sheetChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 14),
        decoration: BoxDecoration(
          color: selected ? GaonColors.textPrimary : GaonColors.primaryLight,
          borderRadius: BorderRadius.circular(GaonRadius.pill),
        ),
        child: Text(
          label,
          style: GaonType.label.copyWith(
            color: selected ? GaonColors.onPrimary : GaonColors.textPrimary,
          ),
        ),
      ),
    );
  }

  /// F-ON-4: 자녀 삭제 — 확인 즉시 화면에서 제거(낙관적), 서버 삭제는 뒤에서.
  Future<void> _deleteChild(Child child, List<Child> current) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: GaonColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GaonRadius.xl),
        ),
        title: Text(
          '${child.name ?? biLine('자녀', 'Con', '孩子')} ${biLine('삭제', 'Xóa', '删除')}',
          style: GaonType.h3.copyWith(color: GaonColors.textPrimary),
        ),
        content: Text(
          biLines(
            '이 자녀 정보를 삭제할까요?',
            'Xóa thông tin con này?',
            '要删除这个孩子的信息吗？',
          ),
          style: GaonType.body.copyWith(color: GaonColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              biLine('취소', 'Hủy', '取消'),
              style: GaonType.body.copyWith(color: GaonColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              biLine('삭제', 'Xóa', '删除'),
              style: GaonType.body.copyWith(
                fontWeight: FontWeight.w700,
                color: GaonColors.warning,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    // 서버 응답을 기다리지 않고 카드부터 제거 — 실패하면 재동기화가 되살린다
    setState(
      () => _childrenOverride = [
        for (final c in current)
          if (c.childId != child.childId) c,
      ],
    );
    _snack(
      biLine('${child.name ?? '자녀'} 정보를 삭제했어요', 'Đã xóa', '已删除'),
    );
    try {
      await repository.deleteChild(child.childId);
    } on ApiException catch (e) {
      if (!mounted) return;
      // 404 = 이미 삭제됨(중복 탭 등) — 화면 상태 그대로 두면 됨
      if (e.statusCode != 404) {
        _snack(
          biLine('삭제에 실패했어요 (오류 ${e.statusCode})', 'Xóa thất bại', '删除失败'),
        );
        await _resyncChildren();
      }
    } catch (e) {
      if (!mounted) return;
      _snack(
        biLines(
          '삭제에 실패했어요 — 잠시 후 다시 시도해 주세요',
          'Xóa thất bại — thử lại sau',
          '删除失败——请稍后再试',
        ),
      );
      await _resyncChildren();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GaonColors.bg,
      body: SafeArea(
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
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        bi('Chỉnh sửa hồ sơ', '修改个人信息'),
                        style: GaonType.h3.copyWith(
                          color: GaonColors.textPrimary,
                        ),
                      ),
                      Text(
                        '개인정보 수정',
                        style: GaonType.micro.copyWith(
                          color: GaonColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            Expanded(
              child: FutureBuilder(
                future: _future,
                builder: (context, snap) {
                  if (snap.hasError) {
                    return GaonAsyncError(
                      message: biLines(
                        '정보를 불러오지 못했어요',
                        'Không tải được thông tin',
                        '无法加载信息',
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
                      child: CircularProgressIndicator(
                        color: GaonColors.textSecondary,
                      ),
                    );
                  }
                  final (user, loaded) = snap.data!;
                  final children = _childrenOverride ?? loaded;

                  return ListView(
                    // 스크롤로 키보드 닫기(QA T-4 — iOS 공통 처리)
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.all(GaonSpace.md),
                    children: [
                      Text(
                        biLine('학부모 정보', 'Thông tin phụ huynh', '家长信息'),
                        style: GaonType.label.copyWith(
                          color: GaonColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: GaonSpace.xs),
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
                        child: Column(
                          children: [
                            // 출신국·모국어를 '언어' 하나로 통합(요청) — 온보딩과 동일.
                            // 언어를 바꾸면 국가도 함께 도출된다(vi→VN, zh→CN).
                            _infoRow(
                              biLine('언어', 'Ngôn ngữ', '语言'),
                              user.nativeLanguage.label,
                              onEdit: () => _editLanguage(user),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: GaonSpace.md),

                      Text(
                        biLine('자녀 정보', 'Thông tin con', '子女信息'),
                        key: _childrenSectionKey,
                        style: GaonType.label.copyWith(
                          color: GaonColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: GaonSpace.xs),
                      for (final child in children)
                        Container(
                          margin: const EdgeInsets.only(bottom: GaonSpace.xs),
                          padding: const EdgeInsets.all(GaonSpace.md),
                          decoration: BoxDecoration(
                            color: GaonColors.surface,
                            borderRadius: BorderRadius.circular(GaonRadius.xl),
                            border: Border.all(
                              width: 2,
                              color: _childBorder(child),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      child.name ?? biLine('자녀', 'Con', '孩子'),
                                      style: GaonType.h3.copyWith(
                                        color: GaonColors.textPrimary,
                                      ),
                                    ),
                                    Text(
                                      '${child.schoolName ?? biLine('학교 미등록', 'Chưa đăng ký trường', '未登记学校')} · '
                                      '${child.grade.label.split(' / ').last} '
                                      '${child.classNo ?? '?'}반',
                                      style: GaonType.caption.copyWith(
                                        color: GaonColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              _pillButton(
                                biLine('수정', 'Sửa', '修改'),
                                GaonColors.primaryLight,
                                GaonColors.textPrimary,
                                () => _showChildSheet(
                                  children.length,
                                  edit: child,
                                ),
                              ),
                              const SizedBox(width: 6),
                              _pillButton(
                                biLine('삭제', 'Xóa', '删除'),
                                GaonColors.warningLight,
                                GaonColors.warning,
                                () => _deleteChild(child, children),
                              ),
                            ],
                          ),
                        ),

                      // 자녀 추가 — F-ON-4 (POST /children)
                      InkWell(
                        onTap: () => _showChildSheet(children.length),
                        borderRadius: BorderRadius.circular(GaonRadius.xl),
                        child: Container(
                          padding: const EdgeInsets.all(GaonSpace.md),
                          decoration: BoxDecoration(
                            border: Border.all(
                              width: 2,
                              color: GaonColors.primary,
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
                  );
                },
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
                label: bi('Lưu thay đổi', '保存'),
                subLabel: '저장하기',
                onTap: () => Navigator.of(context).maybePop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value, {required VoidCallback onEdit}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GaonType.caption.copyWith(
                    color: GaonColors.textSecondary,
                  ),
                ),
                Text(
                  value,
                  style: GaonType.body.copyWith(
                    fontWeight: FontWeight.w600,
                    color: GaonColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          _pillButton(
            biLine('변경', 'Đổi', '更改'),
            GaonColors.primaryLight,
            GaonColors.textPrimary,
            onEdit,
          ),
        ],
      ),
    );
  }

  // ── F-ON-1: 프로필(언어) 변경 — PATCH /profile ──
  // 언어=국가 통합(요청): 언어 변경 시 국가도 도출(_editLanguage). 출신국 단독
  // 변경(_editCountry)은 제거 — 복원 가능하도록 주석 처리.
  /*
  Future<void> _editCountry(User user) async {
    final selected = await _pickOption<OriginCountry>(
      title: biLine('출신국 변경', 'Đổi quốc gia', '更改国家'),
      options: OriginCountry.values,
      labelOf: (v) => v.label,
      current: user.originCountry,
    );
    if (selected == null || selected == user.originCountry) return;
    try {
      await repository.updateProfile(originCountry: selected);
      if (!mounted) return;
      _snack(biLine('출신국을 변경했어요', 'Đã đổi quốc gia', '已更改国家'));
      setState(() { _future = _load(); });
    } catch (_) {
      if (!mounted) return;
      _snack(
        biLines(
          '변경에 실패했어요 — 잠시 후 다시 시도해 주세요',
          'Thay đổi thất bại — thử lại sau',
          '更改失败——请稍后再试',
        ),
      );
    }
  }
  */

  Future<void> _editLanguage(User user) async {
    final selected = await _pickOption<NativeLanguage>(
      title: biLine('모국어 변경', 'Đổi ngôn ngữ', '更改语言'),
      options: NativeLanguage.values,
      labelOf: (v) => v.label,
      current: user.nativeLanguage,
    );
    if (selected == null || selected == user.nativeLanguage) return;
    try {
      // 언어=국가 통합(요청) — 언어를 바꾸면 국가도 함께 도출(vi→VN, zh→CN).
      await repository.updateProfile(
        nativeLanguage: selected,
        originCountry:
            selected == NativeLanguage.zh ? OriginCountry.cn : OriginCountry.vn,
      );
      await AppLangStore.save(selected); // 전 화면 표시 언어 즉시 갱신 + 로컬 저장
      if (!mounted) return;
      _snack(biLine('모국어를 변경했어요', 'Đã đổi ngôn ngữ', '已更改语言'));
      setState(() { _future = _load(); });
    } catch (_) {
      if (!mounted) return;
      _snack(
        biLines(
          '변경에 실패했어요 — 잠시 후 다시 시도해 주세요',
          'Thay đổi thất bại — thử lại sau',
          '更改失败——请稍后再试',
        ),
      );
    }
  }

  Future<T?> _pickOption<T>({
    required String title,
    required List<T> options,
    required String Function(T) labelOf,
    required T current,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      backgroundColor: GaonColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(GaonRadius.xxl),
        ),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(GaonSpace.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GaonType.h3.copyWith(color: GaonColors.textPrimary),
              ),
              const SizedBox(height: GaonSpace.md),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final option in options)
                    _sheetChip(
                      label: labelOf(option),
                      selected: option == current,
                      onTap: () => Navigator.of(sheetContext).pop(option),
                    ),
                ],
              ),
              const SizedBox(height: GaonSpace.sm),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pillButton(String label, Color bg, Color fg, VoidCallback onTap) {
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(GaonRadius.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(GaonRadius.pill),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
          child: Text(
            label,
            style: GaonType.caption.copyWith(
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }
}
