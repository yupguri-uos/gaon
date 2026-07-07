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

정적 빌드 결과물(`dist/`)을 미니PC nginx 또는 임의의 정적 호스팅에 올리면 된다.
배포 스크립트 연동은 `/infra` 참조.
