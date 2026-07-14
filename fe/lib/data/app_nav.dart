import 'package:flutter/foundation.dart';

/// 셸 탭 전환·캘린더 포커스 — UI 전용 전역 내비게이션 신호.
/// 푸시된 화면(행동 카드 등)이나 다이얼로그에서도 탭 이동이 가능하도록
/// ValueNotifier로 느슨하게 연결한다(MainShell·CalendarScreen이 구독).
final mainTabIndex = ValueNotifier<int>(0);

/// 캘린더가 열릴 때 이 날짜의 월로 이동·선택한다(소비 후 null로 리셋).
final calendarFocus = ValueNotifier<DateTime?>(null);

/// 캘린더가 마지막으로 보던 월(1일 정규화) — 화면 상태와 별도로 보존해
/// 탭 전환은 물론, 언어 변경 등으로 탭 트리가 재생성돼도 유지된다(QA C-4).
/// 앱 재시작 시엔 null → 오늘 기준 월로 시작.
DateTime? calendarLastMonth;

/// 자녀 정보(이름·학년·반 등) 변경 신호 — 값 자체는 의미 없고 증가만 한다.
/// 설정의 자녀 추가·수정·삭제가 끝나면 이걸 올려서, IndexedStack으로 계속
/// 살아있는 홈(챗봇)·문자 탭이 캐시해 둔 자녀 목록을 다시 불러오게 한다.
final childrenVersion = ValueNotifier<int>(0);

/// 캘린더 탭으로 이동. [date]를 주면 해당 월·일로 포커스 + 목록 새로고침.
void goToCalendar([DateTime? date]) {
  calendarFocus.value = date;
  mainTabIndex.value = 1;
}

/// 로그아웃·회원탈퇴 시 전역 내비 상태 초기화(적대적 리뷰 C-1) —
/// 리셋하지 않으면 재로그인/신규 계정이 설정 탭·이전 계정의 월에서 시작한다.
void resetAppNav() {
  mainTabIndex.value = 0;
  calendarFocus.value = null;
  calendarLastMonth = null;
}
