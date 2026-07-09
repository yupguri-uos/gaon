import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fe/data/api_repository.dart';
import 'package:fe/models/schema.dart';

/// ApiRepository ↔ BE(§11) wire 계약 검증 — MockClient로 BE 응답을 재현.
/// 실서버 스모크는 인증 토큰 확보 후 별도 수행.
void main() {
  // 한글 본문은 http.Response(String)이 Latin-1로 인코딩해 깨진다 → UTF-8 바이트로.
  http.Response jsonRes(Object body, [int status = 200]) => http.Response.bytes(
        utf8.encode(jsonEncode(body)),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  ApiRepository repoWith(Future<http.Response> Function(http.Request) handler) {
    return ApiRepository(
      client: MockClient(handler),
      baseUrl: 'https://gaon.uk/api',
      token: 'test-token',
    );
  }

  group('인증', () {
    test('토큰 없으면 호출 전에 AuthRequiredException', () {
      final repo = ApiRepository(
        client: MockClient((_) async => http.Response('{}', 200)),
        token: '',
      );
      expect(() => repo.getChildren(), throwsA(isA<AuthRequiredException>()));
    });

    test('401 응답이면 AuthRequiredException', () {
      final repo = repoWith((_) async => http.Response('unauthorized', 401));
      expect(() => repo.getChildren(), throwsA(isA<AuthRequiredException>()));
    });
  });

  group('GET /children', () {
    test('Bearer 헤더 + Child 리스트 파싱', () async {
      late http.Request captured;
      final repo = repoWith((req) async {
        captured = req;
        return jsonRes([
            {
              'child_id': 'c1',
              'user_id': 'u1',
              'name': '이서준',
              'grade': 'elem_2',
              'class_no': '3',
              'school_name': '가온초등학교',
              'color': '#011D14',
              'created_at': '2026-07-01T09:00:00Z',
            }
          ], 200);
      });

      final children = await repo.getChildren();
      expect(captured.headers['Authorization'], 'Bearer test-token');
      expect(captured.url.path, '/api/children');
      expect(children.single.name, '이서준');
      expect(children.single.grade, ChildGrade.elem2);
    });
  });

  group('POST /children', () {
    test('이름·반 있으면 consent_child_pii=true로 전송 (결정 #7-PII)', () async {
      late Map<String, dynamic> sentBody;
      final repo = repoWith((req) async {
        sentBody = jsonDecode(req.body) as Map<String, dynamic>;
        return jsonRes({
            'child_id': 'c9',
            'user_id': 'u1',
            'name': '김하늘',
            'grade': 'elem_5',
            'class_no': '2',
            'created_at': '2026-07-10T09:00:00Z',
          }, 201);
      });

      await repo.addChild(
          grade: ChildGrade.elem5, name: '김하늘', classNo: '2');
      expect(sentBody['grade'], 'elem_5');
      expect(sentBody['consent_child_pii'], isTrue);
    });
  });

  group('Chain B — POST /teacher-message', () {
    test('child_id·situation wire 전송 + TeacherMessage 파싱', () async {
      late Map<String, dynamic> sentBody;
      final repo = repoWith((req) async {
        sentBody = jsonDecode(req.body) as Map<String, dynamic>;
        return jsonRes({
            'situation': 'sick_note',
            'input_native': 'xin chào',
            'output_ko': '선생님, 안녕하세요...',
            'admin_guide_native': 'Giấy khám bệnh...',
          }, 200);
      });

      final msg = await repo.generateTeacherMessage(
        situation: MessageSituation.sickNote,
        inputNative: 'xin chào',
        childId: 'c1',
      );
      expect(sentBody['situation'], 'sick_note');
      expect(sentBody['child_id'], 'c1');
      expect(msg.outputKo, contains('선생님'));
    });
  });

  group('캘린더', () {
    test('POST /calendar/events → created 언래핑', () async {
      final repo = repoWith((_) async => jsonRes({
              'created': [
                {'title': '동의서 마감', 'date': '2026-07-12', 'type': 'deadline'},
              ]
            }, 200));
      final saved = await repo.saveCalendarEvents(documentId: 'd1');
      expect(saved.single.type, CalendarEventType.deadline);
      expect(saved.single.date, DateTime(2026, 7, 12));
    });

    test('GET /calendar/events → events 언래핑 + child_id', () async {
      final repo = repoWith((_) async => jsonRes({
              'events': [
                {
                  'id': 'e1',
                  'document_id': 'd1',
                  'child_id': 'c1',
                  'title': '현장체험학습',
                  'date': '2026-07-16',
                  'type': 'event',
                }
              ]
            }, 200));
      final events = await repo.getCalendarEvents();
      expect(events.single.childId, 'c1');
      expect(events.single.type, CalendarEventType.event);
    });
  });

  group('Chain A — 결과 조회', () {
    test('result의 null 필드(done 전) → StateError 방어', () {
      final repo = repoWith((_) async => jsonRes({
              'document': {
                'document_id': 'd1',
                'user_id': 'u1',
                'image_ref': 'k',
                'status': 'parsing',
                'created_at': '2026-07-10T09:00:00Z',
              },
              'extracted': null,
              'translated': null,
              'action_card': null,
            }, 200));
      expect(() => repo.getDocumentAnalysis('d1'), throwsStateError);
    });
  });
}
