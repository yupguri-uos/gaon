import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;

import '../models/schema.dart';
import 'api_config.dart';
import 'auth_store.dart';
import 'picked_image_store.dart';
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
/// 인증: 전 엔드포인트 Bearer JWT(🔒). 토큰 출처 우선순위(AuthStore):
///   1) Kakao 로그인 플로우(/auth/kakao/login?client=app → gaon:// 딥링크)로
///      받은 access_token — AuthStore에 영속 저장
///   2) 개발 중엔 빌드 시 --dart-define=GAON_API_TOKEN=... (BE 발급 테스트 토큰)
/// 토큰 없이 🔒 호출 시 [AuthRequiredException].
class ApiRepository implements GaonRepository {
  ApiRepository({http.Client? client, String? baseUrl, String? token})
    : _client = client ?? http.Client(),
      _base = baseUrl ?? gaonApiBase,
      _tokenOverride = token;

  final http.Client _client;
  final String _base;

  // 테스트용 고정 토큰(생성자 주입). 실행 경로는 AuthStore가 단일 출처.
  final String? _tokenOverride;

  String get _token => _tokenOverride ?? AuthStore.token;

  // 업로드한 문서의 메타 캐시 — status 폴링 응답({status, step})에는
  // Document 전체가 없어서 여기서 합성한다.
  final Map<String, Document> _uploadedDocs = {};
  User? _cachedUser; // GET /me 응답 캐시 — updateProfile 시 갱신

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
      _decode(
        await _client.post(
          _uri(path),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: jsonEncode(body),
        ),
      );

  Future<dynamic> _patch(String path, Map<String, dynamic> body) async =>
      _decode(
        await _client.patch(
          _uri(path),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: jsonEncode(body),
        ),
      );

  /// 인증 불필요한 헬스체크 — 연동 상태 확인용.
  Future<bool> healthCheck() async {
    final res = await _client.get(_uri('/health'));
    return res.statusCode == 200;
  }

  // ── 사용자 / 온보딩 ──────────────────────────────────────────────
  /// GET /me — 온보딩 전이면 null(§11: UserProfile|null). 로그인 라우팅용.
  Future<User?> fetchMe() async {
    final json = await _get('/me');
    if (json == null) return null;
    return _cachedUser = User.fromJson(json as Map<String, dynamic>);
  }

  @override
  Future<User> getCurrentUser() async {
    final cached = _cachedUser;
    if (cached != null) return cached;
    final user = await fetchMe();
    if (user == null) {
      // 설정·프로필 화면은 온보딩 이후에만 진입 — 여기 오면 상태 이상
      throw StateError('온보딩이 완료되지 않았습니다 — 프로필을 먼저 등록하세요');
    }
    return user;
  }

  @override
  Future<User> updateProfile({
    String? displayName,
    OriginCountry? originCountry,
    NativeLanguage? nativeLanguage,
  }) async {
    // PATCH /profile — 보낸 필드만 갱신(F-ON-1). null은 '변경 없음'으로 제외(?: 표기).
    final json =
        await _patch('/profile', {
              'display_name': ?displayName,
              'origin_country': ?originCountry?.wire,
              'native_language': ?nativeLanguage?.wire,
            })
            as Map<String, dynamic>;
    return _cachedUser = User.fromJson(json);
  }

  @override
  Future<void> logout() async {
    // POST /auth/logout — stateless JWT라 서버 상태 없음(§12). 네트워크 실패해도
    // 로컬 토큰 폐기는 반드시 수행(로그아웃이 오프라인에서도 되도록).
    try {
      await _post('/auth/logout', const {});
    } catch (_) {}
    _cachedUser = null;
    await AuthStore.clear();
  }

  @override
  Future<void> deleteAccount() async {
    // DELETE /auth/me — 서버가 users 삭제 → 연관 데이터 CASCADE. logout과 달리
    // 삭제가 성공해야 토큰을 폐기한다(실패 시 계정이 남았는데 세션만 끊기는 것 방지).
    _decode(await _client.delete(_uri('/auth/me'), headers: _authHeaders));
    _cachedUser = null;
    await AuthStore.clear();
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
    final json =
        await _post('/onboarding', {
              'origin_country': originCountry.wire,
              'native_language': nativeLanguage.wire,
              'child_grade': childGrade.wire,
              'child_name': childName,
              'child_class_no': childClassNo,
              'child_school_name': childSchoolName,
              // 이름·반을 보낼 때만 PII 동의 플래그(결정 #7-PII)
              'consent_child_pii': childName != null || childClassNo != null,
            })
            as Map<String, dynamic>;
    final user = User.fromJson(json['user'] as Map<String, dynamic>);
    _cachedUser = user;
    var child = Child.fromJson(json['child'] as Map<String, dynamic>);
    // /onboarding 요청엔 color 필드가 없어 첫 자녀 색을 PATCH로 배정(§17.4)
    if (child.color == null) {
      try {
        final patched = await _client.patch(
          _uri('/children/${child.childId}'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: jsonEncode({'color': childColorPalette.first}),
        );
        child = Child.fromJson(_decode(patched) as Map<String, dynamic>);
      } catch (_) {
        // 색 배정 실패는 치명적이지 않음 — 기본색으로 표시됨
      }
    }
    return (user, child);
  }

  // ── 자녀 (F-ON-4) ────────────────────────────────────────────────
  @override
  Future<List<Child>> getChildren() async {
    final json = await _get('/children') as List;
    return [for (final e in json) Child.fromJson(e as Map<String, dynamic>)];
  }

  @override
  Future<Child> addChild({
    required ChildGrade grade,
    String? name,
    String? classNo,
    String? schoolName,
    String? color,
  }) async {
    // 캘린더 색 구분(§17.4): 미지정이면 현재 자녀 수 기준 팔레트 순환 배정
    final assigned =
        color ??
        childColorPalette[(await getChildren()).length %
            childColorPalette.length];
    final json =
        await _post('/children', {
              'grade': grade.wire,
              'name': name,
              'class_no': classNo,
              'school_name': schoolName,
              'color': assigned,
              'consent_child_pii': name != null || classNo != null,
            })
            as Map<String, dynamic>;
    return Child.fromJson(json);
  }

  @override
  Future<Child> updateChild({
    required String childId,
    ChildGrade? grade,
    String? name,
    String? classNo,
    String? schoolName,
    String? color,
  }) async {
    // PATCH /children/{id} — 보낸 필드만 갱신(F-ON-4), null은 제외(?: 표기).
    // 이름·반을 보낼 때만 PII 동의 플래그(결정 #7-PII).
    final json =
        await _patch('/children/$childId', {
              'grade': ?grade?.wire,
              'name': ?name,
              'class_no': ?classNo,
              'school_name': ?schoolName,
              'color': ?color,
              if (name != null || classNo != null) 'consent_child_pii': true,
            })
            as Map<String, dynamic>;
    return Child.fromJson(json);
  }

  @override
  Future<void> deleteChild(String childId) async {
    _decode(
      await _client.delete(_uri('/children/$childId'), headers: _authHeaders),
    );
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

    // picked:// = 사용자가 고른 사진(F-DOC-1, 카메라·갤러리) — 메모리 스토어에서 소비.
    // demo://   = 번들 데모 알림장.  그 외 = 파일 경로(모바일 전용).
    if (PickedImageStore.isPickedRef(imageRef)) {
      final bytes = PickedImageStore.take(imageRef);
      if (bytes == null) {
        throw StateError('선택한 사진을 찾을 수 없습니다: $imageRef');
      }
      // 갤러리 스크린샷은 PNG가 흔한데 jpeg로 고정 신고하면 실제 바이트와 어긋난다
      // — 매직 바이트로 판별해 보낸다(BE도 매직 바이트로 재판별하는 이중 방어).
      final type = _sniffImageType(bytes);
      request.files.add(
        http.MultipartFile.fromBytes(
          'image',
          bytes,
          filename: 'notice.${type.subtype}',
          contentType: type,
        ),
      );
    } else if (imageRef.startsWith('demo://')) {
      final bytes = await rootBundle.load('assets/images/demo_notice.jpg');
      request.files.add(
        http.MultipartFile.fromBytes(
          'image',
          bytes.buffer.asUint8List(),
          filename: 'notice.jpg',
          contentType: MediaType('image', 'jpeg'),
        ),
      );
    } else {
      request.files.add(
        await http.MultipartFile.fromPath(
          'image',
          imageRef,
          contentType: MediaType('image', 'jpeg'),
        ),
      );
    }

    final streamed = await _client.send(request);
    final json =
        _decode(await http.Response.fromStream(streamed))
            as Map<String, dynamic>;

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

  /// 이미지 바이트의 매직 바이트로 MIME 판별(PNG·WebP, 그 외 JPEG 간주).
  static MediaType _sniffImageType(List<int> bytes) {
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return MediaType('image', 'png');
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return MediaType('image', 'webp');
    }
    return MediaType('image', 'jpeg');
  }

  @override
  Future<Document> getDocument(String documentId) async {
    final json =
        await _get('/documents/$documentId/status') as Map<String, dynamic>;
    // 분석 실패 원인(failed 시 BE가 기록) — 콘솔 트래킹용(F-DOC-4). UI는 status로 처리.
    final error = json['error'];
    if (error is String && error.isNotEmpty) {
      debugPrint('GAON Chain A 실패(document=$documentId): $error');
    }
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
      extractedItem: ExtractedItem.fromJson(extracted as Map<String, dynamic>),
      translated: TranslatedContent.fromJson(
        translated as Map<String, dynamic>,
      ),
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
  Future<List<CalendarEvent>> saveCalendarEvents({
    required String documentId,
    List<CalendarEvent>? selected,
  }) async {
    final json =
        await _post('/calendar/events', {
              'document_id': documentId,
              // 선택 저장(QA D-3) — (title, date) 키만 보낸다. 미전달 = 전체 저장.
              if (selected != null)
                'selected': [
                  for (final e in selected)
                    {
                      'title': e.title,
                      'date':
                          '${e.date.year.toString().padLeft(4, '0')}-'
                          '${e.date.month.toString().padLeft(2, '0')}-'
                          '${e.date.day.toString().padLeft(2, '0')}',
                    },
                ],
            })
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
  Future<List<CalendarEvent>> getCalendarEvents() async =>
      [for (final v in await getCalendarEventViews()) v.event];

  @override
  Future<List<CalendarEventView>> getCalendarEventViews() async {
    final json = await _get('/calendar/events') as Map<String, dynamic>;
    return [
      for (final e in json['events'] as List)
        CalendarEventView(
          event: CalendarEvent(
            title: (e as Map<String, dynamic>)['title'] as String,
            date: DateTime.parse(e['date'] as String),
            type: CalendarEventType.fromWire(e['type'] as String),
            childId: e['child_id'] as String?,
          ),
          // 출처 문서 제목(QA D-5) — 엔드포인트 로컬 필드, shared 미러엔 없음
          sourceTitle: e['source_title'] as String?,
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
    final json =
        await _post('/teacher-message', {
              'child_id': childId,
              'situation': situation.wire,
              'input_native': inputNative,
            })
            as Map<String, dynamic>;
    return TeacherMessage.fromJson(json);
  }

  // ── 리포트 (F-LOG) ───────────────────────────────────────────────
  @override
  Future<ActivityLog> getActivityLog() async {
    final json = await _get('/report/monthly') as Map<String, dynamic>;
    return ActivityLog.fromJson(json);
  }

  // 알림(F-PRO) 소비부 제거(결정 #11) — BE GET /notifications는 코드 잔존.
}
