import 'package:flutter/material.dart';

import '../data/api_repository.dart';
import '../data/app_lang.dart';
import '../data/locator.dart';
import '../data/repository.dart';
import '../models/display.dart';
import '../models/schema.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';

/// S14 개인정보 수정 — 학부모 정보 + 자녀 카드 관리.
/// 저장은 BE 연동 후 동작(현재 데모).
class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  late Future<(User, List<Child>)> _future = _load();

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
    } catch (_) {} // 실패 시 낙관적 상태 유지 — 다음 진입 때 재조회
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// F-ON-4: 자녀 추가 폼 — 온보딩과 동일 항목(이름·학교·학년·반).
  /// (기가입 계정은 온보딩을 스킵하므로 여기가 자녀 추가 진입점)
  Future<void> _showAddChildSheet(int existingCount) async {
    final nameCtrl = TextEditingController();
    final schoolCtrl = TextEditingController();
    var grade = ChildGrade.elem1;
    var classNo = '1';

    final submitted = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: GaonColors.surface,
      isScrollControlled: true, // 키보드 대응
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(GaonRadius.xxl)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
          padding: EdgeInsets.only(
              left: GaonSpace.lg,
              right: GaonSpace.lg,
              top: GaonSpace.lg,
              bottom: MediaQuery.of(sheetContext).viewInsets.bottom +
                  GaonSpace.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('자녀 추가 · ${bi('Thêm con', '添加子女')}',
                  style: GaonType.h3.copyWith(color: GaonColors.textPrimary)),
              const SizedBox(height: GaonSpace.md),
              _sheetField('이름 · ${bi('Tên con', '孩子姓名')}', nameCtrl, '자녀 이름'),
              const SizedBox(height: GaonSpace.sm),
              _sheetField('학교명 · ${bi('Tên trường', '学校名称')}', schoolCtrl, '예) 가온초등학교'),
              const SizedBox(height: GaonSpace.sm),
              Text('학년 · ${bi('Lớp', '年级')}',
                  style: GaonType.micro.copyWith(
                      fontWeight: FontWeight.w600,
                      color: GaonColors.textSecondary)),
              const SizedBox(height: GaonSpace.xxs),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final g in ChildGrade.values)
                    _sheetChip(
                        label: '초${g.wire.split('_').last}',
                        selected: grade == g,
                        onTap: () => setSheetState(() => grade = g)),
                ],
              ),
              const SizedBox(height: GaonSpace.sm),
              Text('반 · ${bi('Ban', '班')}',
                  style: GaonType.micro.copyWith(
                      fontWeight: FontWeight.w600,
                      color: GaonColors.textSecondary)),
              const SizedBox(height: GaonSpace.xxs),
              Wrap(
                spacing: 6,
                children: [
                  for (var n = 1; n <= 5; n++)
                    _sheetChip(
                        label: '$n반',
                        selected: classNo == '$n',
                        onTap: () =>
                            setSheetState(() => classNo = '$n')),
                ],
              ),
              const SizedBox(height: GaonSpace.lg),
              GaonButton(
                label: '등록하기 · ${bi('Đăng ký', '注册')}',
                onTap: () => Navigator.of(sheetContext).pop(true),
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
    });
    if (submitted != true) return;

    final name = nameCtrl.text.trim();
    final school = schoolCtrl.text.trim();
    try {
      await repository.addChild(
        grade: grade,
        name: name.isEmpty ? null : name,
        classNo: classNo,
        schoolName: school.isEmpty ? null : school,
        // 색은 팔레트 순환 배정(§17.4) — 기존 자녀 수 기준
        color: childColorPalette[existingCount % childColorPalette.length],
      );
      if (!mounted) return;
      _snack('${name.isEmpty ? '자녀' : name} 등록 완료!');
    } catch (e) {
      if (!mounted) return;
      _snack('등록에 실패했어요 — 잠시 후 다시 시도해 주세요');
    } finally {
      // 스피너 없이 자녀 목록만 갱신(추가된 자녀 즉시 표시)
      if (mounted) await _resyncChildren();
    }
  }

  Widget _sheetField(
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

  Widget _sheetChip(
      {required String label,
      required bool selected,
      required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 14),
        decoration: BoxDecoration(
          color: selected ? GaonColors.textPrimary : GaonColors.primaryLight,
          borderRadius: BorderRadius.circular(GaonRadius.pill),
        ),
        child: Text(label,
            style: GaonType.label.copyWith(
                color:
                    selected ? GaonColors.onPrimary : GaonColors.textPrimary)),
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
            borderRadius: BorderRadius.circular(GaonRadius.xl)),
        title: Text('${child.name ?? '자녀'} 삭제',
            style: GaonType.h3.copyWith(color: GaonColors.textPrimary)),
        content: Text('이 자녀 정보를 삭제할까요?\n${bi('Xóa thông tin con này?', '要删除这个孩子的信息吗？')}',
            style: GaonType.body.copyWith(color: GaonColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('취소',
                style:
                    GaonType.body.copyWith(color: GaonColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('삭제',
                style: GaonType.body.copyWith(
                    fontWeight: FontWeight.w700, color: GaonColors.warning)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    // 서버 응답을 기다리지 않고 카드부터 제거 — 실패하면 재동기화가 되살린다
    setState(() => _childrenOverride =
        [for (final c in current) if (c.childId != child.childId) c]);
    _snack('${child.name ?? '자녀'} 정보를 삭제했어요');
    try {
      await repository.deleteChild(child.childId);
    } on ApiException catch (e) {
      if (!mounted) return;
      // 404 = 이미 삭제됨(중복 탭 등) — 화면 상태 그대로 두면 됨
      if (e.statusCode != 404) {
        _snack('삭제에 실패했어요 (오류 ${e.statusCode})');
        await _resyncChildren();
      }
    } catch (e) {
      if (!mounted) return;
      _snack('삭제에 실패했어요 — 잠시 후 다시 시도해 주세요');
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
                border:
                    Border(bottom: BorderSide(color: GaonColors.border)),
              ),
              padding: const EdgeInsets.symmetric(
                  vertical: GaonSpace.sm, horizontal: GaonSpace.md),
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
                        child: Icon(Icons.arrow_back_rounded,
                            size: 16, color: GaonColors.textPrimary),
                      ),
                    ),
                  ),
                  const SizedBox(width: GaonSpace.xs),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('개인정보 수정',
                          style: GaonType.h3
                              .copyWith(color: GaonColors.textPrimary)),
                      Text(bi('Chỉnh sửa hồ sơ', '修改个人信息'),
                          style: GaonType.micro
                              .copyWith(color: GaonColors.textSecondary)),
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
                      message: '정보를 불러오지 못했어요',
                      subMessage: '네트워크 확인 후 다시 시도해 주세요',
                      onRetry: () => setState(() => _future = _load()),
                    );
                  }
                  if (!snap.hasData) {
                    return const Center(
                        child: CircularProgressIndicator(
                            color: GaonColors.textSecondary));
                  }
                  final (user, loaded) = snap.data!;
                  final children = _childrenOverride ?? loaded;

                  return ListView(
                    padding: const EdgeInsets.all(GaonSpace.md),
                    children: [
                      Text('학부모 정보',
                          style: GaonType.label
                              .copyWith(color: GaonColors.textSecondary)),
                      const SizedBox(height: GaonSpace.xs),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: GaonSpace.xs,
                            horizontal: GaonSpace.md),
                        decoration: BoxDecoration(
                          color: GaonColors.surface,
                          borderRadius:
                              BorderRadius.circular(GaonRadius.xl),
                          boxShadow: GaonShadow.card,
                        ),
                        child: Column(
                          children: [
                            _infoRow('출신국 · ${bi('Quốc gia', '国家')}',
                                user.originCountry.label),
                            const GaonDivider(),
                            _infoRow('모국어 · ${bi('Ngôn ngữ', '语言')}',
                                user.nativeLanguage.label),
                          ],
                        ),
                      ),
                      const SizedBox(height: GaonSpace.md),

                      Text('자녀 정보 · Thông tin con',
                          style: GaonType.label
                              .copyWith(color: GaonColors.textSecondary)),
                      const SizedBox(height: GaonSpace.xs),
                      for (final child in children)
                        Container(
                          margin:
                              const EdgeInsets.only(bottom: GaonSpace.xs),
                          padding: const EdgeInsets.all(GaonSpace.md),
                          decoration: BoxDecoration(
                            color: GaonColors.surface,
                            borderRadius:
                                BorderRadius.circular(GaonRadius.xl),
                            border: Border.all(
                                width: 2, color: _childBorder(child)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(child.name ?? '자녀',
                                        style: GaonType.h3.copyWith(
                                            color:
                                                GaonColors.textPrimary)),
                                    Text(
                                        '${child.schoolName ?? '학교 미등록'} · '
                                        '${child.grade.label.split(' / ').last} '
                                        '${child.classNo ?? '?'}반',
                                        style: GaonType.caption.copyWith(
                                            color: GaonColors
                                                .textSecondary)),
                                  ],
                                ),
                              ),
                              _pillButton('수정', GaonColors.primaryLight,
                                  GaonColors.textPrimary,
                                  () => _snack('자녀 수정은 곧 제공돼요')),
                              const SizedBox(width: 6),
                              _pillButton('삭제', GaonColors.warningLight,
                                  GaonColors.warning,
                                  () => _deleteChild(child, children)),
                            ],
                          ),
                        ),

                      // 자녀 추가 — F-ON-4 (POST /children)
                      InkWell(
                        onTap: () => _showAddChildSheet(children.length),
                        borderRadius:
                            BorderRadius.circular(GaonRadius.xl),
                        child: Container(
                          padding: const EdgeInsets.all(GaonSpace.md),
                          decoration: BoxDecoration(
                            border: Border.all(
                                width: 2, color: GaonColors.primary),
                            borderRadius:
                                BorderRadius.circular(GaonRadius.xl),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.add_rounded,
                                  size: 16,
                                  color: GaonColors.textSecondary),
                              const SizedBox(width: GaonSpace.xs),
                              Text('자녀 추가 · ${bi('Thêm con', '添加子女')}',
                                  style: GaonType.body.copyWith(
                                      color: GaonColors.textSecondary)),
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
                  GaonSpace.md, GaonSpace.xs, GaonSpace.md, GaonSpace.lg),
              child: GaonButton(
                label: '저장하기 · ${bi('Lưu thay đổi', '保存')}',
                onTap: () => Navigator.of(context).maybePop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: GaonType.caption
                        .copyWith(color: GaonColors.textSecondary)),
                Text(value,
                    style: GaonType.body.copyWith(
                        fontWeight: FontWeight.w600,
                        color: GaonColors.textPrimary)),
              ],
            ),
          ),
          _pillButton('변경', GaonColors.primaryLight,
              GaonColors.textPrimary, () {
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('프로필 변경은 곧 제공돼요')));
          }),
        ],
      ),
    );
  }

  Widget _pillButton(
      String label, Color bg, Color fg, VoidCallback onTap) {
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(GaonRadius.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(GaonRadius.pill),
        child: Padding(
          padding:
              const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
          child: Text(label,
              style: GaonType.caption
                  .copyWith(fontWeight: FontWeight.w600, color: fg)),
        ),
      ),
    );
  }
}
