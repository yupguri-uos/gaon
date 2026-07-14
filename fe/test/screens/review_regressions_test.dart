import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fe/data/app_lang.dart';
import 'package:fe/data/app_nav.dart';
import 'package:fe/data/locator.dart';
import 'package:fe/data/repository.dart';
import 'package:fe/data/teacher_store.dart';
import 'package:fe/models/schema.dart';
import 'package:fe/screens/action_card_screen.dart';
import 'package:fe/screens/chat_screen.dart';
import 'package:fe/screens/message_screen.dart';

import '../fakes/demo_fixtures.dart';
import '../fakes/fake_repository.dart';

/// 적대적 리뷰(배치 1~5) 확정 결함 회귀 테스트 — A-1·A-2·A-3·B-1·B-2.
/// 각 테스트는 "실패 상황을 재현 → 이제 복구/에러 안내됨"을 검증한다.

/// A-1·B-1용: 결과 조회가 항상 던지거나(analysisThrows) 일정이 많은 대역.
class _ChainAFake extends FakeRepository {
  _ChainAFake({
    this.analysisThrows = false,
    this.manyEvents = false,
    super.wallClock,
  }) : super(latency: Duration.zero);

  final bool analysisThrows;
  final bool manyEvents;

  @override
  Future<DocumentAnalysis> getDocumentAnalysis(String documentId) async {
    if (analysisThrows) {
      throw StateError('분석 결과가 아직 준비되지 않았습니다: $documentId');
    }
    final base = await super.getDocumentAnalysis(documentId);
    if (!manyEvents) return base;
    return DocumentAnalysis(
      document: base.document,
      extractedItem: base.extractedItem,
      translated: base.translated,
      actionCard: ActionCard(
        supplies: base.actionCard.supplies,
        replyDraftKo: base.actionCard.replyDraftKo,
        calendarEvents: [
          for (var i = 0; i < 10; i++)
            CalendarEvent(
              title: '행사 $i',
              date: DateTime(2025, 6, 10 + i),
              type: CalendarEventType.event,
            ),
        ],
      ),
    );
  }
}

/// A-2용: 문자 생성이 항상 실패하는 대역.
class _ChainBFake extends FakeRepository {
  _ChainBFake() : super(latency: Duration.zero);

  @override
  Future<TeacherMessage> generateTeacherMessage({
    required MessageSituation situation,
    required String inputNative,
    required String childId,
  }) async {
    throw Exception('network down');
  }
}

/// 데모 알림장 업로드 → 폴링 완료(done)까지 화면을 진행시킨다.
Future<void> driveUploadToDone(
  WidgetTester tester,
  DateTime Function() clock,
  void Function(DateTime) setClock,
) async {
  await tester.pumpWidget(
    const MaterialApp(home: Scaffold(body: ChatScreen())),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('사진 올리기'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('데모 알림장 사용'));
  await tester.pump();
  setClock(clock().add(const Duration(seconds: 10))); // 체인 완료 시점으로 점프
  await tester.pump(const Duration(milliseconds: 1100)); // 폴링 1회 → done
}

void main() {
  setUp(() {
    repository = FakeRepository(latency: Duration.zero);
    SharedPreferences.setMockInitialValues({});
    appLanguage.value = NativeLanguage.vi;
    resetAppNav();
    TeacherStore.reset();
  });

  testWidgets('A-1: done 후 결과 조회가 계속 실패해도 분석 화면에 갇히지 않는다', (tester) async {
    var clock = DateTime(2025, 6, 10, 9);
    repository = _ChainAFake(analysisThrows: true, wallClock: () => clock);

    await driveUploadToDone(tester, () => clock, (c) => clock = c);

    // 재시도 3회(1초 간격) 동안은 분석 화면 유지 가능 — 이후 반드시 탈출
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.pumpAndSettle();

    // 홈(빈 상태)으로 복귀 + 실패 안내 스낵바 — 무한 '분석 중' 고착이 아님
    expect(find.text('알림장을 올려주세요'), findsOneWidget);
    expect(find.textContaining('분석 결과를 불러오지 못했어요'), findsOneWidget);
  });

  testWidgets('A-2: 문자 생성 실패 시 스피너가 복구되고 버튼을 다시 쓸 수 있다', (tester) async {
    repository = _ChainBFake();
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: MessageScreen())),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'xin chào');
    await tester.tap(find.byIcon(Icons.arrow_downward_rounded));
    await tester.pumpAndSettle();

    // 에러 안내 + 스피너 종료(화살표 아이콘 복귀 = _generating=false)
    expect(find.textContaining('메시지 생성에 실패했어요'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_downward_rounded), findsOneWidget);

    // 버튼 재사용 가능 — 두 번째 탭도 가드에 막히지 않고 다시 시도된다
    await tester.tap(find.byIcon(Icons.arrow_downward_rounded));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.arrow_downward_rounded), findsOneWidget);
  });

  testWidgets('A-3: 화면을 pop한 뒤 스낵바 "캘린더 보기"를 눌러도 예외 없이 이동한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ActionCardScreen()),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // 일정 섹션의 개별 '추가' 버튼으로 저장 → '캘린더 보기' 액션 스낵바 표시
    // (섹션이 ListView 하단이라 lazy-build — 끝까지 스크롤해 노출)
    await tester.drag(find.byType(ListView).first, const Offset(0, -3000));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Thêm · 추가').first);
    await tester.pump(const Duration(milliseconds: 300));

    // 스낵바가 떠 있는 동안 행동 카드 화면을 pop (헤더 뒤로가기) —
    // 전환 애니메이션 완료까지 대기(스낵바는 4초 유지라 그대로 남는다)
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();
    expect(find.textContaining('캘린더 보기'), findsOneWidget);

    // 액션 탭 — disposed State context 예외 없이 전역 신호로 캘린더 이동
    await tester.tap(find.textContaining('캘린더 보기'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(mainTabIndex.value, 1); // goToCalendar 실행됨
    expect(demoActionCard.calendarEvents, isNotEmpty); // 픽스처 전제 확인
  });

  testWidgets('B-1: 일정 10개여도 캘린더 저장 다이얼로그가 넘치지 않는다(스크롤)', (tester) async {
    var clock = DateTime(2025, 6, 10, 9);
    repository = _ChainAFake(manyEvents: true, wallClock: () => clock);

    await driveUploadToDone(tester, () => clock, (c) => clock = c);
    await tester.pumpAndSettle();
    expect(find.text('번역 완료'), findsOneWidget);

    await tester.tap(find.text('캘린더 저장')); // 결과 화면의 저장 버튼(subLabel)
    await tester.pumpAndSettle();

    // RenderFlex 오버플로 없이 다이얼로그가 뜨고, 목록은 스크롤·버튼은 고정
    expect(tester.takeException(), isNull);
    expect(find.textContaining('저장하기'), findsOneWidget);
    expect(find.text('행사 0'), findsOneWidget); // 목록 첫 행 렌더 확인
  });

  testWidgets('B-2: 교사 10명이어도 받는 사람 시트가 넘치지 않는다(스크롤)', (tester) async {
    for (var i = 0; i < 10; i++) {
      await TeacherStore.add(
        demoChild.childId,
        Teacher(name: '교사$i 선생님', role: '$i학년 담임'),
      );
    }
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: MessageScreen())),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('교사0 선생님')); // 헤더 칩(첫 교사 이름) → 시트 열기
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // 시트가 열려 목록이 렌더되고(첫 행), 추가 버튼도 존재
    expect(find.text('교사0 선생님'), findsWidgets);
    expect(find.textContaining('받는 사람 추가'), findsOneWidget);
  });
}
