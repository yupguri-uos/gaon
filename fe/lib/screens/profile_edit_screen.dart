import 'package:flutter/material.dart';

import '../data/demo_data.dart';
import '../data/locator.dart';
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
  late final Future<(User, List<Child>)> _future = () async {
    final user = repository.getCurrentUser();
    final children = repository.getChildren();
    return (await user, await children);
  }();

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
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
                      Text('Chỉnh sửa hồ sơ',
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
                  if (!snap.hasData) {
                    return const Center(
                        child: CircularProgressIndicator(
                            color: GaonColors.textSecondary));
                  }
                  final (user, children) = snap.data!;

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
                            _infoRow('출신국 · Quốc gia',
                                user.originCountry.label),
                            const GaonDivider(),
                            _infoRow('모국어 · Ngôn ngữ',
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
                                width: 2, color: GaonColors.textPrimary),
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
                                        '$demoSchoolName · '
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
                                  () => _snack('자녀 수정은 BE 연동 후 (데모)')),
                              const SizedBox(width: 6),
                              _pillButton('삭제', GaonColors.warningLight,
                                  GaonColors.warning,
                                  () => _snack('자녀 삭제는 BE 연동 후 (데모)')),
                            ],
                          ),
                        ),

                      // 자녀 추가
                      InkWell(
                        onTap: () => _snack('자녀 추가는 BE 연동 후 (데모)'),
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
                              Text('자녀 추가 · Thêm con',
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
                label: '저장하기 · Lưu thay đổi',
                onTap: () {
                  _snack('저장되었습니다 (데모)');
                  Navigator.of(context).maybePop();
                },
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
                const SnackBar(content: Text('변경은 BE 연동 후 (데모)')));
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
