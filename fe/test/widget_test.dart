import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fe/data/app_lang.dart';
import 'package:fe/data/locator.dart';
import 'package:fe/main.dart';

import 'fakes/fake_repository.dart';

void main() {
  setUp(() {
    // locator 기본은 ApiRepository(실 네트워크·launchUrl) — 테스트 대역으로 격리.
    // login_screen이 비 ApiRepository면 OAuth 없이 자녀 등록으로 직행한다.
    repository = FakeRepository(latency: Duration.zero);
    SharedPreferences.setMockInitialValues({});
    AppLangStore.reset(); // 첫 실행(언어 미선택) 상태로
  });

  testWidgets('첫 실행은 언어 선택 화면이 가장 먼저다 (F-ON-1)', (tester) async {
    await tester.pumpWidget(const GaonApp());

    expect(find.text('언어를 선택해주세요'), findsOneWidget);
    expect(find.text('Tiếng Việt'), findsOneWidget);
    expect(find.text('中文'), findsOneWidget);
  });

  testWidgets('언어 탭 시 표시 언어가 즉시 전환된다', (tester) async {
    await tester.pumpWidget(const GaonApp());

    expect(find.text('Vui lòng chọn ngôn ngữ'), findsOneWidget); // 기본 vi
    await tester.tap(find.text('中文'));
    await tester.pumpAndSettle();
    expect(find.text('请选择语言'), findsOneWidget); // 실시간 전환
  });

  testWidgets('언어 선택 → 로그인 → 자녀 등록으로 이어진다', (tester) async {
    await tester.pumpWidget(const GaonApp());

    await tester.tap(find.text('Tiếng Việt'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('다음')); // '다음' = 계속 버튼 병기
    await tester.pumpAndSettle();

    // 로그인 화면 — 모국어 주 + 한국어 병기
    expect(find.text('Bắt đầu với Kakao'), findsOneWidget);
    expect(find.text('카카오로 시작하기'), findsOneWidget);

    await tester.tap(find.text('카카오로 시작하기'));
    await tester.pumpAndSettle();

    // 테스트 대역 경로: OAuth 없이 자녀 등록(F-ON-4)으로 직행
    expect(find.text('자녀 정보를 등록해요'), findsOneWidget);
  });
}
