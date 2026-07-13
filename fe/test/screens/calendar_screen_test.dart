import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fe/data/app_lang.dart';
import 'package:fe/data/app_nav.dart';
import 'package:fe/data/locator.dart';
import 'package:fe/models/schema.dart';
import 'package:fe/screens/calendar_screen.dart';

import '../fakes/fake_repository.dart';

/// 캘린더 UI 재작업(QA C-1~C-4) 회귀 테스트.
/// FakeRepository의 기준일은 2025-06-10 — repository.now() 기준 월 검증에 사용.
void main() {
  setUp(() {
    repository = FakeRepository(latency: Duration.zero);
    calendarLastMonth = null; // 전역 월 상태 격리
    calendarFocus.value = null;
    appLanguage.value = NativeLanguage.vi;
  });

  Future<void> pumpCalendar(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: CalendarScreen())),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('기본 월 = repository.now() 기준 월 (C-4)', (tester) async {
    await pumpCalendar(tester);
    // FakeRepository 기준일(2025-06-10)의 월 — 병기(한국어) 라인으로 확인
    expect(find.text('2025년 6월'), findsOneWidget);
  });

  testWidgets('그리드는 항상 6주 × 48px 고정 — 월 이동에도 불변 (C-1)', (tester) async {
    await pumpCalendar(tester);
    bool isWeekRow(Widget w) =>
        w is SizedBox && w.height == 48 && w.child is Row;
    expect(find.byWidgetPredicate(isWeekRow), findsNWidgets(6));

    // 다음 달로 이동해도 행 수·높이 동일(레이아웃 점프 없음)
    await tester.tap(
      find.widgetWithIcon(IconButton, Icons.chevron_right_rounded),
    );
    await tester.pumpAndSettle();
    expect(find.byWidgetPredicate(isWeekRow), findsNWidgets(6));
  });

  testWidgets('일정 없는 날 선택 시 하단은 옅은 안내로 유지 (C-1)', (tester) async {
    await pumpCalendar(tester);
    // 6/25는 데모 일정이 없는 날 — 하단 영역이 사라지지 않고 안내 문구 표시
    await tester.tap(find.text('25'));
    await tester.pumpAndSettle();
    expect(find.textContaining('일정이 없는 날이에요'), findsOneWidget);
  });

  testWidgets('월 이동 후 화면이 재생성돼도 마지막 월 유지 (C-4)', (tester) async {
    await pumpCalendar(tester);
    await tester.tap(
      find.widgetWithIcon(IconButton, Icons.chevron_right_rounded),
    );
    await tester.pumpAndSettle();
    expect(find.text('2025년 7월'), findsOneWidget);

    // 탭 트리 재생성 시뮬레이션(언어 변경·KeyedSubtree 등) — 새 인스턴스로 교체
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox())),
    );
    await pumpCalendar(tester);
    expect(find.text('2025년 7월'), findsOneWidget);
  });
}
