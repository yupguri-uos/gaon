import 'package:flutter_test/flutter_test.dart';

import 'package:fe/models/schema.dart';

/// schema.py(Pydantic)와의 wire 호환 검증:
/// snake_case 키, Literal 문자열, date='yyyy-MM-dd', 기본값·null 처리.
void main() {
  group('값 타입 wire 매핑', () {
    test('Literal 문자열과 1:1', () {
      expect(OriginCountry.vn.wire, 'VN');
      expect(NativeLanguage.zh.wire, 'zh');
      expect(ChildGrade.elem2.wire, 'elem_2');
      expect(ChildGrade.elem6.wire, 'elem_6');
      expect(ChildGrade.values, hasLength(6)); // 초1~6 (팀 결정, 0009)
      expect(DocStatus.translating.wire, 'translating');
      expect(MessageSituation.sickNote.wire, 'sick_note');
      expect(NotificationType.deadlineD2.wire, 'deadline_d2');
    });

    test('fromWire 왕복', () {
      for (final s in DocStatus.values) {
        expect(DocStatus.fromWire(s.wire), s);
      }
      for (final s in MessageSituation.values) {
        expect(MessageSituation.fromWire(s.wire), s);
      }
    });

    test('모르는 wire 값은 에러 — 스키마 드리프트 조기 발견', () {
      expect(() => DocStatus.fromWire('unknown'), throwsStateError);
    });
  });

  group('Document', () {
    test('fromJson: status 기본값 uploaded', () {
      final doc = Document.fromJson({
        'document_id': 'd1',
        'user_id': 'u1',
        'image_ref': 'minio://bucket/img.jpg',
        'created_at': '2025-06-10T08:30:00Z',
      });
      expect(doc.status, DocStatus.uploaded);
      expect(doc.childId, isNull);
    });

    test('toJson 왕복', () {
      final doc = Document(
        documentId: 'd1',
        userId: 'u1',
        childId: 'c1',
        imageRef: 'minio://bucket/img.jpg',
        status: DocStatus.action,
        createdAt: DateTime.utc(2025, 6, 10, 8, 30),
      );
      final restored = Document.fromJson(doc.toJson());
      expect(restored.status, DocStatus.action);
      expect(restored.childId, 'c1');
      expect(doc.toJson()['status'], 'action');
    });
  });

  group('ExtractedItem', () {
    test('데모 시나리오(2학년 3반 알림장) 파싱', () {
      final item = ExtractedItem.fromJson({
        'doc_type': 'consent',
        'title': '서울대공원 현장체험학습 동의서',
        'dates': [
          {'label': '행사일', 'date': '2025-06-16'},
        ],
        'supplies': ['색연필 12색'],
        'deadline': '2025-06-12',
        'requires_reply': true,
        'raw_text': '…원문…',
      });
      expect(item.docType, DocType.consent);
      expect(item.dates.single.date, DateTime(2025, 6, 16));
      expect(item.deadline, DateTime(2025, 6, 12));
      expect(item.requiresReply, isTrue);
      expect(item.amounts, isEmpty); // 생략된 리스트는 빈 리스트
    });

    test('toJson: date는 yyyy-MM-dd로 직렬화', () {
      final item = ExtractedItem(
        docType: DocType.notice,
        title: 't',
        deadline: DateTime(2025, 6, 12),
        rawText: 'r',
      );
      expect(item.toJson()['deadline'], '2025-06-12');
    });
  });

  group('ActionCard', () {
    test('왕복: supplies·calendar_events·reply_draft_ko', () {
      final card = ActionCard(
        supplies: const [
          Supply(
            nameKo: '색연필',
            nameNative: 'bút chì màu',
            explanationNative: '…',
            spec: '12색 이상',
            ecommerceKeyword: '색연필 12색',
          ),
        ],
        calendarEvents: [
          CalendarEvent(
            title: '동의서 마감',
            date: DateTime(2025, 6, 12),
            type: CalendarEventType.deadline,
            childId: 'c1',
          ),
        ],
        replyDraftKo: '선생님, 안녕하세요…',
      );
      final restored = ActionCard.fromJson(card.toJson());
      expect(restored.supplies.single.ecommerceKeyword, '색연필 12색');
      expect(restored.calendarEvents.single.type, CalendarEventType.deadline);
      expect(card.toJson()['calendar_events'][0]['date'], '2025-06-12');
      expect(restored.replyDraftKo, isNotNull);
    });
  });

  group('TeacherMessage / ChildInfo', () {
    test('왕복', () {
      final msg = TeacherMessage.fromJson({
        'situation': 'absence',
        'input_native': 'Ngày mai con bị sốt nên xin phép nghỉ học.',
        'output_ko': '선생님, 안녕하세요. 내일 아이가 열이 나서 결석하겠습니다.',
        'admin_guide_native': 'Nếu nghỉ quá 3 ngày liên tục, cần nộp giấy khám bệnh.',
      });
      expect(msg.situation, MessageSituation.absence);
      expect(TeacherMessage.fromJson(msg.toJson()).outputKo, msg.outputKo);
    });

    test('ChildInfo: name은 동의 시에만(null 허용)', () {
      const info = ChildInfo(grade: ChildGrade.elem2, classNo: '3');
      expect(info.toJson(), {'grade': 'elem_2', 'class_no': '3', 'name': null});
    });
  });

  group('ActivityLog', () {
    test('기본값 0 + weekly_activity(v0.7 주간 구조) 왕복', () {
      final log = ActivityLog.fromJson({'user_id': 'u1'});
      expect(log.processedCount, 0);
      expect(log.weeklyActivity, isEmpty);

      final full = ActivityLog.fromJson({
        'user_id': 'u1',
        'processed_count': 12,
        'event_participation_count': 8,
        'missed_count': 1,
        'weekly_activity': [
          {
            'week_start': '2025-06-01',
            'week_end': '2025-06-07',
            'processed_count': 3,
            'event_participation_count': 2,
          },
        ],
      });
      final week = full.weeklyActivity.single;
      expect(week.weekStart, DateTime(2025, 6, 1));
      expect(week.processedCount, 3);
      expect(week.missedCount, 0); // 생략 시 기본값
      // 왕복: week_start/week_end는 yyyy-MM-dd로 직렬화
      expect(full.toJson()['weekly_activity'][0]['week_end'], '2025-06-07');
      expect(ActivityLog.fromJson(full.toJson()).missedCount, 1);
    });
  });

  group('Child', () {
    test('school_name 왕복 (마이그레이션 0007)', () {
      final child = Child.fromJson({
        'child_id': 'c1',
        'user_id': 'u1',
        'grade': 'elem_5',
        'class_no': '3',
        'school_name': '가온초등학교',
        'created_at': '2025-05-01T09:00:00Z',
      });
      expect(child.grade, ChildGrade.elem5);
      expect(child.schoolName, '가온초등학교');
      expect(Child.fromJson(child.toJson()).schoolName, '가온초등학교');
    });
  });

  group('Notification', () {
    test('왕복', () {
      final n = Notification(
        notificationId: 'n1',
        userId: 'u1',
        type: NotificationType.deadlineD2,
        titleNative: 'Sắp đến hạn (còn 2 ngày)',
        bodyNative: 'Đơn đồng ý dã ngoại…',
        scheduledAt: DateTime.utc(2025, 6, 10, 8, 30),
        relatedDocumentId: 'd1',
      );
      final restored = Notification.fromJson(n.toJson());
      expect(restored.type, NotificationType.deadlineD2);
      expect(n.toJson()['type'], 'deadline_d2');
      expect(restored.relatedDocumentId, 'd1');
    });
  });
}
