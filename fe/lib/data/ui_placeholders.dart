/// UI 전용 플레이스홀더 — shared-schema에 아직 없는 개념의 표시용 데이터.
///
/// 받는 사람(교사) 목록: schema에 Teacher 엔티티가 없어(SSOT 결정 대기)
/// message_screen의 수신자 선택 UI에서만 쓴다. 서버 데이터가 아니므로
/// GaonRepository를 거치지 않는다 — Teacher가 schema에 정식 반영되면
/// SSOT → schema → 여기 제거 순서로 정리한다.
library;

const demoTeachers = [
  (name: '박지수 선생님', role: '2학년 3반 담임'),
  (name: '김민정 선생님', role: '영어 전담'),
  (name: '이현우 선생님', role: '체육 전담'),
];
