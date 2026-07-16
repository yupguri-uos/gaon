import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fe/data/app_lang.dart';
import 'package:fe/data/locator.dart';
import 'package:fe/models/schema.dart';
import 'package:fe/screens/onboarding_child_screen.dart';

import '../fakes/fake_repository.dart';

/// 온보딩 자녀 등록(F-ON-4) — '시작하기' 검증 팝업.
/// 미완성 상태에서 눌러도 비활성이 아니라, 빠진 항목을 자녀별로 알려주는 팝업이 뜬다.
/// 라벨(biLine='vi · ko')은 뒤에 깔린 카드에도 있으므로 assertion은 팝업 내부로 한정한다.
void main() {
  setUp(() {
    repository = FakeRepository(latency: Duration.zero);
    appLanguage.value = NativeLanguage.vi; // 주 표시 = 베트남어
  });

  Future<void> pumpOnboarding(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: OnboardingChildScreen()));
    await tester.pumpAndSettle();
  }

  // 팝업(AlertDialog) 내부로 한정한 텍스트 파인더.
  Finder inDialog(String text) => find.descendant(
    of: find.byType(AlertDialog),
    matching: find.text(text),
  );

  testWidgets('빈 상태에서 시작하기 → 팝업에 4개 필수 항목이 모두 나온다', (tester) async {
    await pumpOnboarding(tester);

    await tester.tap(find.text('시작하기'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.textContaining('입력하지 않은 정보가 있어요'),
      ),
      findsOneWidget,
    );
    expect(inDialog('Con 1 · 자녀 1'), findsOneWidget);
    expect(inDialog('Tên · 이름'), findsOneWidget);
    expect(inDialog('Tên trường · 학교명'), findsOneWidget);
    expect(inDialog('Lớp · 학년'), findsOneWidget);
    expect(inDialog('Số lớp · 반'), findsOneWidget);
  });

  testWidgets('일부만 채우면 팝업은 채운 항목을 빼고 남은 것만 보여준다', (tester) async {
    await pumpOnboarding(tester);

    // 카드 내 TextField 순서: [학교명, 이름, 반]. 이름만 채운다.
    await tester.enterText(find.byType(TextField).at(1), '큰아이');
    await tester.pump();

    await tester.tap(find.text('시작하기'));
    await tester.pumpAndSettle();

    // 이름은 채웠으니 팝업 목록에서 사라진다
    expect(inDialog('Tên · 이름'), findsNothing);
    // 나머지 셋은 여전히 안내된다
    expect(inDialog('Tên trường · 학교명'), findsOneWidget);
    expect(inDialog('Lớp · 학년'), findsOneWidget);
    expect(inDialog('Số lớp · 반'), findsOneWidget);
  });

  testWidgets('확인을 누르면 팝업이 닫힌다', (tester) async {
    await pumpOnboarding(tester);

    await tester.tap(find.text('시작하기'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.tap(find.text('Đã hiểu · 확인'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });
}
