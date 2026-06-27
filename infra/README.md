# infra — 배포 · 네트워크 · DB

미니PC 기반 배포. 자세한 운영 노트는 노션 "개발" 페이지 인프라 섹션.

- **위치/운영**: 미니PC = 이태권 집 → 손수빈 100% 원격, 이태권 remote hands
- **네트워크**: 팀 접속 = Tailscale(비공개) / 공개 백엔드 = Cloudflare Tunnel. 둘 다 아웃바운드(포트포워딩 불필요).
- **스토리지/DB**: 이미지 MinIO(S3 호환), PostgreSQL + pgvector, 마이그레이션 Alembic
- **푸시**: FCM
- **자동복구**: 백엔드·DB·Tailscale·cloudflared 전부 systemd 자동기동 + BIOS 정전 후 자동부팅

> 시크릿은 `.env`(커밋 금지) / `.env.example` 템플릿 참조. 배포 스크립트·설정파일은 이 폴더.