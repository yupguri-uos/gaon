import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/app_nav.dart';
import '../data/app_lang.dart';
import '../data/locator.dart';
import '../data/repository.dart';
import '../models/schema.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';

/// S9 캘린더 월 뷰 + S10 날짜 상세 바텀시트.
/// 다자녀: Child.color로 이벤트 점 색을 구분(마감은 항상 warn).
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  static const _days = ['일', '월', '화', '수', '목', '금', '토'];
  // 요일 헤더 병기 — 모국어(주). 베트남어는 CN(주일)·T2~T7 관례.
  static const _daysVi = ['CN', 'T2', 'T3', 'T4', 'T5', 'T6', 'T7'];
  static const _daysZh = ['日', '一', '二', '三', '四', '五', '六'];
  static const _weekdaysKo = ['월', '화', '수', '목', '금', '토', '일'];
  static const _weekdaysVi = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
  static const _weekdaysZh = ['一', '二', '三', '四', '五', '六', '日'];

  late Future<(List<Child>, List<CalendarEventView>, DocumentAnalysis?)>
  _future = _load();

  Future<(List<Child>, List<CalendarEventView>, DocumentAnalysis?)>
  _load() async {
    // 일정 그리드 = 저장된 전체 캘린더(GET /calendar/events, F-CAL-1) —
    // '최신 분석 1건'이 아니라 여러 문서의 일정이 누적 표시된다.
    // 뷰 모델(CalendarEventView)로 받아 출처 문서 제목까지 표시(QA D-5).
    final children = repository.getChildren();
    final events = repository.getCalendarEventViews();
    // 상세 시트의 원문/번역·검색어는 최신 분석에서 — 분석 전이면 null(시트 축약 표시).
    // (§7 CalendarEvent에 document_id가 없어 일정별 원문 역추적은 SSOT 결정 대기)
    DocumentAnalysis? analysis;
    try {
      analysis = await repository.getLatestAnalysis();
    } catch (_) {}
    return (await children, await events, analysis);
  }

  /// 표시 중인 월(1일 고정) — ◀▶로 자유 이동.
  /// 초기값: 마지막으로 보던 월(전역 보존, QA C-4) → 없으면 오늘 기준 월.
  late DateTime _visibleMonth =
      calendarLastMonth ?? DateTime(_today.year, _today.month);
  int? _selectedDay;

  DateTime get _today => repository.now();

  @override
  void initState() {
    super.initState();
    calendarFocus.addListener(_onFocus);
    _onFocus(); // 진입 시점에 이미 포커스가 있으면 적용
    mainTabIndex.addListener(_onTabChanged);
  }

  @override
  void dispose() {
    calendarFocus.removeListener(_onFocus);
    mainTabIndex.removeListener(_onTabChanged);
    super.dispose();
  }

  /// 캘린더 탭 진입 시 재조회 — IndexedStack이라 탭 전환만으로는 rebuild가 없어
  /// 다른 화면에서 저장한 일정('나중에' 선택·행동 카드 추가)이 반영되지 않았다(QA).
  void _onTabChanged() {
    if (mainTabIndex.value != 1 || !mounted) return;
    setState(() { _future = _load(); });
  }

  /// 저장 직후 "확인" 등으로 특정 일정에 포커스 — 해당 월로 이동 + 목록 갱신.
  void _onFocus() {
    final date = calendarFocus.value;
    if (date == null) return;
    calendarFocus.value = null; // 소비
    setState(() {
      _visibleMonth = DateTime(date.year, date.month);
      calendarLastMonth = _visibleMonth; // 마지막 월 보존(QA C-4)
      _selectedDay = date.day;
      _future = _load(); // 방금 저장된 일정 반영
    });
  }

  void _shiftMonth(int delta) {
    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + delta);
      calendarLastMonth = _visibleMonth; // 마지막 월 보존(QA C-4)
      _selectedDay = null;
    });
  }

  String _dday(DateTime date) {
    final diff = date.difference(_today).inDays;
    return diff >= 0 ? 'D-$diff' : 'D+${-diff}';
  }

  Color _childColor(List<Child> children, String? childId) {
    final hex = children.where((c) => c.childId == childId).firstOrNull?.color;
    if (hex == null) return GaonColors.textPrimary;
    return Color(int.parse('FF${hex.replaceFirst('#', '')}', radix: 16));
  }

  Color _dotColor(List<Child> children, CalendarEvent e) =>
      e.type == CalendarEventType.deadline
      ? GaonColors.warning
      : _childColor(children, e.childId);

  Future<void> _copyKeyword(String keyword) async {
    await Clipboard.setData(ClipboardData(text: keyword));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(biLine("'$keyword' 복사했어요", 'Đã sao chép', '已复制')),
      ),
    );
  }

  // ── S10: 날짜 상세 바텀시트 ──
  // [analysis]는 최신 분석(원문/번역·검색어 표시용) — 없으면 해당 섹션을 생략한다.
  void _showDetail(DocumentAnalysis? analysis, CalendarEventView view) {
    final event = view.event;
    var showTranslated = true;
    final urgent = event.type == CalendarEventType.deadline;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: GaonColors.surface,
      barrierColor: GaonColors.barrier,
      isScrollControlled: true,
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

                // 날짜 헤더 + 원본/번역 토글
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            bi(
                              '${event.date.day}/${event.date.month} '
                                  '(${_weekdaysVi[event.date.weekday - 1]})',
                              '${event.date.month}月${event.date.day}日 '
                                  '(周${_weekdaysZh[event.date.weekday - 1]})',
                            ),
                            style: GaonType.h2.copyWith(
                              color: urgent
                                  ? GaonColors.warning
                                  : GaonColors.textPrimary,
                            ),
                          ),
                          Text(
                            '${event.date.month}월 ${event.date.day}일 '
                            '${_weekdaysKo[event.date.weekday - 1]}요일 · '
                            '${event.title} · ${_dday(event.date)}',
                            style: GaonType.caption.copyWith(
                              color: GaonColors.textSecondary,
                            ),
                          ),
                          // 출처 문서 — 어느 알림장에서 나온 일정인지(QA D-5).
                          // source_title 없으면 줄 생략.
                          if (view.sourceTitle != null)
                            Text(
                              '${bi('Nguồn', '来源')} · 출처: ${view.sourceTitle}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GaonType.micro.copyWith(
                                color: GaonColors.textSecondary,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (analysis != null)
                      Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: GaonColors.primaryLight,
                          borderRadius: BorderRadius.circular(GaonRadius.pill),
                        ),
                        child: Row(
                          children: [
                            for (final (i, t) in [
                              biLine('원본', 'Gốc', '原文'),
                              biLine('번역', 'Dịch', '译文'),
                            ].indexed)
                              GestureDetector(
                                onTap: () => setSheetState(
                                  () => showTranslated = i == 1,
                                ),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 4,
                                    horizontal: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: (i == 1) == showTranslated
                                        ? GaonColors.textPrimary
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(
                                      GaonRadius.pill,
                                    ),
                                  ),
                                  child: Text(
                                    t,
                                    style: GaonType.caption.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: (i == 1) == showTranslated
                                          ? GaonColors.onPrimary
                                          : GaonColors.textSecondary,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: GaonSpace.md),

                // 내용 — 번역(요약) ↔ 원본(rawText). 분석이 없으면 생략.
                if (analysis != null) ...[
                  Container(
                    padding: const EdgeInsets.all(GaonSpace.sm),
                    decoration: BoxDecoration(
                      color: GaonColors.bg,
                      borderRadius: BorderRadius.circular(GaonRadius.lg),
                    ),
                    child: Text(
                      showTranslated
                          ? analysis.translated.summaryNative
                          : analysis.extractedItem.rawText,
                      style: GaonType.body.copyWith(
                        color: GaonColors.textPrimary,
                        height: 1.7,
                      ),
                    ),
                  ),
                  const SizedBox(height: GaonSpace.sm),
                ],

                // 검색어 추천 (F-DOC-6) — 키워드 있는 supply만(§17.11: 비구매 항목은 null)
                if (analysis != null &&
                    analysis.actionCard.supplies.any(
                      (s) => s.ecommerceKeyword != null,
                    ))
                  Container(
                    padding: const EdgeInsets.all(GaonSpace.sm),
                    decoration: BoxDecoration(
                      color: GaonColors.primaryLight,
                      borderRadius: BorderRadius.circular(GaonRadius.lg),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '🛒 ${biLine('검색어 추천', 'Từ khóa mua sắm', '购物关键词')}',
                          style: GaonType.caption.copyWith(
                            fontWeight: FontWeight.w600,
                            color: GaonColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          children: [
                            for (final s in analysis.actionCard.supplies)
                              if (s.ecommerceKeyword case final keyword?)
                                Material(
                                  color: GaonColors.textPrimary,
                                  borderRadius: BorderRadius.circular(
                                    GaonRadius.pill,
                                  ),
                                  child: InkWell(
                                    onTap: () => _copyKeyword(keyword),
                                    borderRadius: BorderRadius.circular(
                                      GaonRadius.pill,
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 5,
                                        horizontal: 12,
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            keyword,
                                            style: GaonType.caption.copyWith(
                                              fontWeight: FontWeight.w600,
                                              color: GaonColors.onPrimary,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          const Icon(
                                            Icons.copy_rounded,
                                            size: 10,
                                            color: GaonColors.primary,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                          ],
                        ),
                      ],
                    ),
                  ),
                // '리마인드 알림 예약' 버튼 제거(결정 #11) — 선제 알림 기능 전면
                // 비활성. 마감 D-2 '표시'(달력 배지)는 Chain A 산출이라 유지.
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FutureBuilder(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return GaonAsyncError(
              message: biLines(
                '캘린더를 불러오지 못했어요',
                'Không tải được lịch',
                '无法加载日历',
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
              child: CircularProgressIndicator(color: GaonColors.textSecondary),
            );
          }
          final (children, events, analysis) = snap.data!;
          if (events.isEmpty) {
            // 저장된 일정 없음 — 분석 → '캘린더 추가'(F-DOC-7) 유도
            return GaonAsyncError(
              message: biLines('저장된 일정이 없어요', 'Chưa có lịch nào', '还没有保存的日程'),
              subMessage: biLines(
                '알림장을 분석하고 캘린더에 추가해 보세요',
                'Hãy phân tích thông báo và thêm vào lịch',
                '请分析通知单并添加到日历',
              ),
              onRetry: () => setState(() { _future = _load(); }),
            );
          }
          final eventsByDay = <int, List<CalendarEventView>>{};
          for (final v in events) {
            if (v.event.date.year == _visibleMonth.year &&
                v.event.date.month == _visibleMonth.month) {
              eventsByDay.putIfAbsent(v.event.date.day, () => []).add(v);
            }
          }
          // 선택일이 없으면 이 월의 첫 일정 날로 자동 선택
          final selectedDay =
              _selectedDay ??
              (eventsByDay.keys.isEmpty
                  ? null
                  : eventsByDay.keys.reduce((a, b) => a < b ? a : b));
          final selectedEvents = selectedDay == null
              ? const <CalendarEventView>[]
              : (eventsByDay[selectedDay] ?? const <CalendarEventView>[]);

          return Column(
            children: [
              // 월 헤더 + 자녀 범례
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
                    IconButton(
                      onPressed: () => _shiftMonth(-1),
                      icon: const Icon(
                        Icons.chevron_left_rounded,
                        color: GaonColors.textPrimary,
                      ),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            bi(
                              'Tháng ${_visibleMonth.month}, ${_visibleMonth.year}',
                              '${_visibleMonth.year}年${_visibleMonth.month}月',
                            ),
                            textAlign: TextAlign.center,
                            style: GaonType.h2.copyWith(
                              color: GaonColors.textPrimary,
                            ),
                          ),
                          Text(
                            '${_visibleMonth.year}년 ${_visibleMonth.month}월',
                            textAlign: TextAlign.center,
                            style: GaonType.micro.copyWith(
                              color: GaonColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => _shiftMonth(1),
                      icon: const Icon(
                        Icons.chevron_right_rounded,
                        color: GaonColors.textPrimary,
                      ),
                    ),
                    for (final c in children)
                      Padding(
                        padding: const EdgeInsets.only(left: GaonSpace.xs),
                        child: Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _childColor(children, c.childId),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              (c.name ?? '자녀').length > 1
                                  ? (c.name ?? '자녀').substring(1)
                                  : c.name ?? '자녀',
                              style: GaonType.micro.copyWith(
                                color: GaonColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),

              // 요일 헤더 — 첫 주와의 과다 여백 축소(QA C-3)
              Container(
                color: GaonColors.surface,
                padding: const EdgeInsets.symmetric(
                  vertical: GaonSpace.xxs,
                  horizontal: GaonSpace.sm,
                ),
                child: Row(
                  children: [
                    for (final (i, d) in _days.indexed)
                      Expanded(
                        child: Column(
                          children: [
                            // 모국어(주) + 한국어(병기)
                            Text(
                              bi(_daysVi[i], _daysZh[i]),
                              textAlign: TextAlign.center,
                              style: GaonType.caption.copyWith(
                                fontWeight: FontWeight.w600,
                                color: i == 0
                                    ? GaonColors.warning
                                    : GaonColors.textSecondary,
                              ),
                            ),
                            Text(
                              d,
                              textAlign: TextAlign.center,
                              style: GaonType.micro.copyWith(
                                color: i == 0
                                    ? GaonColors.warning
                                    : GaonColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),

              // 날짜 그리드 — iOS 캘린더식 고정 크기(QA C-1): 항상 6주 × 고정
              // 행 높이라 월 이동·날짜 선택에도 달력 높이가 변하지 않는다.
              // crossAxisAlignment.stretch로 셀 전체(가로×세로)가 히트 영역(QA C-2).
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  GaonSpace.xs,
                  0, // 요일 헤더 바로 아래 밀착(QA C-3)
                  GaonSpace.xs,
                  GaonSpace.xxs,
                ),
                child: Builder(
                  builder: (context) {
                    final offset = _visibleMonth.weekday % 7; // 일요일 시작
                    final daysInMonth = DateTime(
                      _visibleMonth.year,
                      _visibleMonth.month + 1,
                      0,
                    ).day;
                    // 항상 6주 — 4~5주 달도 같은 높이(빈 행 유지)
                    const rows = 6;
                    return Column(
                      children: [
                        for (var week = 0; week < rows; week++)
                          SizedBox(
                            height: 48,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (var wd = 0; wd < 7; wd++)
                                  Expanded(
                                    child: _dayCell(
                                      week * 7 + wd + 1 - offset,
                                      daysInMonth,
                                      selectedDay,
                                      children,
                                      eventsByDay,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),

              // 하단 — 고정 영역(Expanded)의 선택일 일정 목록(iOS 캘린더식).
              // 일정 없는 날도 영역 자체는 유지하고 옅은 안내만(QA C-1 — 점프 없음).
              Expanded(
                child: selectedEvents.isEmpty
                    ? Center(
                        child: Text(
                          biLine('일정이 없는 날이에요', 'Không có lịch', '当天没有日程'),
                          style: GaonType.caption.copyWith(
                            color: GaonColors.textSecondary,
                          ),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(
                          GaonSpace.md,
                          GaonSpace.xs,
                          GaonSpace.md,
                          GaonSpace.md,
                        ),
                        children: [
                          Text(
                            '${bi('Ngày $selectedDay/${_visibleMonth.month}', '${_visibleMonth.month}月$selectedDay日')} · '
                            '${_visibleMonth.month}월 $selectedDay일 · '
                            '${_dday(selectedEvents.first.event.date)}',
                            style: GaonType.h3.copyWith(
                              color:
                                  selectedEvents.first.event.type ==
                                      CalendarEventType.deadline
                                  ? GaonColors.warning
                                  : GaonColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: GaonSpace.xs),
                          for (final v in selectedEvents)
                            Padding(
                              padding: const EdgeInsets.only(
                                bottom: GaonSpace.xs,
                              ),
                              child: Material(
                                color: GaonColors.surface,
                                borderRadius: BorderRadius.circular(
                                  GaonRadius.lg,
                                ),
                                child: InkWell(
                                  onTap: () => _showDetail(analysis, v),
                                  borderRadius: BorderRadius.circular(
                                    GaonRadius.lg,
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: GaonSpace.sm,
                                      horizontal: GaonSpace.md,
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 8,
                                          height: 8,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: _dotColor(children, v.event),
                                          ),
                                        ),
                                        const SizedBox(width: GaonSpace.xs),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                v.event.title,
                                                style: GaonType.body.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                  color:
                                                      v.event.type ==
                                                          CalendarEventType
                                                              .deadline
                                                      ? GaonColors.warning
                                                      : GaonColors.textPrimary,
                                                ),
                                              ),
                                              // 출처 문서(QA D-5) — 없으면 생략
                                              if (v.sourceTitle != null)
                                                Text(
                                                  '${bi('Nguồn', '来源')} · 출처: ${v.sourceTitle}',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: GaonType.micro
                                                      .copyWith(
                                                        color: GaonColors
                                                            .textSecondary,
                                                      ),
                                                ),
                                            ],
                                          ),
                                        ),
                                        Text(
                                          _dday(v.event.date),
                                          style: GaonType.caption.copyWith(
                                            color: GaonColors.textSecondary,
                                          ),
                                        ),
                                        const Icon(
                                          Icons.chevron_right_rounded,
                                          size: 16,
                                          color: GaonColors.textSecondary,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _dayCell(
    int day,
    int daysInMonth,
    int? selectedDay,
    List<Child> children,
    Map<int, List<CalendarEventView>> eventsByDay,
  ) {
    if (day < 1 || day > daysInMonth) return const SizedBox();
    final dayEvents = eventsByDay[day] ?? const <CalendarEventView>[];
    final isSelected = day == selectedDay;
    return GestureDetector(
      onTap: () => setState(() => _selectedDay = day),
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isSelected ? GaonColors.textPrimary : Colors.transparent,
            ),
            alignment: Alignment.center,
            child: Text(
              '$day',
              style: GaonType.label.copyWith(
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                color: isSelected
                    ? GaonColors.onPrimary
                    : GaonColors.textPrimary,
              ),
            ),
          ),
          SizedBox(
            height: 6,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final v in dayEvents)
                  Container(
                    width: 4,
                    height: 4,
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _dotColor(children, v.event),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
