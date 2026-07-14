import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fe/data/teacher_store.dart';

/// TeacherStore(자녀별 교사 로컬 저장, QA T-1 — 팀 결정 2026-07-13) 회귀 테스트.
/// Teacher는 FE 로컬 전용 — shared-schema·BE 무변경.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TeacherStore.reset();
  });

  test('초기 상태는 빈 목록 — 데모 프리셋 없음', () async {
    await TeacherStore.load();
    expect(TeacherStore.forChild('c1'), isEmpty);
  });

  test('자녀별로 분리 저장되고 추가/수정/삭제가 동작한다', () async {
    await TeacherStore.add(
      'c1',
      const Teacher(name: '최수민 선생님', role: '담임'),
    );
    await TeacherStore.add(
      'c2',
      const Teacher(name: '김민정 선생님', role: '영어 전담'),
    );
    expect(TeacherStore.forChild('c1').single.name, '최수민 선생님');
    expect(TeacherStore.forChild('c2').single.role, '영어 전담');

    // 수정
    await TeacherStore.update(
      'c1',
      0,
      const Teacher(name: '최수민 선생님', role: '3학년 1반 담임'),
    );
    expect(TeacherStore.forChild('c1').single.role, '3학년 1반 담임');

    // 삭제 — 다른 자녀 목록엔 영향 없음
    await TeacherStore.removeAt('c2', 0);
    expect(TeacherStore.forChild('c2'), isEmpty);
    expect(TeacherStore.forChild('c1'), hasLength(1));
  });

  test('저장 후 재로드(앱 재실행)해도 자녀별 목록이 복원된다', () async {
    await TeacherStore.add(
      'c1',
      const Teacher(name: '박담임 선생님', role: '담임'),
    );
    TeacherStore.reset(); // 앱 재시작 시뮬레이션 — 메모리 비움
    expect(TeacherStore.forChild('c1'), isEmpty);

    await TeacherStore.load(); // shared_preferences에서 복원
    final restored = TeacherStore.forChild('c1');
    expect(restored.single.name, '박담임 선생님');
    expect(restored.single.role, '담임');
  });

  test('범위 밖 인덱스 수정/삭제는 무시된다(방어)', () async {
    await TeacherStore.add('c1', const Teacher(name: 'a', role: 'r'));
    await TeacherStore.update('c1', 5, const Teacher(name: 'x', role: 'y'));
    await TeacherStore.removeAt('c1', 5);
    expect(TeacherStore.forChild('c1').single.name, 'a');
  });
}
