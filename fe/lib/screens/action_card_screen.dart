import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/app_lang.dart';
import '../data/app_nav.dart';
import '../data/locator.dart';
import '../data/repository.dart';
import '../models/schema.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';

/// ⑦ 행동 카드 (F-DOC-6 구매 검색어, F-DOC-7 캘린더 추가, F-DOC-8 회신 초안).
/// 번역을 행동으로 잇는 핵심 화면. 전송은 항상 사용자 수동(복사/공유).
class ActionCardScreen extends StatefulWidget {
  const ActionCardScreen({super.key});

  @override
  State<ActionCardScreen> createState() => _ActionCardScreenState();
}

class _ActionCardScreenState extends State<ActionCardScreen> {
  late Future<DocumentAnalysis> _future = repository.getLatestAnalysis();

  // 회신 초안은 사용자가 공유 전에 직접 수정할 수 있어야 한다(요청) — 편집 상태를
  // 컨트롤러로 보유하고, 복사/공유는 원문이 아니라 편집된 내용을 사용한다.
  final TextEditingController _replyController = TextEditingController();
  bool _replySeeded = false;

  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
  }

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

  /// 쿠팡 열기 — 앱 스킴 우선(웹은 봇 차단으로 Access Denied가 날 수 있음),
  /// 앱이 없으면 웹으로 폴백. 시뮬레이터엔 쿠팡 앱이 없으니 실기기에서 확인.
  Future<void> _openCoupang(String webUrl) async {
    final q = Uri.tryParse(webUrl)?.queryParameters['q'];
    if (q != null) {
      final app = Uri.parse('coupang://search?q=${Uri.encodeComponent(q)}');
      if (await canLaunchUrl(app)) {
        await launchUrl(app);
        return;
      }
    }
    final ok = await launchUrl(
      Uri.parse(webUrl),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && mounted) {
      _snack(
        biLines(
          '쿠팡을 열지 못했어요 — 실기기에서 확인해 주세요',
          'Không mở được Coupang',
          '无法打开Coupang',
        ),
      );
    }
  }

  /// F-DOC-7: 캘린더 실저장 + 리마인드 예약.
  /// [selected] 전달 시 해당 일정만 저장(QA D-3b·D-4 — 일정별 '추가' 버튼).
  /// 저장한 일정이 과거·다른 달이면 현재 월 캘린더에 안 보여 "추가 안 됨"으로
  /// 오인된다(QA D-4 조사 결과) — 성공 스낵바에 '캘린더 보기'(해당 월 포커스 이동)를 단다.
  Future<void> _saveToCalendar(
    String documentId, {
    List<CalendarEvent>? selected,
  }) async {
    // 스낵바는 화면 pop 후에도 살아남는다 — 액션이 dispose된 State의 context를
    // 조회하면 예외(적대적 리뷰 A-3). await 전에 루트 NavigatorState를 캡처해
    // 화면 수명과 무관하게 동작하도록 한다(goToCalendar는 전역 신호라 원래 무관).
    final navigator = Navigator.of(context);
    try {
      final saved = await repository.saveCalendarEvents(
        documentId: documentId,
        selected: selected,
      );
      // 로컬 리마인드 예약 제거(결정 #11 — 선제 알림 비활성)
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            biLines(
              '일정 ${saved.length}개를 캘린더에 저장했어요',
              'Đã lưu ${saved.length} lịch',
              '已保存 ${saved.length} 个日程',
            ),
          ),
          // 모국어·한국어를 두 줄로(biLines), 3초 뒤 자동으로 사라진다
          // (액션을 안 눌러도) — 명시 duration이 없으면 오래 남아 답답하다는 피드백.
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: biLine('캘린더 보기', 'Xem lịch', '查看日历'),
            textColor: GaonColors.primary,
            onPressed: () {
              // 행동 카드(푸시 화면)를 닫고 저장된 일정의 월로 캘린더 포커스
              navigator.popUntil((route) => route.isFirst);
              goToCalendar(saved.firstOrNull?.date);
            },
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _snack(
        biLines(
          '캘린더 저장에 실패했어요 — 네트워크를 확인해 주세요',
          'Lưu lịch thất bại — hãy kiểm tra mạng',
          '保存日历失败——请检查网络',
        ),
      );
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
              ko: '행동 카드',
              native: bi('Thẻ hành động', '行动卡'),
              showBack: true,
            ),
            Expanded(
              child: FutureBuilder(
                future: _future,
                builder: (context, snap) {
                  // 실패 시 무한 스피너 방지(QA A-6 셀프 리뷰) — 안내 + 재시도
                  if (snap.hasError) {
                    return GaonAsyncError(
                      message: biLines(
                        '행동 카드를 불러오지 못했어요',
                        'Không tải được thẻ hành động',
                        '无法加载行动卡',
                      ),
                      subMessage: biLines(
                        '알림장을 먼저 분석했는지 확인해 주세요',
                        'Hãy phân tích thông báo trước',
                        '请先分析通知单',
                      ),
                      onRetry: () => setState(
                        () => _future = repository.getLatestAnalysis(),
                      ),
                    );
                  }
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
                  // 회신 초안을 편집 컨트롤러에 한 번만 시딩(이후 사용자 편집 보존).
                  if (card.replyDraftKo != null && !_replySeeded) {
                    _replyController.text = card.replyDraftKo!;
                    _replySeeded = true;
                  }
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
                                    // 문서와 무관하게 '현장체험학습…'이 박혀 있던
                                    // 하드코딩 제거 — 실제 문서 제목으로 표시(QA 9)
                                    child: BiText(
                                      ko: '${analysis.extractedItem.title} 회신',
                                      native: bi('Trả lời đơn đồng ý', '回复同意书'),
                                      nativeStyle: GaonType.body,
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
                                    Row(
                                      children: [
                                        Text(
                                          biLine(
                                            '회신 초안',
                                            'Bản nháp trả lời',
                                            '回复草稿',
                                          ),
                                          style: GaonType.micro.copyWith(
                                            fontWeight: FontWeight.w600,
                                            color: GaonColors.textSecondary,
                                          ),
                                        ),
                                        const SizedBox(width: GaonSpace.xs),
                                        const Icon(
                                          Icons.edit_rounded,
                                          size: 11,
                                          color: GaonColors.textSecondary,
                                        ),
                                        const SizedBox(width: 2),
                                        Text(
                                          biLine('수정 가능', 'Có thể sửa', '可编辑'),
                                          style: GaonType.nano.copyWith(
                                            color: GaonColors.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: GaonSpace.xxs),
                                    // 공유 전에 사용자가 직접 고칠 수 있는 편집 필드.
                                    // 배경 박스에 녹아들도록 테두리 없이(카톡공유는 이 값 사용).
                                    TextField(
                                      controller: _replyController,
                                      maxLines: null,
                                      textInputAction: TextInputAction.newline,
                                      style: GaonType.caption.copyWith(
                                        color: GaonColors.textPrimary,
                                        height: 1.7,
                                      ),
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        border: InputBorder.none,
                                        contentPadding: EdgeInsets.zero,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: GaonSpace.sm),
                              Row(
                                children: [
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
                                            // 진초록 배경 위 전경은 토큰으로(A-6)
                                            color: GaonColors.onPrimary,
                                          ),
                                          const SizedBox(width: GaonSpace.xxs),
                                          Flexible(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                // 말줄임('...') 대신 한 줄 유지 + 넘치면 축소
                                                FittedBox(
                                                  fit: BoxFit.scaleDown,
                                                  child: Text(
                                                    bi(
                                                      'Thêm vào lịch',
                                                      '添加到日历',
                                                    ),
                                                    maxLines: 1,
                                                    softWrap: false,
                                                    style: GaonType.micro
                                                        .copyWith(
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color: GaonColors
                                                              .onPrimary,
                                                        ),
                                                  ),
                                                ),
                                                FittedBox(
                                                  fit: BoxFit.scaleDown,
                                                  child: Text(
                                                    '캘린더 추가',
                                                    maxLines: 1,
                                                    softWrap: false,
                                                    style: GaonType.nano
                                                        .copyWith(
                                                          color: GaonColors
                                                              .onPrimaryDim,
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
                                  const SizedBox(width: GaonSpace.xs),
                                  Expanded(
                                    child: _MiniAction(
                                      bg: GaonColors.kakao,
                                      // 공유 시트 — 전송은 사용자 수동(결정 #2)
                                      onTap: () => SharePlus.instance.share(
                                        // 원문이 아니라 사용자가 편집한 회신을 공유.
                                        ShareParams(text: _replyController.text),
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
                                          Flexible(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                FittedBox(
                                                  fit: BoxFit.scaleDown,
                                                  child: Text(
                                                    bi('Chia sẻ', '分享'),
                                                    maxLines: 1,
                                                    softWrap: false,
                                                    style: GaonType.micro
                                                        .copyWith(
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          color: GaonColors
                                                              .kakaoText,
                                                        ),
                                                  ),
                                                ),
                                                FittedBox(
                                                  fit: BoxFit.scaleDown,
                                                  child: Text(
                                                    '카톡공유',
                                                    maxLines: 1,
                                                    softWrap: false,
                                                    style: GaonType.nano
                                                        .copyWith(
                                                          color: GaonColors
                                                              .textSecondary,
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
                                // name_ko 결손(AI가 안 채운 경우) 시 고아 '준비'가
                                // 남지 않게 한국어 줄 자체를 생략(QA D-7)
                                ko: supply.nameKo.trim().isEmpty
                                    ? ''
                                    : '${supply.nameKo} 준비',
                                native:
                                    '${bi('Chuẩn bị', '准备')} ${supply.nameNative}',
                                nativeStyle: GaonType.body,
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
                                          // '규격' 라벨은 규격 값이 실제로 있을 때만
                                          // (빈 문자열 방어 포함, QA D-6). '매일 지참'
                                          // 같은 비규격 값이 오는 건 AI 출력 문제 —
                                          // FE에서 판별 불가, 보고로 이관.
                                          if (supply.spec != null &&
                                              supply.spec!.trim().isNotEmpty)
                                            Text.rich(
                                              TextSpan(
                                                children: [
                                                  TextSpan(
                                                    text:
                                                        '${biLine('규격', 'Quy cách', '规格')} ',
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
                                  biLine('구매 검색어', 'Từ khóa mua sắm', '购物关键词'),
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
                                    biLine("'$keyword' 복사했어요", 'Đã sao chép', '已复制'),
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
                                  onTap: () =>
                                      _openCoupang(supply.ecommerceDeeplink!),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        '🛒 ${bi('Tìm trên Coupang', '在Coupang搜索')}',
                                        style: GaonType.caption.copyWith(
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(width: GaonSpace.xs),
                                      Text(
                                        '쿠팡에서 검색',
                                        style: GaonType.nano.copyWith(
                                          color: GaonColors.onPrimaryDim,
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

                      // '알림장에서 추출된 일정' 독립 섹션 제거(요청) — 위 행동 카드의
                      // '캘린더 추가' 버튼이 문서의 모든 일정을 저장하므로 캘린더 추가
                      // 버튼·정보가 중복이었다. 행동 카드 페이지는 행동 카드만 보인다.
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
