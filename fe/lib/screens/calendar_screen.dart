import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/app_nav.dart';
import '../data/app_lang.dart';
import '../data/locator.dart';
import '../data/notification_service.dart';
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
  static const _weekdaysKo = ['월', '화', '수', '목', '금', '토', '일'];

  late Future<(List<Child>, List<CalendarEvent>, DocumentAnalysis?)> _future =
      _load();

  Future<(List<Child>, List<CalendarEvent>, DocumentAnalysis?)> _load() async {
    // 일정 그리드 = 저장된 전체 캘린더(GET /calendar/events, F-CAL-1) —
    // '최신 분석 1건'이 아니라 여러 문서의 일정이 누적 표시된다.
    final children = repository.getChildren();
    final events = repository.getCalendarEvents();
    // 상세 시트의 원문/번역·검색어는 최신 분석에서 — 분석 전이면 null(시트 축약 표시).
    // (§7 CalendarEvent에 document_id가 없어 일정별 원문 역추적은 SSOT 결정 대기)
    DocumentAnalysis? analysis;
    try {
      analysis = await repository.getLatestAnalysis();
    } catch (_) {}
    return (await children, await events, analysis);
  }

  /// 표시 중인 월(1일 고정) — ◀▶로 자유 이동.
  late DateTime _visibleMonth = DateTime(_today.year, _today.month);
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
    setState(() => _future = _load());
  }

  /// 저장 직후 "확인" 등으로 특정 일정에 포커스 — 해당 월로 이동 + 목록 갱신.
  void _onFocus() {
    final date = calendarFocus.value;
    if (date == null) return;
    calendarFocus.value = null; // 소비
    setState(() {
      _visibleMonth = DateTime(date.year, date.month);
      _selectedDay = date.day;
      _future = _load(); // 방금 저장된 일정 반영
    });
  }

  void _shiftMonth(int delta) {
    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + delta);
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
      SnackBar(content: Text("'$keyword' 복사했어요 · ${bi('Đã sao chép', '已复制')}")),
    );
  }

  // ── S10: 날짜 상세 바텀시트 ──
  // [analysis]는 최신 분석(원문/번역·검색어 표시용) — 없으면 해당 섹션을 생략한다.
  void _showDetail(DocumentAnalysis? analysis, CalendarEvent event) {
    var showTranslated = true;
    final urgent = event.type == CalendarEventType.deadline;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: GaonColors.surface,
      barrierColor: const Color(0x59011D14),
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
                            '${event.date.month}월 ${event.date.day}일 '
                            '${_weekdaysKo[event.date.weekday - 1]}요일',
                            style: GaonType.h2.copyWith(
                              color: urgent
                                  ? GaonColors.warning
                                  : GaonColors.textPrimary,
                            ),
                          ),
                          Text(
                            '${event.title} · ${_dday(event.date)}',
                            style: GaonType.caption.copyWith(
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
                            for (final (i, t) in const ['원본', '번역'].indexed)
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
                          '🛒 검색어 추천 · ${bi('Từ khóa mua sắm', '购物关键词')}',
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
                const SizedBox(height: GaonSpace.md),
                GaonButton(
                  label: '🔔 리마인드 알림 예약 · ${bi('Đặt nhắc nhở', '设置提醒')}',
                  onTap: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    Navigator.of(context).pop();
                    // 마감 D-2·행사 전날 잠금화면 리마인드(F-PRO-2·3 로컬)
                    await NotificationService.instance.scheduleEventReminders([
                      event,
                    ]);
                    messenger.showSnackBar(
                      const SnackBar(content: Text('리마인드 알림을 예약했어요 🔔')),
                    );
                  },
                ),
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
              message: '캘린더를 불러오지 못했어요',
              subMessage: '네트워크 확인 후 다시 시도해 주세요',
              onRetry: () => setState(() => _future = _load()),
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
              message: '저장된 일정이 없어요',
              subMessage:
                  '알림장을 분석하고 캘린더에 추가해 보세요 · ${bi('Hãy phân tích thông báo và thêm vào lịch', '请分析通知单并添加到日历')}',
              onRetry: () => setState(() => _future = _load()),
            );
          }
          final eventsByDay = <int, List<CalendarEvent>>{};
          for (final e in events) {
            if (e.date.year == _visibleMonth.year &&
                e.date.month == _visibleMonth.month) {
              eventsByDay.putIfAbsent(e.date.day, () => []).add(e);
            }
          }
          // 선택일이 없으면 이 월의 첫 일정 날로 자동 선택
          final selectedDay =
              _selectedDay ??
              (eventsByDay.keys.isEmpty
                  ? null
                  : eventsByDay.keys.reduce((a, b) => a < b ? a : b));
          final selectedEvents = selectedDay == null
              ? const <CalendarEvent>[]
              : (eventsByDay[selectedDay] ?? const <CalendarEvent>[]);

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
                            '${_visibleMonth.year}년 ${_visibleMonth.month}월',
                            textAlign: TextAlign.center,
                            style: GaonType.h2.copyWith(
                              color: GaonColors.textPrimary,
                            ),
                          ),
                          Text(
                            bi(
                              'Tháng ${_visibleMonth.month}, ${_visibleMonth.year}',
                              '${_visibleMonth.year}年${_visibleMonth.month}月',
                            ),
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

              // 요일 헤더
              Container(
                color: GaonColors.surface,
                padding: const EdgeInsets.symmetric(
                  vertical: GaonSpace.xs,
                  horizontal: GaonSpace.sm,
                ),
                child: Row(
                  children: [
                    for (final (i, d) in _days.indexed)
                      Expanded(
                        child: Text(
                          d,
                          textAlign: TextAlign.center,
                          style: GaonType.caption.copyWith(
                            fontWeight: FontWeight.w600,
                            color: i == 0
                                ? GaonColors.warning
                                : GaonColors.textSecondary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // 날짜 그리드 — 행 높이 고정(QA 2026-07-11: 선택 여부와 무관하게
              // 달력 크기 불변, 터치 구획도 날짜 행에 밀착)
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 4,
                  horizontal: GaonSpace.xs,
                ),
                child: Builder(
                  builder: (context) {
                    final offset = _visibleMonth.weekday % 7; // 일요일 시작
                    final daysInMonth = DateTime(
                      _visibleMonth.year,
                      _visibleMonth.month + 1,
                      0,
                    ).day;
                    final rows = ((offset + daysInMonth) / 7).ceil();
                    return Column(
                      children: [
                        for (var week = 0; week < rows; week++)
                          SizedBox(
                            height: 52,
                            child: Row(
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

              // 하단 — 선택일 일정 목록(iOS 캘린더식). 일정 없는 날은 빈 영역.
              Expanded(
                child: selectedEvents.isEmpty
                    ? const SizedBox.shrink()
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(
                          GaonSpace.md,
                          GaonSpace.xs,
                          GaonSpace.md,
                          GaonSpace.md,
                        ),
                        children: [
                          Text(
                            '${_visibleMonth.month}월 $selectedDay일 · '
                            '${_dday(selectedEvents.first.date)}',
                            style: GaonType.h3.copyWith(
                              color:
                                  selectedEvents.first.type ==
                                      CalendarEventType.deadline
                                  ? GaonColors.warning
                                  : GaonColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: GaonSpace.xs),
                          for (final e in selectedEvents)
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
                                  onTap: () => _showDetail(analysis, e),
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
                                            color: _dotColor(children, e),
                                          ),
                                        ),
                                        const SizedBox(width: GaonSpace.xs),
                                        Expanded(
                                          child: Text(
                                            e.title,
                                            style: GaonType.body.copyWith(
                                              fontWeight: FontWeight.w600,
                                              color:
                                                  e.type ==
                                                      CalendarEventType.deadline
                                                  ? GaonColors.warning
                                                  : GaonColors.textPrimary,
                                            ),
                                          ),
                                        ),
                                        Text(
                                          _dday(e.date),
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
    Map<int, List<CalendarEvent>> eventsByDay,
  ) {
    if (day < 1 || day > daysInMonth) return const SizedBox();
    final dayEvents = eventsByDay[day] ?? const [];
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
                for (final e in dayEvents)
                  Container(
                    width: 4,
                    height: 4,
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _dotColor(children, e),
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
