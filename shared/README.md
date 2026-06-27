# shared — shared-schema (단일 출처)

FE·BE·AI가 주고받는 모든 I/O 타입의 **단일 출처**. 여기 타입을 어기는 ad-hoc dict 교환 금지.

- **정의**: 노션 SSOT 7절
- **변경 순서**: 노션 SSOT → `shared` → 각 코드. 코드에서 필드 임의 추가 금지.
- **핵심 타입**: UserProfile, Document, ExtractedItem, TranslatedContent, ActionCard, TeacherMessage, Notification, ActivityLog, `AgentResponse<T>`

> BE는 Pydantic, FE는 Dart 모델로 이 타입을 1:1 반영한다.