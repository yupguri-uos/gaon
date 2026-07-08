import '../models/schema.dart';

/// Chain A 분석 결과 묶음 — Document.status == done 이후 조회.
/// shared-schema 타입의 FE 편의 묶음일 뿐, 새 계약이 아니다(필드 추가 금지 규칙 준수).
class DocumentAnalysis {
  const DocumentAnalysis({
    required this.document,
    required this.extractedItem,
    required this.translated,
    required this.actionCard,
  });

  final Document document;
  final ExtractedItem extractedItem;
  final TranslatedContent translated;
  final ActionCard actionCard;
}

/// FE 데이터 접근 계약. 화면은 이 인터페이스만 안다.
/// 지금은 MockRepository, BE 연동 시 ApiRepository로 교체(화면 코드 무변경).
///
/// 라우팅 규칙(CLAUDE.md): 이미지 업로드 → Chain A(POST /documents),
/// 교사 메시지 → Chain B(POST /teacher-message). 별도 orchestrate 없음.
abstract interface class GaonRepository {
  /// 데모 시나리오 기준 '오늘' — mock은 2025-06-10 고정, 실서비스는 DateTime.now().
  /// D-day 계산은 반드시 이 값을 기준으로 한다.
  DateTime now();

  Future<User> getCurrentUser();

  Future<List<Child>> getChildren();

  /// 자녀 등록(F-ON-4) = POST /children 대응.
  /// 온보딩·설정에서 호출. name은 미성년 PII — 동의 시에만 전달(결정 #7-PII).
  Future<Child> addChild({
    required ChildGrade grade,
    String? name,
    String? classNo,
  });

  /// Chain A 시작(F-DOC-1). Document 생성 후 status가 비동기로 진행된다.
  Future<Document> uploadDocument({required String imageRef, String? childId});

  /// Chain A 진행 폴링(F-DOC-4). FE는 status로 분석 화면을 갱신한다.
  Future<Document> getDocument(String documentId);

  /// 분석 완료(done) 후 결과 일괄 조회(F-DOC-3·5·6·7·8).
  Future<DocumentAnalysis> getDocumentAnalysis(String documentId);

  /// 홈·캘린더·행동 카드용 — 가장 최근 완료된 분석 결과.
  /// BE에 대응 엔드포인트가 없음(§11) — ApiRepository는
  /// GET /documents(이력)에서 최신 done 문서를 찾아 GET /documents/{id}/result를
  /// 조합해 구현한다. 전용 엔드포인트 신설은 BE와 협의.
  Future<DocumentAnalysis> getLatestAnalysis();

  /// 캘린더 저장(F-DOC-7) = POST /calendar/events { document_id }.
  /// 분석 결과의 일정을 앱 내 캘린더에 확정 저장하고 생성된 이벤트를 반환.
  Future<List<CalendarEvent>> saveCalendarEvents({required String documentId});

  /// 캘린더 화면용 — 저장된 전체 일정.
  Future<List<CalendarEvent>> getCalendarEvents();

  /// Chain B(F-TCH). 생성까지만 — 전송은 사용자 수동(결정 #2).
  /// child_info는 §8 계약상 필수 — ApiRepository가 [childId]로 Child를 찾아
  /// { grade, class_no?, name? }을 구성해 POST /teacher-message에 실어 보낸다.
  Future<TeacherMessage> generateTeacherMessage({
    required MessageSituation situation,
    required String inputNative,
    required String childId,
  });

  /// 월간 리포트(F-LOG).
  Future<ActivityLog> getActivityLog();

  /// 능동 알림(F-PRO).
  Future<List<Notification>> getNotifications();
}
