# GAON FastAPI(be) 이미지 — 실제 repo 구조(2026-07 확인)에 맞춰 작성.
# build.context = repo 루트 (compose의 build.context: ..)
#
# 확인된 사실:
#   - Python 3.11 (.python-version=3.11.13, be/pyproject requires-python>=3.11)
#   - 패키징 = hatchling (requirements.txt 없음). shared·ai·be 모두 pyproject.
#   - be 의존: gaon-shared, gaon-ai (PyPI 아님) → 설치 순서 shared → ai → be.
#   - DB 드라이버 = psycopg[binary] → libpq/빌드툴 불필요(바이너리 휠에 포함).
#   - 엔트리 app.main:app / alembic.ini(script_location=alembic) / alembic/ 은 be 루트.
#   - alembic env.py는 DATABASE_URL 환경변수로 동작(compose env_file이 주입).
FROM python:3.11-slim

WORKDIR /app

# rag 무거운 의존성 최선행 설치(레이어 캐시) — shared/ai 소스가 바뀌어도 torch 재다운로드 없음.
# (shared-schema가 가장 자주 바뀌므로 반드시 소스 COPY보다 앞에 둔다.)
# 스펙 문자열은 ai/pyproject.toml [rag]와 동일하게 유지할 것(버전 정본은 pyproject) —
# 아래 ai[rag] 설치에서 사전 충족된 휠은 재사용되고 kss만 추가 설치된다.
RUN pip install --no-cache-dir "sentence-transformers>=3" "psycopg[binary,pool]>=3.1"

# 모노레포 내부 의존 패키지 먼저 설치(레이어 캐시). 순서 중요: shared → ai.
COPY shared/python /src/shared
RUN pip install --no-cache-dir /src/shared

COPY ai /src/ai
RUN pip install --no-cache-dir "/src/ai[rag]"

# be 설치 — 위에서 gaon-shared·gaon-ai가 이미 충족되므로 나머지 의존만 PyPI에서 받음.
COPY be /src/be
RUN pip install --no-cache-dir /src/be

# 백엔드 코드를 작업 루트에 배치 (app.main:app, alembic.ini, alembic/ 이 /app 에 오도록)
COPY be/ /app/

EXPOSE 8000
# compose에서 command로 오버라이드(app=uvicorn, migrate=alembic). 기본값만 둔다.
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
