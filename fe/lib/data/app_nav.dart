import 'package:flutter/foundation.dart';

/// 셸 탭 전환·캘린더 포커스 — UI 전용 전역 내비게이션 신호.
/// 푸시된 화면(행동 카드 등)이나 다이얼로그에서도 탭 이동이 가능하도록
/// ValueNotifier로 느슨하게 연결한다(MainShell·CalendarScreen이 구독).
final mainTabIndex = ValueNotifier<int>(0);

/// 캘린더가 열릴 때 이 날짜의 월로 이동·선택한다(소비 후 null로 리셋).
final calendarFocus = ValueNotifier<DateTime?>(null);

/// 캘린더 탭으로 이동. [date]를 주면 해당 월·일로 포커스 + 목록 새로고침.
void goToCalendar([DateTime? date]) {
  calendarFocus.value = date;
  mainTabIndex.value = 1;
}
