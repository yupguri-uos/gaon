import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fe/data/locator.dart';
import 'package:fe/data/mock_repository.dart';
import 'package:fe/screens/chat_screen.dart';

/// 알림장 탭(Chain A 허브)이 저장소(모델)에서 렌더링되는지 검증.
void main() {
  setUp(() {
    // 지연 없는 mock으로 교체 — locator 덕에 화면 코드 수정 없이 주입.
    repository = MockRepository(latency: Duration.zero);
  });

  testWidgets('빈 상태: 업로드 안내 + 자녀 선택기(Child 모델)', (tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: ChatScreen())));
    await tester.pumpAndSettle();

    expect(find.text('알림장을 올려주세요'), findsOneWidget);
    expect(find.text('사진 올리기'), findsOneWidget);
    // Child.name + grade/classNo에서 도출된 선택기 라벨
    expect(find.textContaining('이서준'), findsOneWidget);
  });

  testWidgets('업로드 → status 폴링 → 번역 결과(단어 해설 칩)', (tester) async {
    // 시간 제어: 업로드 즉시 done이 되도록 시계를 미래로.
    var clock = DateTime(2025, 6, 10, 9);
    repository = MockRepository(
      latency: Duration.zero,
      wallClock: () => clock,
    );

    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: ChatScreen())));
    await tester.pumpAndSettle();

    await tester.tap(find.text('사진 올리기'));
    await tester.pumpAndSettle(); // 소스 선택 시트(F-DOC-1)
    await tester.tap(find.text('데모 알림장 사용'));
    await tester.pump(); // 업로드 시작
    clock = clock.add(const Duration(seconds: 10)); // 체인 완료 시점으로 점프
    await tester.pump(const Duration(milliseconds: 300)); // 폴링 1회
    await tester.pumpAndSettle();

    // S6 번역 결과: 원문·번역·단어 해설 칩
    expect(find.text('번역 완료'), findsOneWidget);
    expect(find.text('원문 한국어'), findsOneWidget);
    expect(find.text('현장체험학습 ?'), findsOneWidget);
    expect(find.text('📅 캘린더 저장'), findsOneWidget);
  });
}
