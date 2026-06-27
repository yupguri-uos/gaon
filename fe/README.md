# fe — Flutter 앱

GAON 프론트엔드. 로그인 + 7화면, 다국어(ko 병기 + vi/zh).

- **화면 명세**: 노션 SSOT 13절
- **인터페이스**: shared-schema(`../shared`)대로. BE API는 SSOT 11절.
- **워크플로우**: Figma Make → React 코드 → LLM으로 Flutter 변환 → shared-schema에 맞춰 보정
- **랜딩페이지**(포함·실배포): 서비스 소개 + 시연

> 곧 `flutter create`가 이 폴더를 실제 앱으로 채운다. 스택별 규칙이 쌓이면 `fe/CLAUDE.md` 추가.