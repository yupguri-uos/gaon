/// 데모 시나리오 고정 데이터 (SSOT 데모 연속성 규칙):
/// "2학년 3반 미술 준비물 + 서울대공원 현장체험학습, 동의서 6/12 마감, 행사 6/16"
/// 기준일(오늘)은 6/10 — 동의서 마감이 D-2가 되는 날.
/// 다자녀 데모: 이서준(2-3, forest) + 이민아(1-1, warn) — 캘린더 색 구분용.
library;

import '../models/schema.dart';

final demoToday = DateTime(2025, 6, 10);

/// 학교명은 schema(Child)에 필드가 없어 UI 전용 상수로 둔다.
/// 스키마 반영은 SSOT 결정 필요 — CLAUDE.md 변경 순서 참조.
const demoSchoolName = '가온초등학교';

final demoUser = User(
  userId: 'demo-user-1',
  displayName: 'Hương',
  originCountry: OriginCountry.vn,
  nativeLanguage: NativeLanguage.vi,
  createdAt: DateTime(2025, 5, 1, 9),
);

final demoChildren = [
  Child(
    childId: 'demo-child-1',
    userId: 'demo-user-1',
    name: '이서준', // PII — 동의 기반 저장 가정(결정 #7-PII)
    grade: ChildGrade.elem2,
    classNo: '3',
    color: '#011D14', // deep forest
    createdAt: DateTime(2025, 5, 1, 9),
  ),
  Child(
    childId: 'demo-child-2',
    userId: 'demo-user-1',
    name: '이민아',
    grade: ChildGrade.elem1,
    classNo: '1',
    color: '#E05A2B', // warn
    createdAt: DateTime(2025, 5, 1, 9),
  ),
];

Child get demoChild => demoChildren.first;

final demoExtractedItem = ExtractedItem(
  docType: DocType.consent,
  title: '서울대공원 현장체험학습 안내 및 동의서',
  dates: [
    DateItem(label: '동의서 제출 마감', date: DateTime(2025, 6, 12)),
    DateItem(label: '현장체험학습', date: DateTime(2025, 6, 16)),
  ],
  supplies: const ['색연필 12색 이상 (크레파스 불가, 이름 기재)'],
  deadline: DateTime(2025, 6, 12),
  requiresReply: true,
  rawText: '2학년 3반 학부모님께. 6월 16일 서울대공원 현장체험학습이 예정되어 있습니다. '
      '동의서를 6/12까지 제출해 주세요. 미술 시간 준비물(색연필 12색 이상)도 확인 부탁드립니다.',
);

/// 단어 해설(F-DOC-5) — 원문 하이라이트·해설 시트의 데이터 소스.
const demoTranslated = TranslatedContent(
  summaryNative:
      'Kính gửi phụ huynh lớp 2, ban 3. Chuyến dã ngoại đến Công viên Lớn Seoul '
      'dự kiến ngày 16/6. Vui lòng nộp đơn đồng ý trước 12/6. '
      'Chuẩn bị bút chì màu (từ 12 màu) cho tiết Mỹ thuật.',
  terms: [
    Term(
      termKo: '현장체험학습',
      literalNative: 'học tập trải nghiệm thực tế',
      explanationNative:
          'Chuyến đi thực tế — học sinh đi tham quan địa điểm thực tế để học hỏi. '
          'Cần đơn đồng ý của phụ huynh và chuẩn bị đồ ăn nhẹ.',
    ),
    Term(
      termKo: '동의서',
      literalNative: 'đơn đồng ý',
      explanationNative:
          'Giấy xác nhận phụ huynh đồng ý cho con tham gia hoạt động. '
          'Ký tên và gửi lại cho giáo viên trước hạn.',
    ),
    Term(
      termKo: '준비물',
      literalNative: 'đồ cần chuẩn bị',
      explanationNative:
          'Những vật dụng con cần mang đến trường — kiểm tra thông báo mỗi tuần.',
    ),
  ],
);

final demoActionCard = ActionCard(
  supplies: const [
    Supply(
      nameKo: '색연필',
      nameNative: 'Bút chì màu',
      explanationNative:
          'Bút chì màu từ 12 màu trở lên (không phải sáp màu), nhớ ghi tên con.',
      spec: '12색 이상 · 색연필(크레파스 불가) · 이름 기재',
      ecommerceKeyword: '색연필 12색',
      ecommerceDeeplink:
          'https://www.coupang.com/np/search?q=%EC%83%89%EC%97%B0%ED%95%84%2012%EC%83%89',
    ),
  ],
  calendarEvents: [
    CalendarEvent(
      title: '동의서 마감',
      date: DateTime(2025, 6, 12),
      type: CalendarEventType.deadline,
      childId: 'demo-child-1',
    ),
    CalendarEvent(
      title: '현장체험학습',
      date: DateTime(2025, 6, 16),
      type: CalendarEventType.event,
      childId: 'demo-child-1',
    ),
    CalendarEvent(
      title: '학예회 발표',
      date: DateTime(2025, 6, 20),
      type: CalendarEventType.event,
      childId: 'demo-child-2',
    ),
  ],
  replyDraftKo:
      '선생님, 안녕하세요. 서울대공원 현장체험학습 동의서를 제출합니다. 참가에 동의합니다. 감사합니다.',
);

final demoActivityLog = ActivityLog(
  userId: 'demo-user-1',
  processedCount: 12,
  eventParticipationCount: 8,
  missedCount: 1,
  weeklyActivity: const [
    WeeklyActivity(week: 1, count: 4),
    WeeklyActivity(week: 2, count: 5),
    WeeklyActivity(week: 3, count: 3),
    WeeklyActivity(week: 4, count: 4),
  ],
);

final demoNotifications = [
  Notification(
    notificationId: 'demo-noti-1',
    userId: 'demo-user-1',
    childId: 'demo-child-1',
    type: NotificationType.deadlineD2,
    titleNative: 'Sắp đến hạn (còn 2 ngày)',
    bodyNative: 'Đơn đồng ý dã ngoại Công viên Lớn Seoul cần nộp trước 12/6.',
    scheduledAt: DateTime(2025, 6, 10, 8, 30),
    relatedDocumentId: 'demo-doc-1',
  ),
];

/// 받는 사람(교사) 목록 — schema에 Teacher 엔티티가 없어 UI 전용 데모 데이터.
/// 실서비스 반영은 SSOT 결정 필요.
const demoTeachers = [
  (name: '박지수 선생님', role: '2학년 3반 담임'),
  (name: '김민정 선생님', role: '영어 전담'),
  (name: '이현우 선생님', role: '체육 전담'),
];

/// Chain B 상황별 데모 응답(F-TCH-2·3).
TeacherMessage demoTeacherMessage({
  required MessageSituation situation,
  required String inputNative,
}) {
  final (outputKo, adminGuideNative) = switch (situation) {
    MessageSituation.absence => (
        '선생님, 안녕하세요. 내일 아이가 열이 나서 결석하겠습니다. 확인 부탁드립니다.',
        'Nếu nghỉ quá 3 ngày liên tục, cần nộp giấy khám bệnh.',
      ),
    MessageSituation.sickNote => (
        '선생님, 안녕하세요. 아이 진단서를 오늘 알림장에 넣어 보냈습니다. 확인 부탁드립니다.',
        'Giấy khám bệnh cần có tên bệnh viện và ngày khám.',
      ),
    MessageSituation.consultation => (
        '선생님, 안녕하세요. 아이 학교생활 관련해 상담을 요청드리고 싶습니다. 가능한 시간을 알려주시면 감사하겠습니다.',
        'Trường thường tổ chức tư vấn phụ huynh định kỳ mỗi học kỳ — có thể yêu cầu phiên dịch miễn phí.',
      ),
    MessageSituation.custom => (
        '선생님, 안녕하세요. 전달드릴 내용이 있어 연락드립니다. 확인 부탁드립니다.',
        'Nội dung tự do — hãy kiểm tra lại bản dịch trước khi gửi.',
      ),
  };
  return TeacherMessage(
    situation: situation,
    inputNative: inputNative,
    outputKo: outputKo,
    adminGuideNative: adminGuideNative,
  );
}
