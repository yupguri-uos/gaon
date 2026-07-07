import 'package:flutter_test/flutter_test.dart';

import 'package:fe/data/mock_repository.dart';
import 'package:fe/models/schema.dart';

void main() {
  group('Chain A 상태 진행 시뮬레이션', () {
    test('경과 시간에 따라 uploaded → parsing → translating → action → done',
        () async {
      var clock = DateTime(2025, 6, 10, 9, 0, 0);
      final repo = MockRepository(
        latency: Duration.zero,
        wallClock: () => clock,
      );

      final doc = await repo.uploadDocument(imageRef: 'demo://notice.jpg');
      expect(doc.status, DocStatus.uploaded);

      Future<DocStatus> statusAfter(Duration elapsed) async {
        clock = DateTime(2025, 6, 10, 9, 0, 0).add(elapsed);
        return (await repo.getDocument(doc.documentId)).status;
      }

      expect(await statusAfter(const Duration(milliseconds: 500)),
          DocStatus.parsing);
      expect(await statusAfter(const Duration(milliseconds: 1800)),
          DocStatus.translating);
      expect(await statusAfter(const Duration(milliseconds: 2800)),
          DocStatus.action);
      expect(await statusAfter(const Duration(seconds: 4)), DocStatus.done);
    });

    test('모르는 documentId는 에러', () {
      final repo = MockRepository(latency: Duration.zero);
      expect(() => repo.getDocument('nope'), throwsStateError);
    });

    test('분석 결과: requiresReply=true ↔ replyDraftKo 존재 (F-DOC-8 정합)',
        () async {
      final repo = MockRepository(latency: Duration.zero);
      final analysis = await repo.getLatestAnalysis();
      expect(analysis.extractedItem.requiresReply, isTrue);
      expect(analysis.actionCard.replyDraftKo, isNotNull);
      // 마감일이 캘린더 deadline 이벤트로도 존재
      final deadlineEvent = analysis.actionCard.calendarEvents
          .firstWhere((e) => e.type == CalendarEventType.deadline);
      expect(deadlineEvent.date, analysis.extractedItem.deadline);
    });
  });

  group('Chain B (교사 메시지)', () {
    test('상황별로 다른 경어체 메시지 + 입력 보존', () async {
      final repo = MockRepository(latency: Duration.zero);
      const input = 'Ngày mai con bị sốt nên xin phép nghỉ học.';

      final absence = await repo.generateTeacherMessage(
          situation: MessageSituation.absence, inputNative: input);
      final consult = await repo.generateTeacherMessage(
          situation: MessageSituation.consultation, inputNative: input);

      expect(absence.situation, MessageSituation.absence);
      expect(absence.inputNative, input);
      expect(absence.outputKo, contains('결석'));
      expect(consult.outputKo, contains('상담'));
      expect(absence.outputKo, isNot(consult.outputKo));
      expect(absence.adminGuideNative, isNotEmpty);
    });
  });

  group('리포트 데이터', () {
    test('4주치 활동 + 카운트 존재 (응답률은 화면에서 처리/(처리+누락)로 계산)', () async {
      final repo = MockRepository(latency: Duration.zero);
      final log = await repo.getActivityLog();
      expect(log.weeklyActivity, hasLength(4));
      expect(log.processedCount, greaterThan(0));
      // 응답률 계산이 0으로 나누기가 되지 않는지 보장
      expect(log.processedCount + log.missedCount, greaterThan(0));
    });
  });
}
