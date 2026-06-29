"""GAON shared-schema (Python 정본). SSOT §7·§8, §17.4 반영.

사용 예:
    from gaon_shared import ExtractedItem, CulturalTranslationInput, AgentResponse
"""

from .schema import (
    # 값 타입
    OriginCountry,
    NativeLanguage,
    ChildGrade,
    DocStatus,
    DocType,
    CalendarEventType,
    MessageSituation,
    NotificationType,
    # 사용자
    User,
    Child,
    # 문서 / 파싱
    Document,
    DateItem,
    AmountItem,
    Checkbox,
    ExtractedItem,
    # 번역 / 행동
    Term,
    TranslatedContent,
    Supply,
    CalendarEvent,
    ActionCard,
    # 교사 / 알림 / 로그
    TeacherMessage,
    Notification,
    WeeklyActivity,
    ActivityLog,
    # 에이전트 I/O 계약
    DocParsingInput,
    CulturalTranslationInput,
    LifestyleActionInput,
    ChildInfo,
    TeacherCommInput,
    # 봉투
    AgentResponse,
)

__version__ = "0.1.0"
