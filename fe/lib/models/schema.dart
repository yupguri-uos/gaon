/// GAON shared-schema v0.1 — Dart 미러 (정본: shared/python/gaon_shared/schema.py)
///
/// 규칙(CLAUDE.md): 필드 임의 추가 금지. 변경은 SSOT → schema.py → 이 파일 순.
/// schema.py의 §A~F + ChildInfo만 이식한다 — 에이전트 I/O(*Input, AgentResponse)는
/// BE↔AI 내부 계약(§8·§11)이라 FE에서 쓰지 않는다.
///
/// JSON 필드명은 Pydantic과 동일한 snake_case, 값 타입(Literal)의 wire 값도 동일.
/// date(날짜만)는 'yyyy-MM-dd', datetime은 ISO 8601로 직렬화한다.
library;

// ──────────────────────────────────────────────────────────────────────────
// A. 값 타입 — MVP 고정값. wire = schema.py Literal 문자열.
// ──────────────────────────────────────────────────────────────────────────

enum OriginCountry {
  vn('VN'),
  cn('CN');

  const OriginCountry(this.wire);
  final String wire;
  static OriginCountry fromWire(String v) =>
      values.firstWhere((e) => e.wire == v);
}

enum NativeLanguage {
  vi('vi'),
  zh('zh');

  const NativeLanguage(this.wire);
  final String wire;
  static NativeLanguage fromWire(String v) =>
      values.firstWhere((e) => e.wire == v);
}

enum ChildGrade {
  elem1('elem_1'),
  elem2('elem_2'),
  elem3('elem_3'),
  elem4('elem_4'),
  elem5('elem_5'),
  elem6('elem_6'); // 초1~6, 팀 결정 — 중고등은 범위 밖 (마이그레이션 0009)

  const ChildGrade(this.wire);
  final String wire;
  static ChildGrade fromWire(String v) =>
      values.firstWhere((e) => e.wire == v);
}

enum DocStatus {
  uploaded('uploaded'),
  parsing('parsing'),
  translating('translating'),
  action('action'),
  done('done'),
  failed('failed');

  const DocStatus(this.wire);
  final String wire;
  static DocStatus fromWire(String v) =>
      values.firstWhere((e) => e.wire == v);
}

enum DocType {
  notice('notice'), // 알림장
  consent('consent'), // 동의서
  survey('survey'); // 설문·회신

  const DocType(this.wire);
  final String wire;
  static DocType fromWire(String v) => values.firstWhere((e) => e.wire == v);
}

enum CalendarEventType {
  deadline('deadline'),
  event('event');

  const CalendarEventType(this.wire);
  final String wire;
  static CalendarEventType fromWire(String v) =>
      values.firstWhere((e) => e.wire == v);
}

enum MessageSituation {
  absence('absence'),
  sickNote('sick_note'),
  consultation('consultation'),
  custom('custom');

  const MessageSituation(this.wire);
  final String wire;
  static MessageSituation fromWire(String v) =>
      values.firstWhere((e) => e.wire == v);
}

enum NotificationType {
  deadlineD2('deadline_d2'),
  unrepliedConsent('unreplied_consent'),
  eventPreview('event_preview');

  const NotificationType(this.wire);
  final String wire;
  static NotificationType fromWire(String v) =>
      values.firstWhere((e) => e.wire == v);
}

// date(날짜만) 직렬화 헬퍼 — Pydantic date와 호환('yyyy-MM-dd').
String _dateToJson(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

// ──────────────────────────────────────────────────────────────────────────
// B. 사용자 / Memory
// ──────────────────────────────────────────────────────────────────────────

/// 보호자(F-ON-1·F-ON-3).
class User {
  const User({
    required this.userId,
    this.displayName,
    required this.originCountry,
    required this.nativeLanguage,
    required this.createdAt,
  });

  final String userId;
  final String? displayName;
  final OriginCountry originCountry;
  final NativeLanguage nativeLanguage;
  final DateTime createdAt;

  factory User.fromJson(Map<String, dynamic> json) => User(
        userId: json['user_id'] as String,
        displayName: json['display_name'] as String?,
        originCountry: OriginCountry.fromWire(json['origin_country'] as String),
        nativeLanguage:
            NativeLanguage.fromWire(json['native_language'] as String),
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'display_name': displayName,
        'origin_country': originCountry.wire,
        'native_language': nativeLanguage.wire,
        'created_at': createdAt.toIso8601String(),
      };
}

/// 자녀(F-ON-4). name·classNo는 미성년 PII → 동의 시에만 저장(결정 #7-PII).
class Child {
  const Child({
    required this.childId,
    required this.userId,
    this.name,
    required this.grade,
    this.classNo,
    this.schoolName,
    this.color,
    required this.createdAt,
  });

  final String childId;
  final String userId;
  final String? name;
  final ChildGrade grade;
  final String? classNo;
  final String? schoolName; // 학교명(PII 아님 — 동의 불필요, 마이그레이션 0007)
  final String? color;
  final DateTime createdAt;

  factory Child.fromJson(Map<String, dynamic> json) => Child(
        childId: json['child_id'] as String,
        userId: json['user_id'] as String,
        name: json['name'] as String?,
        grade: ChildGrade.fromWire(json['grade'] as String),
        classNo: json['class_no'] as String?,
        schoolName: json['school_name'] as String?,
        color: json['color'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'child_id': childId,
        'user_id': userId,
        'name': name,
        'grade': grade.wire,
        'class_no': classNo,
        'school_name': schoolName,
        'color': color,
        'created_at': createdAt.toIso8601String(),
      };
}

// ──────────────────────────────────────────────────────────────────────────
// C. 문서 처리 단위 & 파싱 결과 (Chain A)
// ──────────────────────────────────────────────────────────────────────────

/// Chain A 처리 단위(F-DOC). FE는 status를 폴링해 분석 화면을 갱신한다.
class Document {
  const Document({
    required this.documentId,
    required this.userId,
    this.childId,
    required this.imageRef,
    this.status = DocStatus.uploaded,
    required this.createdAt,
  });

  final String documentId;
  final String userId;
  final String? childId;
  final String imageRef;
  final DocStatus status;
  final DateTime createdAt;

  factory Document.fromJson(Map<String, dynamic> json) => Document(
        documentId: json['document_id'] as String,
        userId: json['user_id'] as String,
        childId: json['child_id'] as String?,
        imageRef: json['image_ref'] as String,
        status: DocStatus.fromWire(json['status'] as String? ?? 'uploaded'),
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'document_id': documentId,
        'user_id': userId,
        'child_id': childId,
        'image_ref': imageRef,
        'status': status.wire,
        'created_at': createdAt.toIso8601String(),
      };
}

class DateItem {
  const DateItem({required this.label, required this.date});

  final String label;
  final DateTime date;

  factory DateItem.fromJson(Map<String, dynamic> json) => DateItem(
        label: json['label'] as String,
        date: DateTime.parse(json['date'] as String),
      );

  Map<String, dynamic> toJson() =>
      {'label': label, 'date': _dateToJson(date)};
}

class AmountItem {
  const AmountItem({required this.label, required this.value});

  final String label;
  final double value;

  factory AmountItem.fromJson(Map<String, dynamic> json) => AmountItem(
        label: json['label'] as String,
        value: (json['value'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() => {'label': label, 'value': value};
}

class Checkbox {
  const Checkbox({required this.label, this.bbox});

  final String label;
  final List<double>? bbox; // 픽셀 좌표 — MVP 선택(§10)

  factory Checkbox.fromJson(Map<String, dynamic> json) => Checkbox(
        label: json['label'] as String,
        bbox: (json['bbox'] as List?)
            ?.map((e) => (e as num).toDouble())
            .toList(),
      );

  Map<String, dynamic> toJson() => {'label': label, 'bbox': bbox};
}

/// Document Parsing Agent 출력(F-DOC-3).
class ExtractedItem {
  const ExtractedItem({
    required this.docType,
    required this.title,
    this.dates = const [],
    this.amounts = const [],
    this.supplies = const [],
    this.deadline,
    this.requiresReply = false,
    this.checkboxes = const [],
    required this.rawText,
  });

  final DocType docType;
  final String title;
  final List<DateItem> dates;
  final List<AmountItem> amounts;
  final List<String> supplies; // 준비물 원문(한국어)
  final DateTime? deadline;
  final bool requiresReply;
  final List<Checkbox> checkboxes;
  final String rawText;

  factory ExtractedItem.fromJson(Map<String, dynamic> json) => ExtractedItem(
        docType: DocType.fromWire(json['doc_type'] as String),
        title: json['title'] as String,
        dates: (json['dates'] as List? ?? [])
            .map((e) => DateItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        amounts: (json['amounts'] as List? ?? [])
            .map((e) => AmountItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        supplies:
            (json['supplies'] as List? ?? []).map((e) => e as String).toList(),
        deadline: json['deadline'] == null
            ? null
            : DateTime.parse(json['deadline'] as String),
        requiresReply: json['requires_reply'] as bool? ?? false,
        checkboxes: (json['checkboxes'] as List? ?? [])
            .map((e) => Checkbox.fromJson(e as Map<String, dynamic>))
            .toList(),
        rawText: json['raw_text'] as String,
      );

  Map<String, dynamic> toJson() => {
        'doc_type': docType.wire,
        'title': title,
        'dates': dates.map((e) => e.toJson()).toList(),
        'amounts': amounts.map((e) => e.toJson()).toList(),
        'supplies': supplies,
        'deadline': deadline == null ? null : _dateToJson(deadline!),
        'requires_reply': requiresReply,
        'checkboxes': checkboxes.map((e) => e.toJson()).toList(),
        'raw_text': rawText,
      };
}

// ──────────────────────────────────────────────────────────────────────────
// D. 번역 · 행동 카드 (Chain A)
// ──────────────────────────────────────────────────────────────────────────

class Term {
  const Term({
    required this.termKo,
    required this.literalNative,
    required this.explanationNative,
  });

  final String termKo;
  final String literalNative; // 직역(모국어)
  final String explanationNative; // 문화맥락 해설(모국어)

  factory Term.fromJson(Map<String, dynamic> json) => Term(
        termKo: json['term_ko'] as String,
        literalNative: json['literal_native'] as String,
        explanationNative: json['explanation_native'] as String,
      );

  Map<String, dynamic> toJson() => {
        'term_ko': termKo,
        'literal_native': literalNative,
        'explanation_native': explanationNative,
      };
}

/// Cultural & Contextual Translation Agent 출력(F-DOC-5).
class TranslatedContent {
  const TranslatedContent({required this.summaryNative, this.terms = const []});

  final String summaryNative; // 전체 요약(모국어)
  final List<Term> terms;

  factory TranslatedContent.fromJson(Map<String, dynamic> json) =>
      TranslatedContent(
        summaryNative: json['summary_native'] as String,
        terms: (json['terms'] as List? ?? [])
            .map((e) => Term.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'summary_native': summaryNative,
        'terms': terms.map((e) => e.toJson()).toList(),
      };
}

class Supply {
  const Supply({
    required this.nameKo,
    required this.nameNative,
    required this.explanationNative,
    this.spec,
    this.ecommerceKeyword,
    this.ecommerceDeeplink,
  });

  final String nameKo;
  final String nameNative;
  final String explanationNative;
  final String? spec; // 규격(예: 175mm)

  /// 쿠팡 검색용 한국어 키워드 — 구매가 합리적인 실물에만 옴.
  /// null = 비구매 항목(예: 교과서). 이때 deeplink도 null(§17.11, 2026-07-10).
  final String? ecommerceKeyword;
  final String? ecommerceDeeplink; // 쿠팡 검색 URL (자동결제 X)

  factory Supply.fromJson(Map<String, dynamic> json) => Supply(
        nameKo: json['name_ko'] as String,
        nameNative: json['name_native'] as String,
        explanationNative: json['explanation_native'] as String,
        spec: json['spec'] as String?,
        ecommerceKeyword: json['ecommerce_keyword'] as String?,
        ecommerceDeeplink: json['ecommerce_deeplink'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'name_ko': nameKo,
        'name_native': nameNative,
        'explanation_native': explanationNative,
        'spec': spec,
        'ecommerce_keyword': ecommerceKeyword,
        'ecommerce_deeplink': ecommerceDeeplink,
      };
}

class CalendarEvent {
  const CalendarEvent({
    required this.title,
    required this.date,
    required this.type,
    this.childId,
  });

  final String title;
  final DateTime date;
  final CalendarEventType type;
  final String? childId;

  factory CalendarEvent.fromJson(Map<String, dynamic> json) => CalendarEvent(
        title: json['title'] as String,
        date: DateTime.parse(json['date'] as String),
        type: CalendarEventType.fromWire(json['type'] as String),
        childId: json['child_id'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'title': title,
        'date': _dateToJson(date),
        'type': type.wire,
        'child_id': childId,
      };
}

/// Lifestyle Action Agent 출력(F-DOC-6/7/8).
class ActionCard {
  const ActionCard({
    this.supplies = const [],
    this.calendarEvents = const [],
    this.replyDraftKo,
  });

  final List<Supply> supplies;
  final List<CalendarEvent> calendarEvents;
  final String? replyDraftKo; // requiresReply=true일 때만(F-DOC-8)

  factory ActionCard.fromJson(Map<String, dynamic> json) => ActionCard(
        supplies: (json['supplies'] as List? ?? [])
            .map((e) => Supply.fromJson(e as Map<String, dynamic>))
            .toList(),
        calendarEvents: (json['calendar_events'] as List? ?? [])
            .map((e) => CalendarEvent.fromJson(e as Map<String, dynamic>))
            .toList(),
        replyDraftKo: json['reply_draft_ko'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'supplies': supplies.map((e) => e.toJson()).toList(),
        'calendar_events': calendarEvents.map((e) => e.toJson()).toList(),
        'reply_draft_ko': replyDraftKo,
      };
}

// ──────────────────────────────────────────────────────────────────────────
// E. 교사 소통 (Chain B)
// ──────────────────────────────────────────────────────────────────────────

/// Teacher Communication Agent 출력(F-TCH). 전송은 사용자 수동(결정 #2).
class TeacherMessage {
  const TeacherMessage({
    required this.situation,
    required this.inputNative,
    required this.outputKo,
    required this.adminGuideNative,
  });

  final MessageSituation situation;
  final String inputNative;
  final String outputKo; // 경어체 한국어
  final String adminGuideNative; // 행정 절차 안내(모국어)

  factory TeacherMessage.fromJson(Map<String, dynamic> json) => TeacherMessage(
        situation: MessageSituation.fromWire(json['situation'] as String),
        inputNative: json['input_native'] as String,
        outputKo: json['output_ko'] as String,
        adminGuideNative: json['admin_guide_native'] as String,
      );

  Map<String, dynamic> toJson() => {
        'situation': situation.wire,
        'input_native': inputNative,
        'output_ko': outputKo,
        'admin_guide_native': adminGuideNative,
      };
}

/// §17.4: Chain B 요청에 실어 보내는 자녀 정보. name은 동의 시에만.
class ChildInfo {
  const ChildInfo({required this.grade, this.classNo, this.name});

  final ChildGrade grade;
  final String? classNo;
  final String? name;

  factory ChildInfo.fromJson(Map<String, dynamic> json) => ChildInfo(
        grade: ChildGrade.fromWire(json['grade'] as String),
        classNo: json['class_no'] as String?,
        name: json['name'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'grade': grade.wire,
        'class_no': classNo,
        'name': name,
      };
}

// ──────────────────────────────────────────────────────────────────────────
// F. 능동 알림 / 활동 로그
// ──────────────────────────────────────────────────────────────────────────

/// Proactive(F-PRO).
class Notification {
  const Notification({
    required this.notificationId,
    required this.userId,
    this.childId,
    required this.type,
    required this.titleNative,
    required this.bodyNative,
    required this.scheduledAt,
    this.relatedDocumentId,
  });

  final String notificationId;
  final String userId;
  final String? childId;
  final NotificationType type;
  final String titleNative;
  final String bodyNative;
  final DateTime scheduledAt;
  final String? relatedDocumentId;

  factory Notification.fromJson(Map<String, dynamic> json) => Notification(
        notificationId: json['notification_id'] as String,
        userId: json['user_id'] as String,
        childId: json['child_id'] as String?,
        type: NotificationType.fromWire(json['type'] as String),
        titleNative: json['title_native'] as String,
        bodyNative: json['body_native'] as String,
        scheduledAt: DateTime.parse(json['scheduled_at'] as String),
        relatedDocumentId: json['related_document_id'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'notification_id': notificationId,
        'user_id': userId,
        'child_id': childId,
        'type': type.wire,
        'title_native': titleNative,
        'body_native': bodyNative,
        'scheduled_at': scheduledAt.toIso8601String(),
        'related_document_id': relatedDocumentId,
      };
}

class WeeklyActivity {
  const WeeklyActivity({
    required this.weekStart,
    required this.weekEnd,
    this.processedCount = 0,
    this.eventParticipationCount = 0,
    this.missedCount = 0,
  });

  final DateTime weekStart;
  final DateTime weekEnd;
  final int processedCount;
  final int eventParticipationCount;
  final int missedCount;

  factory WeeklyActivity.fromJson(Map<String, dynamic> json) => WeeklyActivity(
        weekStart: DateTime.parse(json['week_start'] as String),
        weekEnd: DateTime.parse(json['week_end'] as String),
        processedCount: json['processed_count'] as int? ?? 0,
        eventParticipationCount:
            json['event_participation_count'] as int? ?? 0,
        missedCount: json['missed_count'] as int? ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'week_start': _dateToJson(weekStart),
        'week_end': _dateToJson(weekEnd),
        'processed_count': processedCount,
        'event_participation_count': eventParticipationCount,
        'missed_count': missedCount,
      };
}

/// Memory 결과 → 월간 리포트(F-LOG).
class ActivityLog {
  const ActivityLog({
    required this.userId,
    this.processedCount = 0,
    this.eventParticipationCount = 0,
    this.missedCount = 0,
    this.weeklyActivity = const [],
  });

  final String userId;
  final int processedCount;
  final int eventParticipationCount;
  final int missedCount;
  final List<WeeklyActivity> weeklyActivity;

  factory ActivityLog.fromJson(Map<String, dynamic> json) => ActivityLog(
        userId: json['user_id'] as String,
        processedCount: json['processed_count'] as int? ?? 0,
        eventParticipationCount:
            json['event_participation_count'] as int? ?? 0,
        missedCount: json['missed_count'] as int? ?? 0,
        weeklyActivity: (json['weekly_activity'] as List? ?? [])
            .map((e) => WeeklyActivity.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'processed_count': processedCount,
        'event_participation_count': eventParticipationCount,
        'missed_count': missedCount,
        'weekly_activity': weeklyActivity.map((e) => e.toJson()).toList(),
      };
}
