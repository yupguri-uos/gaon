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

  /// Chain A 시작(F-DOC-1). Document 생성 후 status가 비동기로 진행된다.
  Future<Document> uploadDocument({required String imageRef, String? childId});

  /// Chain A 진행 폴링(F-DOC-4). FE는 status로 분석 화면을 갱신한다.
  Future<Document> getDocument(String documentId);

  /// 분석 완료(done) 후 결과 일괄 조회(F-DOC-3·5·6·7·8).
  Future<DocumentAnalysis> getDocumentAnalysis(String documentId);

  /// 홈·캘린더·행동 카드용 — 가장 최근 완료된 분석 결과.
  Future<DocumentAnalysis> getLatestAnalysis();

  /// 캘린더 화면용 — 저장된 전체 일정.
  Future<List<CalendarEvent>> getCalendarEvents();

  /// Chain B(F-TCH). 생성까지만 — 전송은 사용자 수동(결정 #2).
  Future<TeacherMessage> generateTeacherMessage({
    required MessageSituation situation,
    required String inputNative,
  });

  /// 월간 리포트(F-LOG).
  Future<ActivityLog> getActivityLog();

  /// 능동 알림(F-PRO).
  Future<List<Notification>> getNotifications();
}
