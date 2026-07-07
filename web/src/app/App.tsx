import { useState, useEffect } from "react";
import {
  Menu, X, ArrowRight, Camera, Sparkles, Calendar,
  MessageSquare, Globe, Clock, Check, Heart, ChevronDown,
} from "lucide-react";

import gaonMark   from "../imports/GAON_logo_PNG.png";
import gaonCard   from "../imports/_____-footprint-flower.png";
import gaonBanner from "../imports/_____-footprint-flower-banner.png";
import gaonApp    from "../imports/_____-footprint-flower-app.png";

/* ─── Palette ──────────────────────────────────────────────────────── */
const C = {
  deep:    "#011D14",
  bg:      "#E6FFF8",
  teal:    "#A2E3DA",
  border1: "#B0F2E8",
  border2: "#C2F1EE",
  mid:     "#2d6055",
} as const;

const APPLE = `-apple-system, BlinkMacSystemFont, "SF Pro Display", "SF Pro Text", "Helvetica Neue", Arial, sans-serif`;

/* ─── i18n 텍스트 ──────────────────────────────────────────────────── */
type Lang = "ko" | "en" | "vi" | "zh";

const T: Record<Lang, Record<string, string>> = {
  ko: {
    langLabel: "언어 선택",
    navAbout: "가온 소개",
    navFeature: "핵심 기능",
    navImpact: "사회적 가치",
    navFaq: "자주 묻는 질문",
    navDownload: "앱 다운로드",
    heroBadge: "다문화 부모를 위한 능동형 AI 에이전트",
    heroH1a: "한국어가 낯설어도,",
    heroH1b: "알림장 번역부터",
    heroH1c: "일정 등록까지",
    heroH1d: "사진 한 장으로 완성",
    heroSub: "가온은 다문화 부모님을 위한 능동형 AI 에이전트입니다. 한국 학교 문화의 맥락을 반영한 번역, 학사 일정 자동 등록, 담임선생님께 보낼 정중한 한국어 답변 초안까지 자동으로 처리해 드립니다.",
    heroCta1: "무료로 시작하기",
    heroCta2: "1분 데모 보기",
    stat1n: "20,000+", stat1l: "다문화 가정",
    stat2n: "15+",     stat2l: "지원 언어",
    stat3n: "98%",     stat3l: "만족도",
    painBadge: "다문화 부모님이 겪는 어려움",
    painH: "왜 학교 정보가\n이렇게 어려울까요?",
    painSub: "수천 명의 다문화 가정의 이야기를 직접 들었습니다.\n이것이 매주 반복되는 현실입니다.",
    pain1t: "언어 장벽", pain1d: "파파고·구글 번역은 단순 직역만 제공합니다. '급수장', '주간학습안내', '가정통신문' 같은 학교 고유 용어의 맥락은 번역되지 않습니다.",
    pain2t: "놓치는 마감일", pain2d: "알림장 속 깊이 박혀있는 '준비물', '동의서 제출 기한', '납부 마감일'을 제때 찾지 못해 중요한 일정을 놓치는 경우가 잦습니다.",
    pain3t: "소통의 불안감", pain3d: "담임선생님께 정중한 한국어 메시지를 직접 작성하는 것은 다문화 부모님에게 매주 반복되는 큰 스트레스입니다.",
    howBadge: "가온 사용법",
    howH: "사진 한 장으로\n모든 것이 해결됩니다",
    how1ko: "사진 촬영", how1en: "사진 찍기", how1d: "학교에서 온 알림장, 가정통신문, 동의서 등 어떤 문서든 사진을 찍으세요. 어두운 조명이나 구겨진 종이도 문제없습니다.", how1n: "OCR + AI 비전",
    how2ko: "맥락 맞춤 번역", how2en: "번역 및 용어 해설", how2d: "가온이 한국 학교 문화를 반영한 번역을 제공하고, 전문 용어를 모국어로 알기 쉽게 설명합니다.", how2n: "15개 이상 언어 지원",
    how3ko: "자동 일정 등록 및 답변", how3en: "일정 등록 & 답변 초안", how3d: "학교 행사와 준비물 마감일이 자동으로 캘린더에 등록되고, 담임선생님께 보낼 정중한 한국어 답변 초안이 생성됩니다.", how3n: "탭 한 번으로 확인",
    showBadge: "앱 주요 화면",
    showH: "가온 앱의 모든 기능을\n직접 살펴보세요",
    feat1t: "OCR 알림장 번역", feat1s: "스마트 OCR 번역", feat1d: "알림장 사진을 찍으면 전체 번역과 함께 학교 용어가 색상 칩으로 강조 표시됩니다. 탭하면 모국어 해설이 바로 나타납니다.",
    feat2t: "하이라이팅 단어 해설", feat2s: "용어 해설 오버레이", feat2d: "강조된 한국 학교 용어를 탭하면 모국어로 된 쉬운 설명이 플로팅 바텀시트로 나타납니다.",
    feat3t: "캘린더 자동 동기화", feat3s: "자동 일정 등록", feat3d: "날짜, 마감일, 학교 행사가 자동으로 감지되어 탭 한 번으로 캘린더에 등록됩니다.",
    feat4t: "한국어 답변 초안", feat4s: "담임 메시지 작성", feat4d: "모국어로 메시지를 입력하면 가온이 담임선생님께 보낼 정중한 한국어 답변을 자동으로 작성해 드립니다.",
    impactBadge: "사회적 가치 · ESG",
    impactH1: "정보 격차 없는",
    impactH2: "다문화 교육 생태계를",
    impactH3: "만들어갑니다",
    impactP1: "가온은 한국에 거주하는 다문화 가정의 교육 정보 격차를 해소하기 위한 ESG·사회적 가치 프로젝트입니다. 언어 장벽으로 인해 어떤 아이도 교육 기회를 놓치지 않도록 하는 것이 가온의 사명입니다.",
    impactP2: "2만여 다문화 가정이 정보 소외 없이 온전한 학교 생활을 누릴 수 있도록 지원하는 것을 목표로 합니다.",
    impactBtn: "미션 자세히 보기",
    imp1n: "20,000+", imp1l: "다문화 가정", imp1ko: "지원 목표",
    imp2n: "15+",     imp2l: "지원 언어",   imp2ko: "모국어 번역",
    imp3n: "98%",     imp3l: "부모 만족도", imp3ko: "앱 사용 후기",
    imp4n: "0",       imp4l: "정보 소외",   imp4ko: "우리의 목표",
    faqBadge: "자주 묻는 질문",
    faqH: "궁금한 점이 있으신가요?",
    faq1q: "어떤 언어를 지원하나요?",
    faq1a: "베트남어, 중국어(간체·번체), 필리핀어, 태국어, 인도네시아어, 러시아어, 영어, 일본어 등 15개 이상의 언어를 지원합니다. 커뮤니티 요청에 따라 계속 추가하고 있습니다.",
    faq2q: "알림장이 아닌 다른 문서도 번역되나요?",
    faq2a: "네, 가정통신문, 동의서, 성적표, 현장학습 안내, 급식 메뉴 등 학교에서 오는 모든 한국어 문서를 처리합니다.",
    faq3q: "개인정보는 안전한가요?",
    faq3a: "업로드된 문서는 실시간으로만 처리되며 영구 저장되지 않습니다. 한국 개인정보보호법(PIPA)을 준수하며 제3자와 정보를 공유하지 않습니다.",
    faq4q: "자녀가 여러 명이어도 사용할 수 있나요?",
    faq4a: "물론입니다. 여러 자녀를 학교, 학년, 반과 함께 등록할 수 있으며, 각 자녀마다 색상으로 구분된 캘린더 뷰를 제공합니다.",
    faq5q: "앱은 무료인가요?",
    faq5a: "핵심 번역 및 캘린더 기능은 무료입니다. 프리미엄 플랜에서는 무제한 문서 기록, 빠른 번역, 선생님 메시지 템플릿 등의 기능을 제공합니다.",
    dlH: "따뜻한 신뢰로\n자녀의 학교생활을 함께해요",
    dlSub: "지금 가온을 다운로드하고 단 하나의 학교 행사도 놓치지 마세요.",
    appStore: "App Store",
    googlePlay: "Google Play",
    footerDesc: "한국 다문화 가정의 교육 정보 격차를 해소하는 능동형 AI 에이전트.",
    footerEmail: "contact@gaon-agent.com",
    footerService: "서비스",
    footerServiceLinks: ["가온 소개", "핵심 기능", "사회적 가치", "앱 다운로드"],
    footerLegal: "법적 고지",
    footerLegalLinks: ["개인정보처리방침", "이용약관", "쿠키 정책", "오픈소스"],
    footerCopy: "© 2024 GAON 가온. All rights reserved.",
    footerMade: "한국의 다문화 가정을 위해 만들었습니다",
    // phone screens
    phoneHeader: "GAON 가온",
    phoneChild: "이서준 · 3학년",
    phoneGreet: "알림장 사진을 보내주세요!\n번역해 드릴게요 📸",
    phoneFile: "📄 알림장.jpg",
    phoneDone: "✅ 번역 완료!",
    phoneResult: "내일(11/15)은 급식비 납부 마감일입니다. 1인당 65,000원을 준비해 주세요.",
    phonePlaceholder: "메시지 입력...",
    transHeader: "번역 결과 카드",
    transHeaderSub: "Translation Result Card",
    transOrigLabel: "원문 (한국어)",
    transOrig: "내일은 급수장 정수기 청소일입니다. 주간학습안내 가정통신문을 확인해주세요.",
    transResultLabel: "번역 결과",
    transResult: "내일은 학교 정수기 청소일입니다. 매주 보내드리는 주간 학습 안내 가정통신문을 확인해 주세요.",
    transTermLabel: "💡 급수장이란?",
    transTerm: "학생들이 물을 채우는 학교 식수대입니다. 보통 한 달에 한 번 청소합니다.",
    calHeader: "2024년 11월",
    calChild: "이서준",
    calEv1: "급식비 납부 마감",
    calEv2: "현장체험학습",
    calEv3: "학예회 발표",
    msgHeader: "문자 작성 · 담임선생님",
    msgHeaderSub: "선생님께 보내는 메시지",
    msgNativeLabel: "내 언어로 작성",
    msgNative: "Xin chào thầy/cô, con tôi sẽ vắng mặt ngày mai vì bệnh. Xin cảm ơn.",
    msgKoLabel: "AI 한국어 번역",
    msgKo: "선생님 안녕하세요. 저희 아이가 내일 몸이 좋지 않아 결석하게 될 것 같습니다. 감사합니다.",
    msgCopy: "복사하기",
    msgShare: "공유하기",
    floatBubble: "알림장 번역 완료 ✓",
    floatBubbleText: '"내일은 급식비 납부 마감일입니다. 1인당 65,000원..."',
    floatCal: "캘린더 등록 완료!",
    floatCalText: "급식비 납부 → 11월 15일",
  },
  en: {
    langLabel: "Language",
    navAbout: "About",
    navFeature: "Features",
    navImpact: "Impact",
    navFaq: "FAQ",
    navDownload: "Download",
    heroBadge: "Active AI Agent for Multicultural Parents",
    heroH1a: "Even if Korean is unfamiliar,",
    heroH1b: "from translation",
    heroH1c: "to calendar sync —",
    heroH1d: "done with one photo.",
    heroSub: "GAON is an active AI agent for multicultural parents. It translates school newsletters with cultural nuance, auto-schedules deadlines, and drafts polite Korean replies to teachers.",
    heroCta1: "Download for Free",
    heroCta2: "Watch 1-Min Demo",
    stat1n: "20,000+", stat1l: "Families",
    stat2n: "15+",     stat2l: "Languages",
    stat3n: "98%",     stat3l: "Satisfaction",
    painBadge: "Struggles Immigrant Parents Face",
    painH: "Why is school info\nso hard to navigate?",
    painSub: "We listened to thousands of multicultural families.\nThese are the walls they face every week.",
    pain1t: "Language Barriers", pain1d: "Papago & Google Translate only give raw literal translations — missing school-specific terms like '급수장' or '주간학습안내' that parents must understand.",
    pain2t: "Missed Deadlines", pain2d: "Parents struggle to spot buried action items — 'what to prepare', 'when to submit agreements', 'fees due' — before it's too late.",
    pain3t: "Communication Anxiety", pain3d: "Writing a formal Korean message or reply to a homeroom teacher causes real stress for multicultural families every week.",
    howBadge: "How GAON Works",
    howH: "One photo.\nEverything handled.",
    how1ko: "사진 촬영", how1en: "Take a Photo", how1d: "Snap any school newsletter, permission slip, or notice. Works in any lighting or paper condition.", how1n: "OCR + AI Vision",
    how2ko: "맥락 맞춤 번역", how2en: "Nuance Translation", how2d: "GAON parses Korean school culture and explains culturally-specific terms in your native language.", how2n: "15+ Languages",
    how3ko: "자동 일정 등록", how3en: "Sync & Draft", how3d: "School events are auto-added to your calendar, and polite Korean reply drafts are generated instantly.", how3n: "One-tap confirm",
    showBadge: "App Screen Flows",
    showH: "See every feature\nof the GAON app.",
    feat1t: "OCR Translation", feat1s: "Smart OCR Translation", feat1d: "Snap a newsletter to get a full translation with school terms highlighted as tappable chips. Tap any chip for an instant explanation.",
    feat2t: "Term Explainer Overlay", feat2s: "Floating Bottom Sheet", feat2d: "Tap any highlighted Korean school term to see a plain-language explanation in your native language.",
    feat3t: "Auto Calendar Sync", feat3s: "One-Tap Calendar Add", feat3d: "Dates, deadlines, and events are auto-detected. One tap to confirm — your calendar stays in sync.",
    feat4t: "Korean Reply Drafts", feat4s: "Teacher Message Composer", feat4d: "Write in your language — GAON drafts a formal, polite Korean message for you to copy and send.",
    impactBadge: "Social Impact · ESG",
    impactH1: "Closing the",
    impactH2: "educational information gap",
    impactH3: "for multicultural Korea.",
    impactP1: "GAON is an ESG and social impact initiative aiming to close the educational information gap for multicultural households in Korea — ensuring no child's school experience suffers because of a language barrier.",
    impactP2: "Targeting 20,000+ multicultural households to experience full school parenting without informational alienation.",
    impactBtn: "Learn About Our Mission",
    imp1n: "20,000+", imp1l: "Multicultural Households", imp1ko: "다문화 가정",
    imp2n: "15+",     imp2l: "Languages Supported",      imp2ko: "지원 언어",
    imp3n: "98%",     imp3l: "Parent Satisfaction",      imp3ko: "부모 만족도",
    imp4n: "0",       imp4l: "Families Left Behind",     imp4ko: "우리의 목표",
    faqBadge: "Frequently Asked Questions",
    faqH: "Got questions?",
    faq1q: "Which languages are supported?",
    faq1a: "Vietnamese, Chinese (Simplified & Traditional), Filipino, Thai, Indonesian, Russian, English, Japanese, and 7+ more. We continue adding languages.",
    faq2q: "Does it work on documents other than newsletters?",
    faq2a: "Yes — school notices, permission slips, grade reports, field trip announcements, lunch menus, and any Korean text your child brings home.",
    faq3q: "Is my data safe?",
    faq3a: "All uploaded documents are processed in real time and never stored permanently. We comply with Korean PIPA and do not share your data with third parties.",
    faq4q: "Can I register multiple children?",
    faq4a: "Absolutely. Register multiple children with their school, grade, and class. Each child gets a color-coded calendar view.",
    faq5q: "Is the app free?",
    faq5a: "Core translation and calendar features are free. A premium plan adds unlimited document history, priority speed, and messaging templates.",
    dlH: "Empower your child's\nschool life with warm trust.",
    dlSub: "Download GAON today and never miss a single school event again.",
    appStore: "App Store",
    googlePlay: "Google Play",
    footerDesc: "An active AI agent closing the educational information gap for multicultural families in Korea.",
    footerEmail: "contact@gaon-agent.com",
    footerService: "Service",
    footerServiceLinks: ["About GAON", "Core Features", "Social Impact", "Download App"],
    footerLegal: "Legal",
    footerLegalLinks: ["Privacy Policy", "Terms of Service", "Cookie Policy", "Open Source"],
    footerCopy: "© 2024 GAON 가온. All rights reserved.",
    footerMade: "Made with care for multicultural families in Korea",
    phoneHeader: "GAON 가온",
    phoneChild: "이서준 · Grade 3",
    phoneGreet: "Send me a photo of your\nschool newsletter! 📸",
    phoneFile: "📄 newsletter.jpg",
    phoneDone: "✅ Translation Complete!",
    phoneResult: "Tomorrow (11/15) is the school lunch fee deadline. Please prepare ₩65,000 per student.",
    phonePlaceholder: "Type a message...",
    transHeader: "Translation Card",
    transHeaderSub: "번역 결과 카드",
    transOrigLabel: "Original (Korean)",
    transOrig: "내일은 급수장 정수기 청소일입니다. 주간학습안내 가정통신문을 확인해주세요.",
    transResultLabel: "Translation",
    transResult: "Tomorrow is the school drinking water station cleaning day. Please check the weekly study guide notice sent home.",
    transTermLabel: "💡 What is 급수장?",
    transTerm: "The school's drinking water station where students fill their bottles. Usually cleaned monthly.",
    calHeader: "November 2024",
    calChild: "이서준",
    calEv1: "Lunch Fee Deadline",
    calEv2: "Field Trip",
    calEv3: "School Concert",
    msgHeader: "Message to Teacher",
    msgHeaderSub: "담임선생님께",
    msgNativeLabel: "Write in your language",
    msgNative: "Xin chào thầy/cô, con tôi sẽ vắng mặt ngày mai vì bệnh. Xin cảm ơn.",
    msgKoLabel: "AI Korean Translation",
    msgKo: "선생님 안녕하세요. 저희 아이가 내일 몸이 좋지 않아 결석하게 될 것 같습니다. 감사합니다.",
    msgCopy: "Copy",
    msgShare: "Share",
    floatBubble: "Translation complete ✓",
    floatBubbleText: '"Tomorrow is the lunch fee deadline. ₩65,000 per student..."',
    floatCal: "Calendar added!",
    floatCalText: "Lunch Fee → Nov 15",
  },
  vi: {
    langLabel: "Ngôn ngữ",
    navAbout: "Giới thiệu",
    navFeature: "Tính năng",
    navImpact: "Tác động",
    navFaq: "Câu hỏi",
    navDownload: "Tải xuống",
    heroBadge: "Trợ lý AI cho phụ huynh đa văn hóa",
    heroH1a: "Dù tiếng Hàn còn xa lạ,",
    heroH1b: "từ dịch thông báo",
    heroH1c: "đến đặt lịch —",
    heroH1d: "chỉ cần một tấm ảnh.",
    heroSub: "GAON là trợ lý AI chủ động cho phụ huynh đa văn hóa. Dịch thông báo trường với sắc thái văn hóa, tự động lên lịch và soạn thảo tin nhắn lịch sự bằng tiếng Hàn.",
    heroCta1: "Tải xuống miễn phí",
    heroCta2: "Xem demo 1 phút",
    stat1n: "20,000+", stat1l: "Gia đình",
    stat2n: "15+",     stat2l: "Ngôn ngữ",
    stat3n: "98%",     stat3l: "Hài lòng",
    painBadge: "Khó khăn phụ huynh gặp phải",
    painH: "Tại sao thông tin trường\nlại khó hiểu vậy?",
    painSub: "Chúng tôi lắng nghe hàng nghìn gia đình.\nĐây là những trở ngại thực tế mỗi tuần.",
    pain1t: "Rào cản ngôn ngữ", pain1d: "Papago & Google Dịch chỉ cho bản dịch thô — không nắm bắt được các thuật ngữ đặc thù của trường học Hàn Quốc.",
    pain2t: "Bỏ lỡ thời hạn", pain2d: "Phụ huynh khó tìm thấy các mục quan trọng như 'chuẩn bị gì', 'nộp giấy khi nào' trước khi quá muộn.",
    pain3t: "Lo lắng khi giao tiếp", pain3d: "Viết tin nhắn lịch sự bằng tiếng Hàn để gửi giáo viên chủ nhiệm là nỗi lo lặp đi lặp lại hàng tuần.",
    howBadge: "Cách GAON hoạt động",
    howH: "Một tấm ảnh.\nMọi thứ được giải quyết.",
    how1ko: "사진 촬영", how1en: "Chụp ảnh", how1d: "Chụp bất kỳ thông báo trường nào. Hoạt động với mọi điều kiện ánh sáng.", how1n: "OCR + AI Vision",
    how2ko: "맥락 맞춤 번역", how2en: "Dịch có ngữ cảnh", how2d: "GAON phân tích văn hóa trường học Hàn Quốc và giải thích thuật ngữ bằng ngôn ngữ mẹ đẻ của bạn.", how2n: "15+ ngôn ngữ",
    how3ko: "자동 일정 등록", how3en: "Đồng bộ & soạn thảo", how3d: "Sự kiện trường tự động thêm vào lịch và tin nhắn lịch sự bằng tiếng Hàn được soạn sẵn.", how3n: "Xác nhận một chạm",
    showBadge: "Màn hình ứng dụng",
    showH: "Khám phá toàn bộ\ntính năng của GAON.",
    feat1t: "Dịch OCR", feat1s: "Dịch thông minh", feat1d: "Chụp thông báo để nhận bản dịch đầy đủ với các thuật ngữ được tô màu. Chạm để xem giải thích.",
    feat2t: "Giải thích thuật ngữ", feat2s: "Bảng giải thích nổi", feat2d: "Chạm vào bất kỳ thuật ngữ nào để xem giải thích bằng ngôn ngữ mẹ đẻ của bạn.",
    feat3t: "Đồng bộ lịch tự động", feat3s: "Thêm lịch một chạm", feat3d: "Ngày tháng và hạn chót được phát hiện tự động. Chạm để xác nhận.",
    feat4t: "Soạn thảo tin nhắn", feat4s: "Soạn tin nhắn giáo viên", feat4d: "Viết bằng tiếng mẹ đẻ — GAON soạn tin nhắn tiếng Hàn lịch sự để bạn gửi.",
    impactBadge: "Tác động xã hội · ESG",
    impactH1: "Thu hẹp khoảng cách",
    impactH2: "thông tin giáo dục",
    impactH3: "cho gia đình đa văn hóa.",
    impactP1: "GAON là sáng kiến ESG nhằm thu hẹp khoảng cách thông tin giáo dục cho các hộ gia đình đa văn hóa tại Hàn Quốc.",
    impactP2: "Mục tiêu hỗ trợ hơn 20.000 hộ gia đình đa văn hóa có thể tham gia đầy đủ vào cuộc sống học đường của con.",
    impactBtn: "Tìm hiểu sứ mệnh",
    imp1n: "20,000+", imp1l: "Gia đình đa văn hóa", imp1ko: "다문화 가정",
    imp2n: "15+",     imp2l: "Ngôn ngữ hỗ trợ",    imp2ko: "지원 언어",
    imp3n: "98%",     imp3l: "Phụ huynh hài lòng", imp3ko: "부모 만족도",
    imp4n: "0",       imp4l: "Gia đình bị bỏ lại",  imp4ko: "목표",
    faqBadge: "Câu hỏi thường gặp",
    faqH: "Bạn có thắc mắc gì không?",
    faq1q: "Ứng dụng hỗ trợ những ngôn ngữ nào?",
    faq1a: "Tiếng Việt, Tiếng Trung (Giản thể & Phồn thể), Tiếng Filipino, Thái, Indonesia, Nga, Anh, Nhật và hơn 7 ngôn ngữ khác.",
    faq2q: "Có dịch được tài liệu khác không?",
    faq2a: "Có — thông báo trường, phiếu đồng ý, bảng điểm, thông báo dã ngoại, thực đơn bữa trưa và mọi văn bản tiếng Hàn.",
    faq3q: "Dữ liệu cá nhân có an toàn không?",
    faq3a: "Tài liệu được xử lý thời gian thực và không lưu trữ vĩnh viễn. Tuân thủ luật bảo vệ thông tin cá nhân Hàn Quốc.",
    faq4q: "Có thể đăng ký nhiều con không?",
    faq4a: "Hoàn toàn được. Mỗi con có lịch riêng được phân biệt bằng màu sắc.",
    faq5q: "Ứng dụng có miễn phí không?",
    faq5a: "Các tính năng cốt lõi miễn phí. Gói premium bổ sung lịch sử tài liệu không giới hạn và mẫu tin nhắn giáo viên.",
    dlH: "Đồng hành cùng con\nvới sự tin tưởng ấm áp.",
    dlSub: "Tải GAON ngay hôm nay và đừng bỏ lỡ bất kỳ sự kiện trường nào.",
    appStore: "App Store",
    googlePlay: "Google Play",
    footerDesc: "Trợ lý AI chủ động thu hẹp khoảng cách thông tin giáo dục cho gia đình đa văn hóa tại Hàn Quốc.",
    footerEmail: "contact@gaon-agent.com",
    footerService: "Dịch vụ",
    footerServiceLinks: ["Giới thiệu", "Tính năng", "Tác động", "Tải xuống"],
    footerLegal: "Pháp lý",
    footerLegalLinks: ["Chính sách quyền riêng tư", "Điều khoản", "Cookie", "Mã nguồn mở"],
    footerCopy: "© 2024 GAON 가온. Bảo lưu mọi quyền.",
    footerMade: "Được tạo ra cho gia đình đa văn hóa tại Hàn Quốc",
    phoneHeader: "GAON 가온",
    phoneChild: "이서준 · Lớp 3",
    phoneGreet: "Hãy gửi ảnh thông báo trường!\nTôi sẽ dịch cho bạn 📸",
    phoneFile: "📄 thong_bao.jpg",
    phoneDone: "✅ Dịch hoàn tất!",
    phoneResult: "Ngày mai (11/15) là hạn chót nộp tiền ăn trưa. Vui lòng chuẩn bị 65.000₩ mỗi học sinh.",
    phonePlaceholder: "Nhập tin nhắn...",
    transHeader: "Thẻ kết quả dịch",
    transHeaderSub: "번역 결과 카드",
    transOrigLabel: "Nguyên bản (Tiếng Hàn)",
    transOrig: "내일은 급수장 정수기 청소일입니다. 주간학습안내 가정통신문을 확인해주세요.",
    transResultLabel: "Bản dịch",
    transResult: "Ngày mai là ngày vệ sinh máy lọc nước tại trạm uống nước của trường. Vui lòng kiểm tra thông báo hướng dẫn học tập hàng tuần.",
    transTermLabel: "💡 급수장 là gì?",
    transTerm: "Trạm uống nước của trường nơi học sinh lấy nước. Thường được vệ sinh hàng tháng.",
    calHeader: "Tháng 11 năm 2024",
    calChild: "이서준",
    calEv1: "Hạn nộp tiền ăn",
    calEv2: "Dã ngoại",
    calEv3: "Biểu diễn văn nghệ",
    msgHeader: "Nhắn tin cho giáo viên",
    msgHeaderSub: "담임선생님께",
    msgNativeLabel: "Viết bằng tiếng của bạn",
    msgNative: "Xin chào thầy/cô, con tôi sẽ vắng mặt ngày mai vì bệnh. Xin cảm ơn.",
    msgKoLabel: "AI dịch sang tiếng Hàn",
    msgKo: "선생님 안녕하세요. 저희 아이가 내일 몸이 좋지 않아 결석하게 될 것 같습니다. 감사합니다.",
    msgCopy: "Sao chép",
    msgShare: "Chia sẻ",
    floatBubble: "Dịch hoàn tất ✓",
    floatBubbleText: '"Ngày mai là hạn nộp tiền ăn. 65.000₩ mỗi học sinh..."',
    floatCal: "Đã thêm vào lịch!",
    floatCalText: "Tiền ăn → 15/11",
  },
  zh: {
    langLabel: "语言",
    navAbout: "关于我们",
    navFeature: "核心功能",
    navImpact: "社会影响",
    navFaq: "常见问题",
    navDownload: "下载应用",
    heroBadge: "为多文化家长打造的主动型AI助手",
    heroH1a: "即使韩语陌生，",
    heroH1b: "从通知单翻译",
    heroH1c: "到日程同步——",
    heroH1d: "一张照片全搞定。",
    heroSub: "GAON是为多文化家长打造的主动型AI助手。提供融合文化背景的翻译，自动添加学校日程，并为您起草礼貌的韩语回复。",
    heroCta1: "免费下载",
    heroCta2: "观看1分钟演示",
    stat1n: "20,000+", stat1l: "多文化家庭",
    stat2n: "15+",     stat2l: "支持语言",
    stat3n: "98%",     stat3l: "满意度",
    painBadge: "家长面临的困境",
    painH: "为什么学校信息\n如此难以理解？",
    painSub: "我们聆听了数千个多文化家庭的心声。\n这些是他们每周面临的真实困境。",
    pain1t: "语言障碍", pain1d: "Papago和谷歌翻译只提供字面翻译，无法理解'급수장'、'주간학습안내'等学校特有术语的含义。",
    pain2t: "错过截止日期", pain2d: "家长很难在通知单中找到关键信息——'需要准备什么'、'什么时候提交'，往往错过重要事项。",
    pain3t: "沟通焦虑", pain3d: "用韩语给班主任写正式消息，对多文化家庭来说是每周都要面对的巨大压力。",
    howBadge: "GAON使用方法",
    howH: "一张照片，\n一切迎刃而解。",
    how1ko: "사진 촬영", how1en: "拍照", how1d: "拍下任何学校通知单。任何光线或纸张状况都没问题。", how1n: "OCR + AI视觉",
    how2ko: "맥락 맞춤 번역", how2en: "语境翻译", how2d: "GAON分析韩国学校文化，用您的母语解释专业术语。", how2n: "支持15+语言",
    how3ko: "자동 일정 등록", how3en: "同步&起草", how3d: "学校活动自动添加到日历，礼貌的韩语回复草稿即时生成。", how3n: "一键确认",
    showBadge: "应用界面展示",
    showH: "探索GAON的\n全部功能。",
    feat1t: "OCR翻译", feat1s: "智能OCR翻译", feat1d: "拍照即可获得完整翻译，学校术语以彩色标签高亮显示，点击即可查看解释。",
    feat2t: "术语解释浮层", feat2s: "浮动底部面板", feat2d: "点击任何高亮的韩国学校术语，即可看到母语解释。",
    feat3t: "自动日历同步", feat3s: "一键添加日历", feat3d: "自动识别日期和截止时间。一键确认即可同步日历。",
    feat4t: "韩语回复草稿", feat4s: "教师消息起草", feat4d: "用母语输入，GAON为您起草礼貌的韩语消息，一键复制发送。",
    impactBadge: "社会影响 · ESG",
    impactH1: "消除信息鸿沟，",
    impactH2: "构建多文化",
    impactH3: "教育生态系统。",
    impactP1: "GAON是一个ESG社会影响力项目，致力于消除韩国多文化家庭在教育信息上的差距，确保没有孩子因语言障碍而错失教育机会。",
    impactP2: "目标帮助20,000余个多文化家庭，让每一位家长都能平等参与孩子的学校生活。",
    impactBtn: "了解我们的使命",
    imp1n: "20,000+", imp1l: "多文化家庭", imp1ko: "다문화 가정",
    imp2n: "15+",     imp2l: "支持语言",   imp2ko: "지원 언어",
    imp3n: "98%",     imp3l: "家长满意度", imp3ko: "부모 만족도",
    imp4n: "0",       imp4l: "被遗落的家庭", imp4ko: "我们的目标",
    faqBadge: "常见问题",
    faqH: "您有什么疑问？",
    faq1q: "支持哪些语言？",
    faq1a: "越南语、中文（简体和繁体）、菲律宾语、泰语、印尼语、俄语、英语、日语等15种以上语言，并持续增加。",
    faq2q: "除了通知单还能翻译其他文件吗？",
    faq2a: "可以——学校通知、同意书、成绩单、郊游通知、午餐菜单及孩子带回的任何韩语文件。",
    faq3q: "个人信息安全吗？",
    faq3a: "上传的文件仅实时处理，不永久存储。遵守韩国个人信息保护法，不与第三方共享。",
    faq4q: "可以注册多个孩子吗？",
    faq4a: "当然可以。每个孩子都有独立的日历视图，用不同颜色区分。",
    faq5q: "应用是免费的吗？",
    faq5a: "核心翻译和日历功能免费。高级计划提供无限文档记录和教师消息模板。",
    dlH: "以温暖的信任，\n守护孩子的学校生活。",
    dlSub: "立即下载GAON，不再错过任何学校活动。",
    appStore: "App Store",
    googlePlay: "Google Play",
    footerDesc: "消除韩国多文化家庭教育信息鸿沟的主动型AI助手。",
    footerEmail: "contact@gaon-agent.com",
    footerService: "服务",
    footerServiceLinks: ["关于我们", "核心功能", "社会影响", "下载应用"],
    footerLegal: "法律信息",
    footerLegalLinks: ["隐私政策", "使用条款", "Cookie政策", "开源"],
    footerCopy: "© 2024 GAON 가온. 保留所有权利。",
    footerMade: "为韩国多文化家庭用心打造",
    phoneHeader: "GAON 가온",
    phoneChild: "이서준 · 3年级",
    phoneGreet: "请发送学校通知单的照片！\n我来帮您翻译 📸",
    phoneFile: "📄 通知单.jpg",
    phoneDone: "✅ 翻译完成！",
    phoneResult: "明天(11/15)是午餐费缴纳截止日期。请准备每人65,000韩元。",
    phonePlaceholder: "输入消息...",
    transHeader: "翻译结果卡片",
    transHeaderSub: "번역 결과 카드",
    transOrigLabel: "原文（韩语）",
    transOrig: "내일은 급수장 정수기 청소일입니다. 주간학습안내 가정통신문을 확인해주세요.",
    transResultLabel: "翻译结果",
    transResult: "明天是学校饮水站净水器清洁日。请查看每周学习指导家庭通知单。",
    transTermLabel: "💡 급수장是什么？",
    transTerm: "学校的饮水站，学生在此灌水。通常每月清洁一次。",
    calHeader: "2024年11月",
    calChild: "이서준",
    calEv1: "午餐费缴纳截止",
    calEv2: "实地体验学习",
    calEv3: "学艺会演出",
    msgHeader: "给老师发消息",
    msgHeaderSub: "담임선생님께",
    msgNativeLabel: "用您的语言书写",
    msgNative: "Xin chào thầy/cô, con tôi sẽ vắng mặt ngày mai vì bệnh. Xin cảm ơn.",
    msgKoLabel: "AI韩语翻译",
    msgKo: "선생님 안녕하세요. 저희 아이가 내일 몸이 좋지 않아 결석하게 될 것 같습니다. 감사합니다.",
    msgCopy: "复制",
    msgShare: "分享",
    floatBubble: "翻译完成 ✓",
    floatBubbleText: '"明天是午餐费缴纳截止日。每人65,000韩元..."',
    floatCal: "已添加到日历！",
    floatCalText: "午餐费 → 11月15日",
  },
};

/* ─── Lang Context ─────────────────────────────────────────────────── */
import { createContext, useContext } from "react";
const LangCtx = createContext<{ lang: Lang; t: typeof T["ko"] }>({ lang: "ko", t: T.ko });
const useLang = () => useContext(LangCtx);

/* ─── Badge ────────────────────────────────────────────────────────── */
function Badge({ children, dark = false }: { children: React.ReactNode; dark?: boolean }) {
  return (
    <span
      className="inline-block text-[11px] font-semibold tracking-wide px-3 py-1 rounded-full"
      style={dark
        ? { background: "rgba(162,227,218,0.14)", color: C.teal, border: "1px solid rgba(162,227,218,0.22)" }
        : { background: C.border2, color: C.deep, border: `1px solid ${C.border1}` }}
    >{children}</span>
  );
}

/* ─── Phone screens ────────────────────────────────────────────────── */
function ChatScreen() {
  const { t } = useLang();
  return (
    <div className="flex flex-col h-full text-[11px]">
      <div className="px-3 py-2.5 border-b flex items-center justify-between" style={{ background: "white", borderColor: C.border2 }}>
        <div className="flex items-center gap-1.5">
          <div className="w-5 h-5 rounded-full flex items-center justify-center font-bold text-[9px]" style={{ background: C.deep, color: C.teal }}>가</div>
          <span className="font-semibold">{t.phoneHeader}</span>
        </div>
        <span className="px-1.5 py-0.5 rounded-full text-[9px] font-medium" style={{ background: C.border2, color: C.deep }}>{t.phoneChild}</span>
      </div>
      <div className="flex-1 p-3 space-y-2.5 overflow-hidden">
        <div className="flex">
          <div className="max-w-[80%] p-2 rounded-2xl rounded-tl-sm leading-relaxed whitespace-pre-line" style={{ background: C.border2, color: C.deep }}>
            {t.phoneGreet}
          </div>
        </div>
        <div className="flex justify-end">
          <div className="max-w-[80%] p-2 rounded-2xl rounded-tr-sm" style={{ background: C.teal }}>
            <div className="w-20 h-14 rounded-lg flex items-center justify-center text-[9px]" style={{ background: "rgba(1,29,20,0.1)", color: C.deep }}>{t.phoneFile}</div>
          </div>
        </div>
        <div className="flex">
          <div className="max-w-[85%] p-2 rounded-2xl rounded-tl-sm leading-relaxed" style={{ background: "white", border: `1px solid ${C.border1}`, color: C.deep }}>
            <div className="font-semibold mb-0.5">{t.phoneDone}</div>
            {t.phoneResult}
          </div>
        </div>
      </div>
      <div className="p-2.5 border-t flex gap-2 items-center" style={{ borderColor: C.border2, background: "white" }}>
        <div className="flex-1 rounded-full px-3 py-1.5 opacity-40" style={{ background: C.bg, border: `1px solid ${C.border1}` }}>{t.phonePlaceholder}</div>
        <div className="w-7 h-7 rounded-full flex items-center justify-center flex-shrink-0" style={{ background: C.deep }}>
          <Camera size={11} style={{ color: C.teal }} />
        </div>
      </div>
    </div>
  );
}

function TranslationScreen() {
  const { t } = useLang();
  return (
    <div className="flex flex-col h-full text-[11px]">
      <div className="px-3 py-2.5 border-b" style={{ background: "white", borderColor: C.border2 }}>
        <div className="font-semibold">{t.transHeader}</div>
        <div className="text-[9px] opacity-50">{t.transHeaderSub}</div>
      </div>
      <div className="flex-1 p-3 space-y-2.5 overflow-hidden">
        <div className="p-2.5 rounded-xl leading-relaxed" style={{ background: C.border2, color: C.deep }}>
          <div className="text-[9px] font-semibold opacity-50 mb-1.5">{t.transOrigLabel}</div>
          내일은{" "}
          <span className="px-1 py-0.5 rounded-md font-semibold" style={{ background: C.teal }}>급수장</span>
          {" "}정수기 청소일입니다.{" "}
          <span className="px-1 py-0.5 rounded-md font-semibold" style={{ background: C.border1 }}>주간학습안내</span>
          {" "}가정통신문을 확인해주세요.
        </div>
        <div className="p-2.5 rounded-xl leading-relaxed" style={{ background: "white", border: `1px solid ${C.border1}`, color: C.deep }}>
          <div className="text-[9px] font-semibold opacity-50 mb-1.5">{t.transResultLabel}</div>
          {t.transResult}
        </div>
        <div className="p-2.5 rounded-xl" style={{ background: C.deep, color: C.teal }}>
          <div className="text-[9px] font-semibold opacity-60 mb-0.5">{t.transTermLabel}</div>
          <div style={{ color: C.bg, opacity: 0.9 }}>{t.transTerm}</div>
        </div>
      </div>
    </div>
  );
}

function CalendarScreen() {
  const { t } = useLang();
  const dayNames = ["일", "월", "화", "수", "목", "금", "토"];
  const events: Record<number, string> = { 15: C.teal, 22: C.border1, 28: C.deep };
  const evList = [
    { day: 15, label: t.calEv1, dot: C.teal },
    { day: 22, label: t.calEv2, dot: C.border1 },
    { day: 28, label: t.calEv3, dot: C.deep },
  ];
  return (
    <div className="flex flex-col h-full text-[10px]">
      <div className="px-3 py-2.5 border-b flex justify-between items-center" style={{ background: "white", borderColor: C.border2 }}>
        <div className="font-semibold text-[11px]">{t.calHeader}</div>
        <span className="px-1.5 py-0.5 rounded-full font-medium" style={{ background: C.border2, color: C.deep }}>{t.calChild}</span>
      </div>
      <div className="p-3">
        <div className="grid grid-cols-7 mb-1.5">
          {dayNames.map(d => <div key={d} className="text-center opacity-40 font-semibold">{d}</div>)}
        </div>
        <div className="grid grid-cols-7">
          {[...Array(4)].map((_, i) => <div key={`e${i}`} />)}
          {[...Array(30)].map((_, i) => {
            const day = i + 1;
            const dot = events[day];
            return (
              <div key={day} className="flex flex-col items-center py-1">
                <div className="w-6 h-6 flex items-center justify-center rounded-full"
                  style={day === 15 ? { background: C.deep, color: "white", fontWeight: 700 } : { opacity: 0.7 }}>
                  {day}
                </div>
                {dot && <div className="w-1 h-1 rounded-full mt-0.5" style={{ background: dot }} />}
              </div>
            );
          })}
        </div>
      </div>
      <div className="px-3 space-y-1.5">
        {evList.map(e => (
          <div key={e.day} className="flex items-center gap-2 p-2 rounded-xl" style={{ background: C.border2 }}>
            <div className="w-1.5 h-1.5 rounded-full flex-shrink-0" style={{ background: e.dot }} />
            <span className="font-semibold">{e.day}일</span>
            <span className="opacity-70">{e.label}</span>
          </div>
        ))}
      </div>
    </div>
  );
}

/* ─── Hero visual: logo card + floating phone ──────────────────────── */
function HeroVisual() {
  const { t } = useLang();
  return (
    <div className="relative w-full flex justify-center items-start" style={{ minHeight: 480 }}>
      {/* Ambient glow */}
      <div className="absolute inset-0 flex items-center justify-center pointer-events-none">
        <div className="w-72 h-72 rounded-full opacity-30" style={{ background: C.teal, filter: "blur(72px)" }} />
      </div>

      {/* Main logo card — centered, prominent */}
      <div
        className="relative z-10 mt-4"
        style={{ filter: "drop-shadow(0 24px 56px rgba(1,29,20,0.22))" }}
      >
        <img
          src={gaonCard}
          alt="가온 — 다문화 가정의 든든한 동반자"
          className="w-64 md:w-72 rounded-[2rem] select-none"
          draggable={false}
        />
      </div>

      {/* Mini phone mockup — bottom-right overlap */}
      <div
        className="absolute bottom-0 right-0 md:-right-4 z-20"
        style={{ filter: "drop-shadow(0 16px 32px rgba(1,29,20,0.28))" }}
      >
        <div className="w-36 rounded-[1.8rem] overflow-hidden border-[3px]" style={{ background: C.deep, borderColor: "#1a3828" }}>
          <div className="h-4 flex items-center justify-center">
            <div className="w-8 h-2 rounded-full" style={{ background: "#1a3028" }} />
          </div>
          <div style={{ background: C.bg }}>
            {/* mini chat preview */}
            <div className="px-2 py-2 border-b flex items-center gap-1.5" style={{ background: "white", borderColor: C.border2 }}>
              <img src={gaonApp} alt="" className="w-4 h-4 rounded-md" />
              <span className="text-[9px] font-semibold" style={{ color: C.deep }}>GAON 가온</span>
            </div>
            <div className="p-2 space-y-1.5">
              <div className="rounded-xl p-1.5 text-[8px] leading-relaxed" style={{ background: C.border2, color: C.deep }}>
                {t.phoneDone}
              </div>
              <div className="rounded-xl p-1.5 text-[8px] leading-relaxed" style={{ background: "white", border: `1px solid ${C.border1}`, color: C.deep }}>
                {t.phoneResult.slice(0, 30)}...
              </div>
            </div>
          </div>
          <div className="h-3 flex items-center justify-center">
            <div className="w-10 h-0.5 rounded-full" style={{ background: "rgba(255,255,255,0.15)" }} />
          </div>
        </div>
      </div>

      {/* Floating translation bubble — top-left */}
      <div
        className="absolute top-10 -left-2 md:-left-8 z-20 w-40 p-2.5 rounded-2xl text-[10px] shadow-lg"
        style={{ background: "white", border: `1px solid ${C.border2}` }}
      >
        <div className="opacity-50 mb-0.5">{t.floatBubble}</div>
        <div className="font-semibold leading-snug" style={{ color: C.deep }}>{t.floatBubbleText}</div>
      </div>

      {/* Floating calendar chip — left-center */}
      <div
        className="absolute bottom-24 -left-4 md:-left-10 z-20 p-2.5 rounded-2xl text-[10px] shadow-lg"
        style={{ background: C.teal, color: C.deep }}
      >
        <div className="flex items-center gap-1 font-semibold mb-0.5">
          <Calendar size={10} />{t.floatCal}
        </div>
        <div className="opacity-75">{t.floatCalText}</div>
      </div>
    </div>
  );
}

/* ─── Hero phone ───────────────────────────────────────────────────── */
function HeroPhone() {
  const { t } = useLang();
  const [screen, setScreen] = useState(0);
  useEffect(() => {
    const id = setInterval(() => setScreen(s => (s + 1) % 3), 3500);
    return () => clearInterval(id);
  }, []);
  const screens = [<ChatScreen key="c" />, <TranslationScreen key="t" />, <CalendarScreen key="k" />];
  return (
    <div className="relative flex justify-center">
      <div className="absolute top-8 left-1/2 -translate-x-1/2 w-64 h-64 rounded-full opacity-25 pointer-events-none" style={{ background: C.teal, filter: "blur(56px)" }} />
      <div className="relative z-10 w-60" style={{ filter: "drop-shadow(0 28px 48px rgba(1,29,20,0.24))" }}>
        <div className="rounded-[2.8rem] overflow-hidden border-[3.5px]" style={{ background: C.deep, borderColor: "#1a3828" }}>
          <div className="h-7 flex items-center justify-between px-5">
            <span className="text-[10px]" style={{ color: "rgba(230,255,248,0.4)" }}>9:41</span>
            <div className="w-14 h-3.5 rounded-full" style={{ background: "#1a3028" }} />
            <div className="w-5 h-2 rounded-sm opacity-40" style={{ background: C.teal }} />
          </div>
          <div className="h-[440px] overflow-hidden" style={{ background: C.bg }}>{screens[screen]}</div>
          <div className="h-5 flex items-center justify-center">
            <div className="w-20 h-0.5 rounded-full" style={{ background: "rgba(255,255,255,0.18)" }} />
          </div>
        </div>
        <div className="flex justify-center gap-1.5 mt-4">
          {[0, 1, 2].map(i => (
            <button key={i} onClick={() => setScreen(i)} className="rounded-full transition-all"
              style={{ width: i === screen ? 20 : 6, height: 6, background: i === screen ? C.deep : C.border1 }} />
          ))}
        </div>
      </div>
      {/* Floating bubbles */}
      <div className="absolute -right-2 md:-right-10 top-20 w-44 p-3 rounded-2xl text-[11px] shadow-xl" style={{ background: "white", border: `1px solid ${C.border2}` }}>
        <div className="opacity-50 mb-1">{t.floatBubble}</div>
        <div className="font-semibold leading-relaxed" style={{ color: C.deep }}>{t.floatBubbleText}</div>
      </div>
      <div className="absolute -left-2 md:-left-10 bottom-28 p-3 rounded-2xl text-[11px] shadow-xl" style={{ background: C.teal, color: C.deep }}>
        <div className="flex items-center gap-1 mb-1 font-semibold"><Calendar size={11} />{t.floatCal}</div>
        <div className="opacity-75">{t.floatCalText}</div>
      </div>
    </div>
  );
}

/* ─── Message phone ────────────────────────────────────────────────── */
function MessagePhone() {
  const { t } = useLang();
  return (
    <div className="relative w-52 mx-auto" style={{ filter: "drop-shadow(0 22px 36px rgba(1,29,20,0.2))" }}>
      <div className="rounded-[2.8rem] overflow-hidden border-[3.5px]" style={{ background: C.deep, borderColor: "#1a3828" }}>
        <div className="h-6 flex items-center justify-center">
          <div className="w-12 h-2.5 rounded-full" style={{ background: "#1a3028" }} />
        </div>
        <div style={{ background: C.bg }}>
          <div className="px-4 py-2.5 border-b" style={{ background: "white", borderColor: C.border2 }}>
            <div className="text-[11px] font-semibold">{t.msgHeader}</div>
            <div className="text-[9px] opacity-50">{t.msgHeaderSub}</div>
          </div>
          <div className="p-3 border-b" style={{ borderColor: C.border2 }}>
            <div className="text-[9px] font-semibold opacity-50 mb-1.5">{t.msgNativeLabel}</div>
            <div className="p-2.5 rounded-xl text-[10px] leading-relaxed" style={{ background: "white", border: `1px solid ${C.border1}`, color: C.deep, minHeight: 52 }}>{t.msgNative}</div>
          </div>
          <div className="p-3 border-b" style={{ borderColor: C.border2 }}>
            <div className="flex items-center gap-1 mb-1.5"><Sparkles size={8} style={{ color: C.deep }} /><div className="text-[9px] font-semibold opacity-50">{t.msgKoLabel}</div></div>
            <div className="p-2.5 rounded-xl text-[10px] leading-relaxed" style={{ background: C.border2, color: C.deep, minHeight: 52 }}>{t.msgKo}</div>
          </div>
          <div className="p-3 flex gap-2">
            <button className="flex-1 py-2 rounded-full text-[9px] font-semibold" style={{ background: C.deep, color: C.teal }}>{t.msgCopy}</button>
            <button className="flex-1 py-2 rounded-full text-[9px] font-semibold" style={{ border: `1px solid ${C.border1}`, color: C.deep }}>{t.msgShare}</button>
          </div>
        </div>
        <div className="h-4 flex items-center justify-center">
          <div className="w-16 h-0.5 rounded-full" style={{ background: "rgba(255,255,255,0.15)" }} />
        </div>
      </div>
    </div>
  );
}

/* ─── Language toggle ──────────────────────────────────────────────── */
const LANGS: { code: Lang; flag: string; label: string }[] = [
  { code: "ko", flag: "🇰🇷", label: "한국어" },
  { code: "en", flag: "🇺🇸", label: "English" },
  { code: "vi", flag: "🇻🇳", label: "Tiếng Việt" },
  { code: "zh", flag: "🇨🇳", label: "中文" },
];

function LangSwitcher({ lang, setLang }: { lang: Lang; setLang: (l: Lang) => void }) {
  const [open, setOpen] = useState(false);
  const cur = LANGS.find(l => l.code === lang)!;
  return (
    <div className="relative">
      <button
        onClick={() => setOpen(o => !o)}
        className="flex items-center gap-1.5 px-3 py-1.5 rounded-full text-xs font-semibold transition-all hover:opacity-80"
        style={{ background: C.border2, color: C.deep, border: `1px solid ${C.border1}` }}
      >
        <span>{cur.flag}</span>
        <span>{cur.label}</span>
        <Globe size={12} className="opacity-50" />
      </button>
      {open && (
        <div
          className="absolute right-0 top-10 w-36 rounded-2xl overflow-hidden shadow-xl z-50"
          style={{ background: "white", border: `1px solid ${C.border1}` }}
        >
          {LANGS.map(l => (
            <button
              key={l.code}
              onClick={() => { setLang(l.code); setOpen(false); }}
              className="w-full flex items-center gap-2.5 px-4 py-2.5 text-xs font-medium text-left transition-colors hover:opacity-80"
              style={{ background: l.code === lang ? C.border2 : "transparent", color: C.deep }}
            >
              <span>{l.flag}</span>
              <span>{l.label}</span>
            </button>
          ))}
        </div>
      )}
    </div>
  );
}

/* ─── Nav ──────────────────────────────────────────────────────────── */
function Nav({ lang, setLang }: { lang: Lang; setLang: (l: Lang) => void }) {
  const { t } = useLang();
  const [menuOpen, setMenuOpen] = useState(false);
  const [scrolled, setScrolled] = useState(false);
  useEffect(() => {
    const fn = () => setScrolled(window.scrollY > 50);
    window.addEventListener("scroll", fn);
    return () => window.removeEventListener("scroll", fn);
  }, []);
  return (
    <nav className="fixed top-0 left-0 right-0 z-50 transition-all duration-300"
      style={{ background: scrolled ? "rgba(230,255,248,0.94)" : "transparent", backdropFilter: scrolled ? "blur(14px)" : "none", borderBottom: scrolled ? `1px solid ${C.border1}` : "1px solid transparent" }}>
      <div className="max-w-6xl mx-auto px-6 h-16 flex items-center justify-between gap-4">
        <div className="flex items-center gap-2 flex-shrink-0">
          <img src={gaonMark} alt="가온 로고" className="h-8 w-auto" />
          <span className="font-bold text-base tracking-tight" style={{ color: C.deep }}>GAON <span className="font-normal opacity-50 text-sm">가온</span></span>
        </div>
        <div className="hidden md:flex items-center gap-7 text-[13px] font-medium flex-1 justify-center">
          {[t.navAbout, t.navFeature, t.navImpact, t.navFaq].map(link => (
            <a key={link} href="#" className="transition-opacity hover:opacity-100" style={{ color: C.deep, opacity: 0.58 }}>{link}</a>
          ))}
        </div>
        <div className="hidden md:flex items-center gap-3 flex-shrink-0">
          <LangSwitcher lang={lang} setLang={setLang} />
          <button className="px-5 py-2 rounded-full text-sm font-semibold transition-all hover:opacity-90 hover:scale-[1.02]"
            style={{ background: C.deep, color: C.teal }}>{t.navDownload}</button>
        </div>
        <div className="md:hidden flex items-center gap-2">
          <LangSwitcher lang={lang} setLang={setLang} />
          <button className="p-1" onClick={() => setMenuOpen(o => !o)} style={{ color: C.deep }}>
            {menuOpen ? <X size={22} /> : <Menu size={22} />}
          </button>
        </div>
      </div>
      {menuOpen && (
        <div className="md:hidden px-6 pb-6 pt-2 space-y-4 border-t" style={{ background: C.bg, borderColor: C.border1 }}>
          {[t.navAbout, t.navFeature, t.navImpact, t.navFaq].map(link => (
            <a key={link} href="#" className="block text-sm font-medium opacity-70" style={{ color: C.deep }}>{link}</a>
          ))}
          <button className="w-full px-5 py-3 rounded-full text-sm font-semibold" style={{ background: C.deep, color: C.teal }}>{t.navDownload}</button>
        </div>
      )}
    </nav>
  );
}

/* ─── Hero ─────────────────────────────────────────────────────────── */
function HeroSection() {
  const { t } = useLang();
  return (
    <section className="pt-28 pb-20 px-6 max-w-6xl mx-auto">
      <div className="grid md:grid-cols-[1fr_auto] gap-16 items-center">
        <div className="max-w-xl">
          <Badge>{t.heroBadge}</Badge>
          <h1 className="mt-7 text-4xl md:text-[3.1rem] font-bold leading-[1.2] tracking-tight" style={{ color: C.deep }}>
            {t.heroH1a}<br />
            <span style={{ color: C.mid }}>{t.heroH1b}</span><br />
            <span style={{ color: C.mid }}>{t.heroH1c}</span><br />
            {t.heroH1d}
          </h1>
          <p className="mt-5 text-base md:text-[1.05rem] leading-relaxed opacity-68 max-w-md" style={{ color: C.deep }}>{t.heroSub}</p>
          <div className="mt-8 flex flex-wrap gap-3">
            <button className="flex items-center gap-2 px-7 py-3.5 rounded-full font-semibold text-sm transition-all hover:scale-[1.03] hover:shadow-xl"
              style={{ background: C.teal, color: C.deep, boxShadow: `0 4px 20px rgba(162,227,218,0.45)` }}>
              {t.heroCta1}<ArrowRight size={15} />
            </button>
            <button className="flex items-center gap-2 px-7 py-3.5 rounded-full font-semibold text-sm transition-all hover:opacity-75"
              style={{ border: `1.5px solid ${C.deep}`, color: C.deep }}>{t.heroCta2}</button>
          </div>
          <div className="mt-10 flex items-center gap-8">
            {([
              [t.stat1n, t.stat1l],
              [t.stat2n, t.stat2l],
              [t.stat3n, t.stat3l],
            ] as [string, string][]).map(([n, l], i) => (
              <div key={l} className="flex items-center gap-8">
                <div className="text-center">
                  <div className="text-2xl font-bold" style={{ color: C.deep }}>{n}</div>
                  <div className="text-[11px] opacity-55 mt-0.5">{l}</div>
                </div>
                {i < 2 && <div className="w-px h-8 opacity-20" style={{ background: C.deep }} />}
              </div>
            ))}
          </div>
        </div>
        <div className="md:w-[340px] w-full flex justify-center">
          <HeroPhone />
        </div>
      </div>
    </section>
  );
}

/* ─── Pain ─────────────────────────────────────────────────────────── */
function PainSection() {
  const { t } = useLang();
  const cards = [
    { icon: Globe,          title: t.pain1t, desc: t.pain1d },
    { icon: Clock,          title: t.pain2t, desc: t.pain2d },
    { icon: MessageSquare,  title: t.pain3t, desc: t.pain3d },
  ];
  return (
    <section className="py-20 px-6 max-w-6xl mx-auto">
      <div className="text-center mb-14">
        <Badge>{t.painBadge}</Badge>
        <h2 className="mt-5 text-3xl md:text-4xl font-bold whitespace-pre-line" style={{ color: C.deep }}>{t.painH}</h2>
        <p className="mt-4 text-sm opacity-60 max-w-md mx-auto leading-relaxed whitespace-pre-line" style={{ color: C.deep }}>{t.painSub}</p>
      </div>
      <div className="grid md:grid-cols-3 gap-6">
        {cards.map(({ icon: Icon, title, desc }) => (
          <div key={title} className="p-7 rounded-3xl transition-all hover:-translate-y-1.5 hover:shadow-xl"
            style={{ background: C.border2, border: `1px solid ${C.border1}` }}>
            <div className="w-12 h-12 rounded-2xl flex items-center justify-center mb-6" style={{ background: C.mid }}>
              <Icon size={22} style={{ color: C.teal }} />
            </div>
            <h3 className="text-lg font-bold mb-3" style={{ color: C.deep }}>{title}</h3>
            <p className="text-sm leading-relaxed opacity-65" style={{ color: C.deep }}>{desc}</p>
          </div>
        ))}
      </div>
    </section>
  );
}

/* ─── How ──────────────────────────────────────────────────────────── */
function HowSection() {
  const { t } = useLang();
  const steps = [
    { icon: Camera,   ko: t.how1ko, en: t.how1en, desc: t.how1d, note: t.how1n, num: "01" },
    { icon: Sparkles, ko: t.how2ko, en: t.how2en, desc: t.how2d, note: t.how2n, num: "02" },
    { icon: Calendar, ko: t.how3ko, en: t.how3en, desc: t.how3d, note: t.how3n, num: "03" },
  ];
  return (
    <section className="py-20 px-6" style={{ background: "white" }}>
      <div className="max-w-6xl mx-auto">
        <div className="text-center mb-16">
          <Badge>{t.howBadge}</Badge>
          <h2 className="mt-5 text-3xl md:text-4xl font-bold whitespace-pre-line" style={{ color: C.deep }}>{t.howH}</h2>
        </div>
        <div className="grid md:grid-cols-3 gap-10">
          {steps.map(({ icon: Icon, ko, en, desc, note, num }, i) => (
            <div key={num} className="relative">
              {i < 2 && <div className="hidden md:block absolute top-8 left-[68%] right-[-32%] h-px" style={{ background: `linear-gradient(to right, ${C.border1}, transparent)` }} />}
              <div className="flex gap-5 items-start">
                <div className="flex-shrink-0 relative">
                  <div className="w-16 h-16 rounded-2xl flex items-center justify-center" style={{ background: C.bg, border: `2px solid ${C.border1}` }}>
                    <Icon size={26} style={{ color: C.deep }} />
                  </div>
                  <div className="absolute -top-2 -right-2 w-6 h-6 rounded-full flex items-center justify-center text-[10px] font-bold" style={{ background: C.deep, color: C.teal }}>{i + 1}</div>
                </div>
                <div className="pt-1">
                  <div className="font-mono text-[10px] opacity-30 mb-0.5">{num}</div>
                  <div className="text-[11px] opacity-50 font-medium mb-0.5">{ko}</div>
                  <h3 className="text-lg font-bold mb-2" style={{ color: C.deep }}>{en}</h3>
                  <p className="text-sm leading-relaxed opacity-65 mb-3" style={{ color: C.deep }}>{desc}</p>
                  <span className="text-[10px] px-2 py-1 rounded-full font-semibold" style={{ background: C.border2, color: C.mid }}>{note}</span>
                </div>
              </div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}

/* ─── Showcase ─────────────────────────────────────────────────────── */
function ShowcaseSection() {
  const { t } = useLang();
  const feats = [
    { title: t.feat1t, sub: t.feat1s, desc: t.feat1d, tag: "Flow 2" },
    { title: t.feat2t, sub: t.feat2s, desc: t.feat2d, tag: "Interactive" },
    { title: t.feat3t, sub: t.feat3s, desc: t.feat3d, tag: "Flow 3" },
    { title: t.feat4t, sub: t.feat4s, desc: t.feat4d, tag: "Flow 4" },
  ];
  return (
    <section className="py-20 px-6 max-w-6xl mx-auto">
      <div className="text-center mb-16">
        <Badge>{t.showBadge}</Badge>
        <h2 className="mt-5 text-3xl md:text-4xl font-bold whitespace-pre-line" style={{ color: C.deep }}>{t.showH}</h2>
      </div>
      <div className="grid md:grid-cols-2 gap-14 items-start">
        <div className="space-y-8">
          {feats.map(({ title, sub, desc, tag }) => (
            <div key={title} className="flex gap-5">
              <div className="flex-shrink-0 w-10 h-10 rounded-2xl flex items-center justify-center mt-0.5" style={{ background: C.border2 }}>
                <Check size={18} style={{ color: C.deep }} />
              </div>
              <div>
                <div className="flex flex-wrap items-center gap-2 mb-1">
                  <h4 className="font-bold text-base" style={{ color: C.deep }}>{title}</h4>
                  <span className="text-[10px] px-2 py-0.5 rounded-full font-semibold" style={{ background: C.border1, color: C.mid }}>{tag}</span>
                </div>
                <div className="text-[11px] opacity-45 mb-1">{sub}</div>
                <p className="text-sm opacity-65 leading-relaxed" style={{ color: C.deep }}>{desc}</p>
              </div>
            </div>
          ))}
        </div>
        <div className="flex justify-center"><MessagePhone /></div>
      </div>
    </section>
  );
}

/* ─── Impact ───────────────────────────────────────────────────────── */
function ImpactSection() {
  const { t } = useLang();

  const stats = [
    { n: t.imp1n, l: t.imp1l, ko: t.imp1ko },
    { n: t.imp2n, l: t.imp2l, ko: t.imp2ko },
    { n: t.imp3n, l: t.imp3l, ko: t.imp3ko },
    { n: t.imp4n, l: t.imp4l, ko: t.imp4ko },
  ];
  return (
    <section style={{ background: C.deep }}>
      {/* Banner image strip */}
      <div className="w-full overflow-hidden" style={{ maxHeight: 200 }}>
        <img
          src={gaonBanner}
          alt="가온 — 다문화 가정의 든든한 동반자"
          className="w-full object-cover object-center select-none"
          style={{ opacity: 0.85 }}
          draggable={false}
        />
      </div>

      <div className="py-24 px-6">
      <div className="max-w-6xl mx-auto grid md:grid-cols-2 gap-16 items-center">
        <div>
          <Badge dark>{t.impactBadge}</Badge>
          <h2 className="mt-6 text-3xl md:text-4xl font-bold leading-tight" style={{ color: C.bg }}>
            {t.impactH1}<br /><span style={{ color: C.teal }}>{t.impactH2}</span><br />{t.impactH3}
          </h2>
          <p className="mt-5 text-sm leading-relaxed" style={{ color: "rgba(230,255,248,0.62)" }}>{t.impactP1}</p>
          <p className="mt-3 text-sm leading-relaxed" style={{ color: "rgba(230,255,248,0.62)" }}>{t.impactP2}</p>
          <button className="mt-8 flex items-center gap-2 px-6 py-3.5 rounded-full font-semibold text-sm transition-all hover:opacity-90 hover:scale-[1.02]"
            style={{ background: C.teal, color: C.deep }}>{t.impactBtn}<ArrowRight size={15} /></button>
        </div>
        <div className="grid grid-cols-2 gap-4">
          {stats.map(({ n, l, ko }) => (
            <div key={l} className="p-6 rounded-3xl transition-all hover:scale-[1.02]"
              style={{ background: "rgba(162,227,218,0.07)", border: "1px solid rgba(162,227,218,0.14)" }}>
              <div className="text-3xl font-bold mb-1.5" style={{ color: C.teal }}>{n}</div>
              <div className="text-sm font-semibold mb-0.5" style={{ color: C.bg }}>{l}</div>
              <div className="text-[11px] opacity-45" style={{ color: C.teal }}>{ko}</div>
            </div>
          ))}
        </div>
      </div>
      </div>
    </section>
  );
}

/* ─── FAQ ──────────────────────────────────────────────────────────── */
function FaqSection() {
  const { t } = useLang();
  const [open, setOpen] = useState<number | null>(null);
  const faqs = [
    { q: t.faq1q, a: t.faq1a },
    { q: t.faq2q, a: t.faq2a },
    { q: t.faq3q, a: t.faq3a },
    { q: t.faq4q, a: t.faq4a },
    { q: t.faq5q, a: t.faq5a },
  ];
  return (
    <section className="py-20 px-6" style={{ background: "white" }}>
      <div className="max-w-3xl mx-auto">
        <div className="text-center mb-14">
          <Badge>{t.faqBadge}</Badge>
          <h2 className="mt-5 text-3xl md:text-4xl font-bold" style={{ color: C.deep }}>{t.faqH}</h2>
        </div>
        <div className="space-y-3">
          {faqs.map(({ q, a }, i) => (
            <div key={i} className="rounded-2xl overflow-hidden transition-all"
              style={{ border: `1px solid ${open === i ? C.teal : C.border1}`, background: open === i ? C.bg : "white" }}>
              <button className="w-full px-6 py-5 flex items-center justify-between text-left font-semibold text-sm"
                style={{ color: C.deep }} onClick={() => setOpen(open === i ? null : i)}>
                <span>{q}</span>
                <ChevronDown size={18} className="flex-shrink-0 transition-transform" style={{ transform: open === i ? "rotate(180deg)" : "none", color: C.mid }} />
              </button>
              {open === i && <div className="px-6 pb-5 text-sm leading-relaxed" style={{ color: C.deep, opacity: 0.72 }}>{a}</div>}
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}

/* ─── Download CTA ─────────────────────────────────────────────────── */
function DownloadSection() {
  const { t } = useLang();
  return (
    <section className="py-20 px-6" style={{ background: C.bg }}>
      <div className="max-w-4xl mx-auto">
        <div className="p-10 md:p-16 rounded-3xl text-center"
          style={{ background: "white", border: `1px solid ${C.border1}`, boxShadow: `0 8px 48px rgba(162,227,218,0.18)` }}>
          <div className="w-16 h-16 rounded-3xl flex items-center justify-center mx-auto mb-7" style={{ background: C.deep }}>
            <Heart size={28} style={{ color: C.teal }} />
          </div>
          <h2 className="text-3xl md:text-4xl font-bold mb-4 leading-tight whitespace-pre-line" style={{ color: C.deep }}>{t.dlH}</h2>
          <p className="text-sm md:text-base opacity-60 mb-10 max-w-md mx-auto leading-relaxed" style={{ color: C.deep }}>{t.dlSub}</p>
          <div className="flex flex-col sm:flex-row gap-4 justify-center mb-10">
            {[
              { label: t.appStore, svg: <path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.8-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z" /> },
              { label: t.googlePlay, svg: <path d="M3.18 23.76c.26.14.56.18.85.12l12.2-6.95-2.71-2.71-10.34 9.54zM.73 2.29C.28 2.72 0 3.4 0 4.28v15.44c0 .88.28 1.56.73 1.99l.1.09 8.65-8.65v-.2L.83 2.2l-.1.09zm18.68 8.43l-2.47-1.4-3.06 3.06 3.06 3.06 2.48-1.42c.71-.4.71-1.06 0-1.46l-.01.16zm-18 10.47l11.85-6.74-2.71-2.71L.73 20.2l-.32.99z" /> },
            ].map(({ label, svg }) => (
              <button key={label} className="flex items-center justify-center gap-3 px-8 py-4 rounded-2xl font-semibold transition-all hover:opacity-90 hover:scale-[1.02]"
                style={{ background: C.deep, color: C.teal, boxShadow: `0 4px 20px rgba(1,29,20,0.18)` }}>
                <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor">{svg}</svg>
                {label}
              </button>
            ))}
          </div>
          <div className="flex justify-center gap-10">
            {[t.appStore, t.googlePlay].map(label => (
              <div key={label} className="text-center">
                <div className="w-[72px] h-[72px] rounded-xl mx-auto mb-2 flex items-center justify-center"
                  style={{ border: `2px dashed ${C.border1}`, background: C.bg }}>
                  <span className="text-[9px] opacity-35 text-center leading-tight">QR<br />Code</span>
                </div>
                <div className="text-[11px] opacity-45">{label} QR</div>
              </div>
            ))}
          </div>
        </div>
      </div>
    </section>
  );
}

/* ─── Footer ───────────────────────────────────────────────────────── */
function Footer() {
  const { t } = useLang();
  return (
    <footer className="py-12 px-6 border-t" style={{ borderColor: C.border1, background: C.bg }}>
      <div className="max-w-6xl mx-auto">
        <div className="grid md:grid-cols-4 gap-10 mb-10">
          <div className="md:col-span-2">
            <div className="flex items-center gap-3 mb-4">
              <img src={gaonMark} alt="가온 로고" className="h-10 w-auto" />
              <div>
                <div className="font-bold text-lg leading-tight" style={{ color: C.deep }}>GAON 가온</div>
                <div className="text-[11px] opacity-50 leading-tight" style={{ color: C.deep }}>다문화 가정의 든든한 동반자</div>
              </div>
            </div>
            <p className="text-sm opacity-60 leading-relaxed max-w-xs" style={{ color: C.deep }}>{t.footerDesc}</p>
            <div className="mt-3 text-xs opacity-45" style={{ color: C.deep }}>{t.footerEmail}</div>
          </div>
          {[
            { title: t.footerService, links: t.footerServiceLinks },
            { title: t.footerLegal,   links: t.footerLegalLinks },
          ].map(({ title, links }) => (
            <div key={title}>
              <h5 className="font-semibold text-sm mb-4" style={{ color: C.deep }}>{title}</h5>
              <ul className="space-y-2.5">
                {links.map(link => (
                  <li key={link}><a href="#" className="text-sm transition-opacity hover:opacity-100" style={{ color: C.deep, opacity: 0.55 }}>{link}</a></li>
                ))}
              </ul>
            </div>
          ))}
        </div>
        <div className="pt-6 border-t flex flex-col sm:flex-row justify-between items-center gap-3" style={{ borderColor: C.border1 }}>
          <p className="text-xs opacity-40" style={{ color: C.deep }}>{t.footerCopy}</p>
          <p className="text-xs opacity-40" style={{ color: C.deep }}>{t.footerMade}</p>
        </div>
      </div>
    </footer>
  );
}

/* ─── Root ─────────────────────────────────────────────────────────── */
export default function App() {
  const [lang, setLang] = useState<Lang>("ko");
  const t = T[lang];

  return (
    <LangCtx.Provider value={{ lang, t }}>
      <div
        className="min-h-screen overflow-x-hidden bg-background text-foreground"
        style={{ fontFamily: APPLE }}
      >
        <Nav lang={lang} setLang={setLang} />
        <HeroSection />
        <PainSection />
        <HowSection />
        <ShowcaseSection />
        <ImpactSection />
        <FaqSection />
        <DownloadSection />
        <Footer />
      </div>
    </LangCtx.Provider>
  );
}
