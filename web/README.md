# GAON 웹 랜딩 페이지

서비스 소개용 마케팅 원페이지 (React + Vite, Figma Make export 기반).
앱(`/fe`)과 별개의 정적 사이트 — BE 의존성 없음.

- 다국어: ko / en / vi / zh (클라이언트 토글)
- 원본 시안: [Figma — Web Landing Page Design](https://www.figma.com/design/oUUHeZafDehzlcOtGjvsjb/Web-Landing-Page-Design)

## 실행

```bash
npm i          # 의존성 설치
npm run dev    # 개발 서버 (기본 http://localhost:5173)
npm run build  # 정적 빌드 → dist/
```

## 배포

- 공개 경로: **https://gaon.uk/landing/** (Cloudflare 터널, INF 공지 2026-07-08)
- base 경로 `/landing/`은 vite.config.ts에서 빌드 시 자동 적용된다 — 별도 플래그 불필요.
  (base 없이 빌드하면 자산 404로 흰 화면이 되므로 config에 고정해 둠)
- `npm run build` → `dist/`를 미니PC nginx에 적재. 배포 스크립트 연동은 `/infra` 참조.

## 알려진 placeholder

- 소개 수치("20,000+ 다문화 가정 · 15+ 언어 · 98% 만족도")는 데모용 임의값 —
  본선/공개 전 실측 또는 근거 있는 수치로 교체 예정 (팀 공유됨, 2026-07-08).
