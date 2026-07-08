/// BE 공개 엔드포인트 설정 (INF 공지 2026-07-08).
///
/// - 공개 URL: https://gaon.uk (Cloudflare 터널 + 자동 HTTPS)
/// - nginx가 `/api` 프리픽스를 벗겨 미니PC FastAPI로 전달
///   (예: /api/documents → FastAPI의 /documents)
/// - ApiRepository 구현 시 반드시 이 base를 사용한다.
/// - 로컬 BE로 붙일 땐 빌드 시 오버라이드:
///   flutter run --dart-define=GAON_API_BASE=http://localhost:8000
const gaonApiBase = String.fromEnvironment(
  'GAON_API_BASE',
  defaultValue: 'https://gaon.uk/api',
);
