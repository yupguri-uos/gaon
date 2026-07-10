import 'package:flutter/material.dart';

import '../data/app_nav.dart';
import '../data/app_lang.dart';
import '../data/locator.dart';
import '../data/notification_service.dart';
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

  late Future<(List<Child>, List<CalendarEvent>)> _future = _load();

  /// 캘린더 일정은 실서버 저장분(GET /calendar/events)이 정본 —
  /// 분석 결과(제안 일정)가 아니라 사용자가 저장한 일정을 그린다.
  Future<(List<Child>, List<CalendarEvent>)> _load() async {
    final children = repository.getChildren();
    final events = repository.getCalendarEvents();
    return (await children, await events);
  }

  /// 표시 중인 월(1일 고정) — ◀▶로 자유 이동.
  late DateTime _visibleMonth =
      DateTime(_today.year, _today.month);
  int? _selectedDay;

  DateTime get _today => repository.now();

  @override
  void initState() {
    super.initState();
    calendarFocus.addListener(_onFocus);
    _onFocus(); // 진입 시점에 이미 포커스가 있으면 적용
  }

  @override
  void dispose() {
    calendarFocus.removeListener(_onFocus);
    super.dispose();
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
      _visibleMonth =
          DateTime(_visibleMonth.year, _visibleMonth.month + delta);
      _selectedDay = null;
    });
  }

  /// 자정 기준 날짜 차이 — 시각 차 때문에 하루가 밀리는 문제 방지.
  String _dday(DateTime date) {
    final diff = DateTime(date.year, date.month, date.day)
        .difference(DateTime(_today.year, _today.month, _today.day))
        .inDays;
    return diff >= 0 ? 'D-$diff' : 'D+${-diff}';
  }

  Color _childColor(List<Child> children, String? childId) {
    final hex = children
        .where((c) => c.childId == childId)
        .firstOrNull
        ?.color;
    if (hex == null) return GaonColors.textPrimary;
    return Color(int.parse('FF${hex.replaceFirst('#', '')}', radix: 16));
  }

  Color _dotColor(List<Child> children, CalendarEvent e) =>
      e.type == CalendarEventType.deadline
          ? GaonColors.warning
          : _childColor(children, e.childId);


  // ── S10: 날짜 상세 바텀시트 — 일정 정보만(원문·구매 정보는 행동 카드에서).
  void _showDetail(List<Child> children, CalendarEvent event) {
    final urgent = event.type == CalendarEventType.deadline;
    final childName =
        children.where((c) => c.childId == event.childId).firstOrNull?.name;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: GaonColors.surface,
      barrierColor: const Color(0x59011D14),
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(GaonRadius.xxl)),
      ),
      builder: (context) => SafeArea(
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
              Text(
                  '${event.date.month}월 ${event.date.day}일 '
                  '${_weekdaysKo[event.date.weekday - 1]}요일',
                  style: GaonType.h2.copyWith(
                      color: urgent
                          ? GaonColors.warning
                          : GaonColors.textPrimary)),
              const SizedBox(height: GaonSpace.md),
              Container(
                padding: const EdgeInsets.all(GaonSpace.sm),
                decoration: BoxDecoration(
                  color: GaonColors.bg,
                  borderRadius: BorderRadius.circular(GaonRadius.lg),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _dotColor(children, event),
                      ),
                    ),
                    const SizedBox(width: GaonSpace.xs),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(event.title,
                              style: GaonType.body.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: GaonColors.textPrimary)),
                          Text(
                              '${_dday(event.date)} · '
                              '${urgent ? '마감 · ${bi('Hạn nộp', '截止')}' : '행사 · ${bi('Sự kiện', '活动')}'}'
                              '${childName != null ? ' · $childName' : ''}',
                              style: GaonType.caption.copyWith(
                                  color: urgent
                                      ? GaonColors.warning
                                      : GaonColors.textSecondary)),
                        ],
                      ),
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
                  await NotificationService.instance
                      .scheduleEventReminders([event]);
                  messenger.showSnackBar(const SnackBar(
                      content: Text('리마인드 알림을 예약했어요 🔔')));
                },
              ),
            ],
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
                child: CircularProgressIndicator(
                    color: GaonColors.textSecondary));
          }
          final (children, events) = snap.data!;
          final eventsByDay = <int, List<CalendarEvent>>{};
          for (final e in events) {
            if (e.date.year == _visibleMonth.year &&
                e.date.month == _visibleMonth.month) {
              eventsByDay.putIfAbsent(e.date.day, () => []).add(e);
            }
          }
          // 선택일이 없으면 이 월의 첫 일정 날로 자동 선택
          final selectedDay = _selectedDay ??
              (eventsByDay.keys.isEmpty
                  ? null
                  : eventsByDay.keys.reduce((a, b) => a < b ? a : b));
          final selectedEvents =
              selectedDay == null ? const <CalendarEvent>[] : (eventsByDay[selectedDay] ?? const <CalendarEvent>[]);

          return Column(
            children: [
              // 월 헤더 + 자녀 범례
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
                    IconButton(
                      onPressed: () => _shiftMonth(-1),
                      icon: const Icon(Icons.chevron_left_rounded,
                          color: GaonColors.textPrimary),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                              '${_visibleMonth.year}년 ${_visibleMonth.month}월',
                              textAlign: TextAlign.center,
                              style: GaonType.h2.copyWith(
                                  color: GaonColors.textPrimary)),
                          Text(
                              bi('Tháng ${_visibleMonth.month}, ${_visibleMonth.year}',
                                  '${_visibleMonth.year}年${_visibleMonth.month}月'),
                              textAlign: TextAlign.center,
                              style: GaonType.micro.copyWith(
                                  color: GaonColors.textSecondary)),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => _shiftMonth(1),
                      icon: const Icon(Icons.chevron_right_rounded,
                          color: GaonColors.textPrimary),
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
                                    color: GaonColors.textSecondary)),
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
                    vertical: GaonSpace.xs, horizontal: GaonSpace.sm),
                child: Row(
                  children: [
                    for (final (i, d) in _days.indexed)
                      Expanded(
                        child: Text(d,
                            textAlign: TextAlign.center,
                            style: GaonType.caption.copyWith(
                              fontWeight: FontWeight.w600,
                              color: i == 0
                                  ? GaonColors.warning
                                  : GaonColors.textSecondary,
                            )),
                      ),
                  ],
                ),
              ),

              // 날짜 그리드 — 셀 높이 고정(달력 크기 불변, iOS 캘린더식).
              // 남는 공간은 아래 일정 영역이 차지하고, 일정이 없으면 비워둔다.
              Container(
                color: GaonColors.surface,
                padding: const EdgeInsets.symmetric(
                    vertical: 4, horizontal: GaonSpace.xs),
                child: Builder(builder: (context) {
                  final offset = _visibleMonth.weekday % 7; // 일요일 시작
                  final daysInMonth = DateTime(_visibleMonth.year,
                          _visibleMonth.month + 1, 0)
                      .day;
                  final rows = ((offset + daysInMonth) / 7).ceil();
                  return Column(
                    children: [
                      for (var week = 0; week < rows; week++)
                        Row(
                          children: [
                            for (var wd = 0; wd < 7; wd++)
                              Expanded(
                                child: _dayCell(
                                    week * 7 + wd + 1 - offset,
                                    daysInMonth,
                                    selectedDay,
                                    children,
                                    eventsByDay),
                              ),
                          ],
                        ),
                    ],
                  );
                }),
              ),
              Container(height: 1, color: GaonColors.border),

              // 선택일 일정 목록 — 상시 확보된 영역(없으면 빈 화면)
              Expanded(
                child: events.isEmpty
                    ? Center(
                        child: Text(
                            '저장된 일정이 없어요\n알림장 탭에서 일정을 저장해 보세요 · ${bi('Hãy lưu lịch từ thông báo', '请从通知单保存日程')}',
                            textAlign: TextAlign.center,
                            style: GaonType.caption.copyWith(
                                color: GaonColors.textSecondary,
                                height: 1.6)),
                      )
                    : selectedEvents.isEmpty
                    ? const SizedBox.shrink()
                    : ListView(
                        padding: const EdgeInsets.all(GaonSpace.sm),
                        children: [
                          for (final e in selectedEvents)
                            Padding(
                              padding: const EdgeInsets.only(
                                  bottom: GaonSpace.xs),
                              child: Material(
                                color: GaonColors.surface,
                                borderRadius: BorderRadius.circular(
                                    GaonRadius.lg),
                                child: InkWell(
                                  onTap: () => _showDetail(children, e),
                                  borderRadius: BorderRadius.circular(
                                      GaonRadius.lg),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: GaonSpace.sm,
                                        horizontal: GaonSpace.md),
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
                                        const SizedBox(
                                            width: GaonSpace.xs),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(e.title,
                                                  style: GaonType.body
                                                      .copyWith(
                                                          fontWeight:
                                                              FontWeight
                                                                  .w600,
                                                          color: GaonColors
                                                              .textPrimary)),
                                              Text(
                                                  '${e.date.month}월 ${e.date.day}일 · ${_dday(e.date)}',
                                                  style: GaonType.caption
                                                      .copyWith(
                                                          color: e.type ==
                                                                  CalendarEventType
                                                                      .deadline
                                                              ? GaonColors
                                                                  .warning
                                                              : GaonColors
                                                                  .textSecondary)),
                                            ],
                                          ),
                                        ),
                                        const Icon(
                                            Icons.chevron_right_rounded,
                                            size: 18,
                                            color:
                                                GaonColors.textSecondary),
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

  Widget _dayCell(int day, int daysInMonth, int? selectedDay,
      List<Child> children, Map<int, List<CalendarEvent>> eventsByDay) {
    if (day < 1 || day > daysInMonth) return const SizedBox(height: 46);
    final dayEvents = eventsByDay[day] ?? const [];
    final isSelected = day == selectedDay;
    return GestureDetector(
      onTap: () => setState(() => _selectedDay = day),
      behavior: HitTestBehavior.opaque,
      // 셀 높이 고정 — 터치 구획이 날짜와 1:1로 일치
      child: SizedBox(
        height: 46,
        child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color:
                  isSelected ? GaonColors.textPrimary : Colors.transparent,
            ),
            alignment: Alignment.center,
            child: Text('$day',
                style: GaonType.label.copyWith(
                  fontWeight:
                      isSelected ? FontWeight.w700 : FontWeight.w400,
                  color: isSelected
                      ? GaonColors.onPrimary
                      : GaonColors.textPrimary,
                )),
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
      ),
    );
  }
}
