import '../models/schema.dart';
import 'demo_data.dart';
import 'repository.dart';

/// BE 연동 전 데모용 구현.
/// - 네트워크 지연을 흉내 낸다(_latency).
/// - 업로드된 Document의 status는 경과 시간에 따라
///   uploaded → parsing → translating → action → done 으로 진행된다
///   (실서비스의 BackgroundTasks 체인 진행을 시뮬레이션).
class MockRepository implements GaonRepository {
  MockRepository({
    this.latency = const Duration(milliseconds: 250),
    DateTime Function()? wallClock, // 테스트에서 시간 제어용
  }) : _wallClock = wallClock ?? DateTime.now;

  final Duration latency;
  final DateTime Function() _wallClock;

  // 세션 내 업로드된 문서와 업로드 시각. 데모라 단일 사용자 가정.
  final Map<String, DateTime> _uploadedAtWall = {};
  int _docSeq = 0;

  Future<T> _delayed<T>(T value) =>
      Future.delayed(latency, () => value);

  @override
  DateTime now() => demoToday;

  @override
  Future<User> getCurrentUser() => _delayed(demoUser);

  // 온보딩에서 등록한 자녀. 등록 전에는 데모 자녀(이서준·이민아)를 보여준다.
  List<Child>? _registeredChildren;
  int _childSeq = 0;

  @override
  Future<List<Child>> getChildren() =>
      _delayed(_registeredChildren ?? demoChildren);

  @override
  Future<Child> addChild({
    required ChildGrade grade,
    String? name,
    String? classNo,
    String? schoolName,
    String? color,
  }) {
    final registered = _registeredChildren ??= [];
    final child = Child(
      childId: 'child-${++_childSeq}',
      userId: demoUser.userId,
      name: name,
      grade: grade,
      classNo: classNo,
      schoolName: schoolName,
      color: color ??
          childColorPalette[registered.length % childColorPalette.length],
      createdAt: demoToday,
    );
    registered.add(child);
    return _delayed(child);
  }

  @override
  Future<void> deleteChild(String childId) {
    (_registeredChildren ??= [...demoChildren])
        .removeWhere((c) => c.childId == childId);
    return _delayed(null);
  }

  @override
  Future<Document> uploadDocument({
    required String imageRef,
    String? childId,
  }) {
    final id = 'demo-doc-${++_docSeq}';
    _uploadedAtWall[id] = _wallClock();
    return _delayed(Document(
      documentId: id,
      userId: demoUser.userId,
      childId: childId ?? demoChild.childId,
      imageRef: imageRef,
      createdAt: demoToday,
    ));
  }

  @override
  Future<Document> getDocument(String documentId) {
    final uploadedAt = _uploadedAtWall[documentId];
    if (uploadedAt == null) {
      throw StateError('unknown document: $documentId');
    }
    final elapsed = _wallClock().difference(uploadedAt);
    return _delayed(Document(
      documentId: documentId,
      userId: demoUser.userId,
      childId: demoChild.childId,
      imageRef: 'demo://notice.jpg',
      status: _statusFor(elapsed),
      createdAt: demoToday,
    ));
  }

  /// 체인 진행 시뮬레이션 타임라인.
  DocStatus _statusFor(Duration elapsed) {
    if (elapsed < const Duration(milliseconds: 400)) return DocStatus.uploaded;
    if (elapsed < const Duration(milliseconds: 1400)) return DocStatus.parsing;
    if (elapsed < const Duration(milliseconds: 2400)) {
      return DocStatus.translating;
    }
    if (elapsed < const Duration(milliseconds: 3200)) return DocStatus.action;
    return DocStatus.done;
  }

  @override
  Future<DocumentAnalysis> getDocumentAnalysis(String documentId) async {
    final doc = await getDocument(documentId);
    return DocumentAnalysis(
      document: doc,
      extractedItem: demoExtractedItem,
      translated: demoTranslated,
      actionCard: demoActionCard,
    );
  }

  @override
  Future<DocumentAnalysis> getLatestAnalysis() => _delayed(DocumentAnalysis(
        document: Document(
          documentId: 'demo-doc-0',
          userId: demoUser.userId,
          childId: demoChild.childId,
          imageRef: 'demo://notice.jpg',
          status: DocStatus.done,
          createdAt: demoToday,
        ),
        extractedItem: demoExtractedItem,
        translated: demoTranslated,
        actionCard: demoActionCard,
      ));

  @override
  Future<List<CalendarEvent>> getCalendarEvents() =>
      _delayed(demoActionCard.calendarEvents);

  @override
  Future<List<CalendarEvent>> saveCalendarEvents(
      {required String documentId}) {
    // 데모: 최근 분석의 일정을 그대로 '저장됨'으로 반환.
    return _delayed(demoActionCard.calendarEvents);
  }

  @override
  Future<TeacherMessage> generateTeacherMessage({
    required MessageSituation situation,
    required String inputNative,
    required String childId,
  }) {
    // 실제 생성 지연을 흉내 — 데모에서 '생성 중' 상태가 보이도록 약간 길게.
    return Future.delayed(
      const Duration(milliseconds: 700),
      () => demoTeacherMessage(
        situation: situation,
        inputNative: inputNative,
      ),
    );
  }

  @override
  Future<ActivityLog> getActivityLog() => _delayed(demoActivityLog);

  @override
  Future<List<Notification>> getNotifications() =>
      _delayed(demoNotifications);
}
