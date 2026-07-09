import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  static const _weekdaysKo = ['월', '화', '수', '목', '금', '토', '일'];
  // 데모 시나리오: 2025년 6월 — 일요일 시작, 30일.
  static const _totalDays = 30;

  late final Future<(List<Child>, DocumentAnalysis)> _future = () async {
    final children = repository.getChildren();
    final analysis = repository.getLatestAnalysis();
    return (await children, await analysis);
  }();

  int _selectedDay = 12;

  DateTime get _today => repository.now();

  String _dday(DateTime date) {
    final diff = date.difference(_today).inDays;
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

  Future<void> _copyKeyword(String keyword) async {
    await Clipboard.setData(ClipboardData(text: keyword));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("'$keyword' 복사했어요 · Đã sao chép")),
    );
  }

  // ── S10: 날짜 상세 바텀시트 ──
  void _showDetail(DocumentAnalysis analysis, CalendarEvent event) {
    var showTranslated = true;
    final urgent = event.type == CalendarEventType.deadline;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: GaonColors.surface,
      barrierColor: const Color(0x59011D14),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(GaonRadius.xxl)),
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
                                      : GaonColors.textPrimary)),
                          Text(
                              '${event.title} · ${_dday(event.date)}',
                              style: GaonType.caption.copyWith(
                                  color: GaonColors.textSecondary)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: GaonColors.primaryLight,
                        borderRadius:
                            BorderRadius.circular(GaonRadius.pill),
                      ),
                      child: Row(
                        children: [
                          for (final (i, t) in const ['원본', '번역'].indexed)
                            GestureDetector(
                              onTap: () => setSheetState(
                                  () => showTranslated = i == 1),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 4, horizontal: 12),
                                decoration: BoxDecoration(
                                  color: (i == 1) == showTranslated
                                      ? GaonColors.textPrimary
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(
                                      GaonRadius.pill),
                                ),
                                child: Text(t,
                                    style: GaonType.caption.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: (i == 1) == showTranslated
                                            ? GaonColors.onPrimary
                                            : GaonColors.textSecondary)),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: GaonSpace.md),

                // 내용 — 번역(요약) ↔ 원본(rawText)
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
                        color: GaonColors.textPrimary, height: 1.7),
                  ),
                ),
                const SizedBox(height: GaonSpace.sm),

                // 검색어 추천 (F-DOC-6) — 키워드 있는 supply만(§17.11: 비구매 항목은 null)
                if (analysis.actionCard.supplies
                    .any((s) => s.ecommerceKeyword != null))
                  Container(
                    padding: const EdgeInsets.all(GaonSpace.sm),
                    decoration: BoxDecoration(
                      color: GaonColors.primaryLight,
                      borderRadius: BorderRadius.circular(GaonRadius.lg),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('🛒 검색어 추천 · Từ khóa mua sắm',
                            style: GaonType.caption.copyWith(
                                fontWeight: FontWeight.w600,
                                color: GaonColors.textPrimary)),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          children: [
                            for (final s in analysis.actionCard.supplies)
                              if (s.ecommerceKeyword case final keyword?)
                              Material(
                                color: GaonColors.textPrimary,
                                borderRadius: BorderRadius.circular(
                                    GaonRadius.pill),
                                child: InkWell(
                                  onTap: () => _copyKeyword(keyword),
                                  borderRadius: BorderRadius.circular(
                                      GaonRadius.pill),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 5, horizontal: 12),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(keyword,
                                            style: GaonType.caption
                                                .copyWith(
                                                    fontWeight:
                                                        FontWeight.w600,
                                                    color: GaonColors
                                                        .onPrimary)),
                                        const SizedBox(width: 4),
                                        const Icon(Icons.copy_rounded,
                                            size: 10,
                                            color: GaonColors.primary),
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
                  label: '📅 캘린더 추가 · Thêm vào lịch',
                  onTap: () {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('기기 캘린더에 추가했어요 (데모)')));
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
          if (!snap.hasData) {
            return const Center(
                child: CircularProgressIndicator(
                    color: GaonColors.textSecondary));
          }
          final (children, analysis) = snap.data!;
          final events = analysis.actionCard.calendarEvents;
          final eventsByDay = <int, List<CalendarEvent>>{};
          for (final e in events) {
            if (e.date.year == _today.year && e.date.month == _today.month) {
              eventsByDay.putIfAbsent(e.date.day, () => []).add(e);
            }
          }
          final selectedEvents = eventsByDay[_selectedDay] ?? const [];

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
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${_today.year}년 ${_today.month}월',
                              style: GaonType.h1.copyWith(
                                  color: GaonColors.textPrimary)),
                          Text('Tháng ${_today.month}, ${_today.year}',
                              style: GaonType.caption.copyWith(
                                  color: GaonColors.textSecondary)),
                        ],
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

              // 날짜 그리드
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      vertical: 4, horizontal: GaonSpace.xs),
                  child: Column(
                    children: [
                      for (var week = 0; week < 5; week++)
                        Expanded(
                          child: Row(
                            children: [
                              for (var wd = 0; wd < 7; wd++)
                                Expanded(
                                  child: _dayCell(week * 7 + wd + 1,
                                      children, eventsByDay),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // 선택일 프리뷰 바
              if (selectedEvents.isNotEmpty)
                Material(
                  color: GaonColors.surface,
                  child: InkWell(
                    onTap: () =>
                        _showDetail(analysis, selectedEvents.first),
                    child: Container(
                      decoration: const BoxDecoration(
                        border: Border(
                            top: BorderSide(color: GaonColors.border)),
                      ),
                      padding: const EdgeInsets.symmetric(
                          vertical: GaonSpace.sm,
                          horizontal: GaonSpace.md),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                    '${_today.month}월 $_selectedDay일 · '
                                    '${_dday(selectedEvents.first.date)}',
                                    style: GaonType.h3.copyWith(
                                        color: selectedEvents.first.type ==
                                                CalendarEventType.deadline
                                            ? GaonColors.warning
                                            : GaonColors.textPrimary)),
                                Text(
                                    selectedEvents
                                        .map((e) => e.title)
                                        .join(' · '),
                                    style: GaonType.caption.copyWith(
                                        color:
                                            GaonColors.textSecondary)),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded,
                              size: 18, color: GaonColors.textSecondary),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _dayCell(int day, List<Child> children,
      Map<int, List<CalendarEvent>> eventsByDay) {
    if (day > _totalDays) return const SizedBox();
    final dayEvents = eventsByDay[day] ?? const [];
    final isSelected = day == _selectedDay;
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
    );
  }
}
