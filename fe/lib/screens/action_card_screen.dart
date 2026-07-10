import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/app_lang.dart';
import '../data/locator.dart';
import '../data/notification_service.dart';
import '../data/repository.dart';
import '../models/schema.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';

/// ⑦ 행동 카드 (F-DOC-6 구매 검색어, F-DOC-7 캘린더 추가, F-DOC-8 회신 초안).
/// Translation → Action의 핵심 화면. 전송은 항상 사용자 수동(복사/공유).
class ActionCardScreen extends StatefulWidget {
  const ActionCardScreen({super.key});

  @override
  State<ActionCardScreen> createState() => _ActionCardScreenState();
}

class _ActionCardScreenState extends State<ActionCardScreen> {
  late final Future<DocumentAnalysis> _future = repository.getLatestAnalysis();

  void _snack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _copy(String text, String toast) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    _snack(toast);
  }

  String _dday(DateTime date) {
    final diff = date.difference(repository.now()).inDays;
    return diff >= 0 ? 'D-$diff' : 'D+${-diff}';
  }

  /// F-DOC-7: 캘린더 실저장 + 리마인드 예약.
  Future<void> _saveToCalendar(String documentId) async {
    try {
      final saved = await repository.saveCalendarEvents(documentId: documentId);
      await NotificationService.instance.scheduleEventReminders(saved);
      if (!mounted) return;
      _snack('일정 ${saved.length}개를 캘린더에 저장했어요 · ${bi('Đã lưu', '已保存')}');
    } catch (e) {
      if (!mounted) return;
      _snack('캘린더 저장에 실패했어요 — 네트워크를 확인해 주세요');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GaonColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            GaonHeader(
              vi: bi('Thẻ hành động', '行动卡'),
              ko: '행동 카드',
              showBack: true,
            ),
            Expanded(
              child: FutureBuilder(
                future: _future,
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: GaonColors.textSecondary,
                      ),
                    );
                  }
                  final analysis = snap.data!;
                  final card = analysis.actionCard;
                  final deadline = analysis.extractedItem.deadline;
                  final eventDates = card.calendarEvents
                      .where((e) => e.type == CalendarEventType.event)
                      .toList();
                  var actionNo = 0;

                  return ListView(
                    padding: const EdgeInsets.fromLTRB(
                      GaonSpace.md,
                      0,
                      GaonSpace.md,
                      GaonSpace.lg,
                    ),
                    children: [
                      // ── 회신 초안 (F-DOC-8) — requiresReply일 때만 ──
                      if (card.replyDraftKo != null) ...[
                        _sectionLabel(
                          '${bi('HÀNH ĐỘNG', '行动')} ${++actionNo} · 할 일 $actionNo'
                          '${deadline != null ? ' — ${_dday(deadline)}' : ''}',
                          GaonColors.warning,
                        ),
                        const SizedBox(height: GaonSpace.xs),
                        SurfaceCard(
                          border: Border.all(
                            width: 1.5,
                            color: const Color(0xFFFCDDD6),
                          ),
                          margin: const EdgeInsets.only(bottom: GaonSpace.sm),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  if (deadline != null)
                                    GaonBadge(
                                      label: _dday(deadline),
                                      color: GaonColors.warning,
                                      bg: GaonColors.warningLight,
                                    ),
                                  const SizedBox(width: GaonSpace.xs),
                                  Expanded(
                                    child: BiText(
                                      vi: bi(
                                        'Trả lời đơn đồng ý dã ngoại',
                                        '回复校外活动同意书',
                                      ),
                                      ko: '현장체험학습 동의서 회신',
                                      viStyle: GaonType.body,
                                      koStyle: GaonType.micro,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: GaonSpace.sm),
                              // 회신 초안
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  vertical: GaonSpace.sm,
                                  horizontal: GaonSpace.md,
                                ),
                                decoration: BoxDecoration(
                                  color: GaonColors.primaryLight,
                                  borderRadius: BorderRadius.circular(
                                    GaonRadius.md,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${bi('Bản nháp trả lời', '回复草稿')} · 회신 초안',
                                      style: GaonType.micro.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: GaonColors.textSecondary,
                                      ),
                                    ),
                                    const SizedBox(height: GaonSpace.xxs),
                                    Text(
                                      card.replyDraftKo!,
                                      style: GaonType.caption.copyWith(
                                        color: GaonColors.textPrimary,
                                        height: 1.7,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: GaonSpace.sm),
                              Row(
                                children: [
                                  if (deadline != null)
                                    Expanded(
                                      child: _MiniAction(
                                        bg: GaonColors.warningLight,
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            const Icon(
                                              Icons.notifications_rounded,
                                              size: 12,
                                              color: GaonColors.warning,
                                            ),
                                            const SizedBox(
                                              width: GaonSpace.xxs,
                                            ),
                                            Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  '마감 ${deadline.month}/${deadline.day}',
                                                  style: GaonType.micro
                                                      .copyWith(
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color:
                                                            GaonColors.warning,
                                                      ),
                                                ),
                                                Text(
                                                  bi('Hạn nộp', '截止日期'),
                                                  style: TextStyle(
                                                    fontSize: 9,
                                                    color: GaonColors
                                                        .textSecondary,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  const SizedBox(width: GaonSpace.xs),
                                  Expanded(
                                    child: _MiniAction(
                                      bg: GaonColors.textPrimary,
                                      onTap: () => _saveToCalendar(
                                        analysis.document.documentId,
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          const Icon(
                                            Icons.calendar_month_rounded,
                                            size: 12,
                                            color: Colors.white,
                                          ),
                                          const SizedBox(width: GaonSpace.xxs),
                                          Text(
                                            '캘린더 추가',
                                            style: GaonType.micro.copyWith(
                                              fontWeight: FontWeight.w600,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: GaonSpace.xs),
                                  Expanded(
                                    child: _MiniAction(
                                      bg: GaonColors.kakao,
                                      // 공유 시트 — 전송은 사용자 수동(결정 #2)
                                      onTap: () => SharePlus.instance.share(
                                        ShareParams(text: card.replyDraftKo!),
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          const Icon(
                                            Icons.share_rounded,
                                            size: 11,
                                            color: GaonColors.kakaoText,
                                          ),
                                          const SizedBox(width: GaonSpace.xxs),
                                          Text(
                                            '카톡공유',
                                            style: GaonType.micro.copyWith(
                                              fontWeight: FontWeight.w700,
                                              color: GaonColors.kakaoText,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],

                      // ── 준비물 (F-DOC-6) — Supply마다 카드 ──
                      for (final supply in card.supplies) ...[
                        _sectionLabel(
                          '${bi('HÀNH ĐỘNG', '行动')} ${++actionNo} · 할 일 $actionNo',
                          GaonColors.textSecondary,
                        ),
                        const SizedBox(height: GaonSpace.xs),
                        SurfaceCard(
                          border: Border.all(
                            width: 1.5,
                            color: const Color(0xFFD4EDB8),
                          ),
                          margin: const EdgeInsets.only(bottom: GaonSpace.sm),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              BiText(
                                vi: '${bi('Chuẩn bị', '准备')} ${supply.nameNative}',
                                ko: '${supply.nameKo} 준비',
                                viStyle: GaonType.body,
                                koStyle: GaonType.micro,
                              ),
                              const SizedBox(height: GaonSpace.sm),
                              // 규격 + 모국어 설명
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  vertical: GaonSpace.xs,
                                  horizontal: GaonSpace.sm,
                                ),
                                decoration: BoxDecoration(
                                  color: GaonColors.successLight,
                                  borderRadius: BorderRadius.circular(
                                    GaonRadius.md,
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Padding(
                                      padding: EdgeInsets.only(top: 2),
                                      child: Icon(
                                        Icons.check_circle_rounded,
                                        size: 12,
                                        color: GaonColors.textSecondary,
                                      ),
                                    ),
                                    const SizedBox(width: GaonSpace.xs),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          if (supply.spec != null)
                                            Text.rich(
                                              TextSpan(
                                                children: [
                                                  TextSpan(
                                                    text: '규격 ',
                                                    style: GaonType.caption
                                                        .copyWith(
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                  ),
                                                  TextSpan(text: supply.spec),
                                                ],
                                              ),
                                              style: GaonType.caption.copyWith(
                                                color: GaonColors.textPrimary,
                                              ),
                                            ),
                                          Text(
                                            supply.explanationNative,
                                            style: GaonType.micro.copyWith(
                                              color: GaonColors.textSecondary,
                                              height: 1.5,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // 구매 검색어 — 비구매 항목(keyword=null)은 숨김(§17.11).
                              // 준비물 이름·설명은 위에서 그대로 노출.
                              if (supply.ecommerceKeyword
                                  case final keyword?) ...[
                                const SizedBox(height: GaonSpace.sm),
                                Text(
                                  '${bi('Từ khóa mua sắm', '购物关键词')} · 구매 검색어',
                                  style: GaonType.micro.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: GaonColors.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: GaonSpace.xxs),
                                _MiniAction(
                                  bg: GaonColors.primaryLight,
                                  onTap: () => _copy(
                                    keyword,
                                    "'$keyword' 복사했어요 · ${bi('Đã sao chép', '已复制')}",
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        keyword,
                                        style: GaonType.caption.copyWith(
                                          fontWeight: FontWeight.w600,
                                          color: GaonColors.textSecondary,
                                        ),
                                      ),
                                      const Icon(
                                        Icons.copy_rounded,
                                        size: 11,
                                        color: GaonColors.textSecondary,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              if (supply.ecommerceDeeplink != null) ...[
                                const SizedBox(height: GaonSpace.xs),
                                // 쿠팡 검색 링크(자동결제 아님 — 검색 페이지로만)
                                _MiniAction(
                                  bg: const Color(0xFFFF3B2F),
                                  onTap: () => launchUrl(
                                    Uri.parse(supply.ecommerceDeeplink!),
                                    mode: LaunchMode.externalApplication,
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        '🛒 쿠팡에서 검색',
                                        style: GaonType.caption.copyWith(
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(width: GaonSpace.xs),
                                      Text(
                                        bi('Tìm trên Coupang', '在Coupang搜索'),
                                        style: TextStyle(
                                          fontSize: 9,
                                          color: Color(0xBFFFFFFF),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              // 행사 캘린더 추가 (F-DOC-7)
                              for (final e in eventDates) ...[
                                const SizedBox(height: GaonSpace.xs),
                                _MiniAction(
                                  bg: GaonColors.textPrimary,
                                  onTap: () => _saveToCalendar(
                                    analysis.document.documentId,
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(
                                        Icons.calendar_month_rounded,
                                        size: 11,
                                        color: Colors.white,
                                      ),
                                      const SizedBox(width: GaonSpace.xxs),
                                      Text(
                                        '${e.date.month}/${e.date.day} 행사 캘린더 추가',
                                        style: GaonType.micro.copyWith(
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text, Color color) {
    return Text(
      text,
      style: GaonType.micro.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 0.6,
        color: color,
      ),
    );
  }
}

/// 카드 내부의 작은 액션 버튼(틴트 배경 + 라운드 md).
class _MiniAction extends StatelessWidget {
  const _MiniAction({required this.bg, required this.child, this.onTap});

  final Color bg;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(GaonRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(GaonRadius.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: GaonSpace.xs,
            horizontal: GaonSpace.sm,
          ),
          child: child,
        ),
      ),
    );
  }
}
