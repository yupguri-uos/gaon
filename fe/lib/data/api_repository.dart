import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;

import '../models/schema.dart';
import 'api_config.dart';
import 'repository.dart';

/// 인증 토큰이 없거나 만료됨 — Kakao 로그인(F-ON-3)으로 재발급 필요.
class AuthRequiredException implements Exception {
  @override
  String toString() => '인증이 필요합니다 (Kakao 로그인 후 토큰 주입)';
}

class ApiException implements Exception {
  ApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => 'API $statusCode: $message';
}

/// 실 BE 연동 구현 (§11 엔드포인트 1:1) — https://gaon.uk/api.
///
/// 인증: 전 엔드포인트 Bearer JWT(🔒). 토큰 출처 우선순위:
///   1) Kakao 로그인 플로우(/auth/kakao/callback)의 access_token → [token]에 주입
///   2) 개발 중엔 빌드 시 --dart-define=GAON_API_TOKEN=... (BE 발급 테스트 토큰)
/// 토큰 없이 🔒 호출 시 [AuthRequiredException].
///
/// 알려진 BE 갭(2026-07-10 대조):
///   - GET /me 미구현(§11에는 있음) → getCurrentUser는 온보딩 응답 캐시로 대체,
///     캐시 없으면 AuthRequired 취급. BE 구현되면 _fetchMe로 교체.
///   - GET /notifications 미구현(P2) → 빈 리스트 반환.
class ApiRepository implements GaonRepository {
  ApiRepository({http.Client? client, String? baseUrl, String? token})
      : _client = client ?? http.Client(),
        _base = baseUrl ?? gaonApiBase,
        _token = token ??
            const String.fromEnvironment('GAON_API_TOKEN', defaultValue: '');

  final http.Client _client;
  final String _base;
  String _token;

  /// Kakao 로그인 후 세션 토큰 주입 지점.
  set token(String value) => _token = value;

  // 업로드한 문서의 메타 캐시 — status 폴링 응답({status, step})에는
  // Document 전체가 없어서 여기서 합성한다.
  final Map<String, Document> _uploadedDocs = {};
  User? _cachedUser; // 온보딩 응답 캐시 (BE에 GET /me가 생기면 제거)

  @override
  DateTime now() => DateTime.now();

  // ── HTTP 헬퍼 ────────────────────────────────────────────────────
  Map<String, String> get _authHeaders {
    if (_token.isEmpty) throw AuthRequiredException();
    return {'Authorization': 'Bearer $_token'};
  }

  Uri _uri(String path) => Uri.parse('$_base$path');

  dynamic _decode(http.Response res) {
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw AuthRequiredException();
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException(res.statusCode, utf8.decode(res.bodyBytes));
    }
    if (res.bodyBytes.isEmpty) return null;
    return jsonDecode(utf8.decode(res.bodyBytes));
  }

  Future<dynamic> _get(String path) async =>
      _decode(await _client.get(_uri(path), headers: _authHeaders));

  Future<dynamic> _post(String path, Map<String, dynamic> body) async =>
      _decode(await _client.post(
        _uri(path),
        headers: {..._authHeaders, 'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ));

  /// 인증 불필요한 헬스체크 — 연동 상태 확인용.
  Future<bool> healthCheck() async {
    final res = await _client.get(_uri('/health'));
    return res.statusCode == 200;
  }

  // ── 사용자 / 온보딩 ──────────────────────────────────────────────
  @override
  Future<User> getCurrentUser() async {
    // BE 갭: GET /me 미구현(§11) — 온보딩 캐시로 대체.
    final cached = _cachedUser;
    if (cached != null) return cached;
    throw AuthRequiredException();
  }

  /// POST /onboarding — 프로필 + 첫 자녀 생성(F-ON-1).
  /// GaonRepository 인터페이스 밖의 연동 전용 메서드(로그인 플로우에서 호출).
  Future<(User, Child)> submitOnboarding({
    required OriginCountry originCountry,
    required NativeLanguage nativeLanguage,
    required ChildGrade childGrade,
    String? childName,
    String? childClassNo,
    String? childSchoolName,
  }) async {
    final json = await _post('/onboarding', {
      'origin_country': originCountry.wire,
      'native_language': nativeLanguage.wire,
      'child_grade': childGrade.wire,
      'child_name': childName,
      'child_class_no': childClassNo,
      'child_school_name': childSchoolName,
      // 이름·반을 보낼 때만 PII 동의 플래그(결정 #7-PII)
      'consent_child_pii': childName != null || childClassNo != null,
    }) as Map<String, dynamic>;
    final user = User.fromJson(json['user'] as Map<String, dynamic>);
    _cachedUser = user;
    return (user, Child.fromJson(json['child'] as Map<String, dynamic>));
  }

  // ── 자녀 (F-ON-4) ────────────────────────────────────────────────
  @override
  Future<List<Child>> getChildren() async {
    final json = await _get('/children') as List;
    return [
      for (final e in json) Child.fromJson(e as Map<String, dynamic>),
    ];
  }

  @override
  Future<Child> addChild({
    required ChildGrade grade,
    String? name,
    String? classNo,
    String? schoolName,
  }) async {
    final json = await _post('/children', {
      'grade': grade.wire,
      'name': name,
      'class_no': classNo,
      'school_name': schoolName,
      'consent_child_pii': name != null || classNo != null,
    }) as Map<String, dynamic>;
    return Child.fromJson(json);
  }

  // ── Chain A (F-DOC) ──────────────────────────────────────────────
  @override
  Future<Document> uploadDocument({
    required String imageRef,
    String? childId,
  }) async {
    final request = http.MultipartRequest('POST', _uri('/documents'))
      ..headers.addAll(_authHeaders);
    if (childId != null) request.fields['child_id'] = childId;

    // BE가 content_type 검사(image/*)를 하므로 명시.
    // 데모 경로면 번들 알림장 사진 사용, 아니면 파일 경로로 취급.
    if (imageRef.startsWith('demo://')) {
      final bytes = await rootBundle.load('assets/images/demo_notice.jpg');
      request.files.add(http.MultipartFile.fromBytes(
        'image',
        bytes.buffer.asUint8List(),
        filename: 'notice.jpg',
        contentType: MediaType('image', 'jpeg'),
      ));
    } else {
      request.files.add(await http.MultipartFile.fromPath(
        'image',
        imageRef,
        contentType: MediaType('image', 'jpeg'),
      ));
    }

    final streamed = await _client.send(request);
    final json =
        _decode(await http.Response.fromStream(streamed)) as Map<String, dynamic>;

    final document = Document(
      documentId: json['document_id'] as String,
      userId: _cachedUser?.userId ?? '',
      childId: childId,
      imageRef: imageRef,
      status: DocStatus.fromWire(json['status'] as String),
      createdAt: DateTime.now(),
    );
    _uploadedDocs[document.documentId] = document;
    return document;
  }

  @override
  Future<Document> getDocument(String documentId) async {
    final json =
        await _get('/documents/$documentId/status') as Map<String, dynamic>;
    final base = _uploadedDocs[documentId];
    return Document(
      documentId: documentId,
      userId: base?.userId ?? '',
      childId: base?.childId,
      imageRef: base?.imageRef ?? '',
      status: DocStatus.fromWire(json['status'] as String),
      createdAt: base?.createdAt ?? DateTime.now(),
    );
  }

  @override
  Future<DocumentAnalysis> getDocumentAnalysis(String documentId) async {
    final json =
        await _get('/documents/$documentId/result') as Map<String, dynamic>;
    final extracted = json['extracted'];
    final translated = json['translated'];
    final actionCard = json['action_card'];
    if (extracted == null || translated == null || actionCard == null) {
      // done 전에 호출되면 결과가 비어있을 수 있음(§18.4 레이스는 수정됐지만 방어)
      throw StateError('분석 결과가 아직 준비되지 않았습니다: $documentId');
    }
    return DocumentAnalysis(
      document: Document.fromJson(json['document'] as Map<String, dynamic>),
      extractedItem:
          ExtractedItem.fromJson(extracted as Map<String, dynamic>),
      translated:
          TranslatedContent.fromJson(translated as Map<String, dynamic>),
      actionCard: ActionCard.fromJson(actionCard as Map<String, dynamic>),
    );
  }

  @override
  Future<DocumentAnalysis> getLatestAnalysis() async {
    // 전용 엔드포인트 없음(§11) — 이력에서 최신 done 문서를 찾아 결과 조회.
    final json = await _get('/documents') as List;
    for (final e in json) {
      final doc = Document.fromJson(e as Map<String, dynamic>);
      if (doc.status == DocStatus.done) {
        return getDocumentAnalysis(doc.documentId);
      }
    }
    throw StateError('완료된 분석이 없습니다 — 알림장을 먼저 업로드하세요');
  }

  // ── 캘린더 (F-DOC-7) ─────────────────────────────────────────────
  @override
  Future<List<CalendarEvent>> saveCalendarEvents(
      {required String documentId}) async {
    final json = await _post('/calendar/events', {'document_id': documentId})
        as Map<String, dynamic>;
    return [
      for (final e in json['created'] as List)
        CalendarEvent(
          title: (e as Map<String, dynamic>)['title'] as String,
          date: DateTime.parse(e['date'] as String),
          type: CalendarEventType.fromWire(e['type'] as String),
        ),
    ];
  }

  @override
  Future<List<CalendarEvent>> getCalendarEvents() async {
    final json = await _get('/calendar/events') as Map<String, dynamic>;
    return [
      for (final e in json['events'] as List)
        CalendarEvent(
          title: (e as Map<String, dynamic>)['title'] as String,
          date: DateTime.parse(e['date'] as String),
          type: CalendarEventType.fromWire(e['type'] as String),
          childId: e['child_id'] as String?,
        ),
    ];
  }

  // ── Chain B (F-TCH) ──────────────────────────────────────────────
  @override
  Future<TeacherMessage> generateTeacherMessage({
    required MessageSituation situation,
    required String inputNative,
    required String childId,
  }) async {
    final json = await _post('/teacher-message', {
      'child_id': childId,
      'situation': situation.wire,
      'input_native': inputNative,
    }) as Map<String, dynamic>;
    return TeacherMessage.fromJson(json);
  }

  // ── 리포트 (F-LOG) ───────────────────────────────────────────────
  @override
  Future<ActivityLog> getActivityLog() async {
    final json = await _get('/report/monthly') as Map<String, dynamic>;
    return ActivityLog.fromJson(json);
  }

  // ── 알림 (F-PRO) ─────────────────────────────────────────────────
  @override
  Future<List<Notification>> getNotifications() async {
    // BE 미구현(P2, §18.3) — 라우터 생기면 GET /notifications로 교체.
    return const [];
  }
}
