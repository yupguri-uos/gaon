import 'package:flutter_test/flutter_test.dart';

import 'package:fe/data/locator.dart';
import 'package:fe/main.dart';

import 'fakes/fake_repository.dart';

void main() {
  setUp(() {
    // locator 기본은 ApiRepository(실 네트워크·launchUrl) — 테스트 대역으로 격리.
    // login_screen이 비 ApiRepository면 OAuth 없이 온보딩으로 직행한다.
    repository = FakeRepository(latency: Duration.zero);
  });

  testWidgets('첫 화면은 로그인(카카오 진입점)이다', (tester) async {
    await tester.pumpWidget(const GaonApp());

    expect(find.text('카카오로 시작하기'), findsOneWidget);
    expect(find.text('계속하면 서비스 약관에 동의합니다'), findsOneWidget);
  });

  testWidgets('카카오 로그인 탭 시 온보딩(본인정보)으로 이동한다', (tester) async {
    await tester.pumpWidget(const GaonApp());

    await tester.tap(find.text('카카오로 시작하기'));
    await tester.pumpAndSettle();

    expect(find.text('내 정보를 알려주세요'), findsOneWidget);
    expect(find.text('🇻🇳 베트남'), findsOneWidget);
  });
}
