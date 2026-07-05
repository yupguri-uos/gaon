-- 최초 DB 초기화 시 1회 실행 (/docker-entrypoint-initdb.d).
-- Alembic 마이그레이션이 vector 컬럼을 쓰기 전에 확장이 있어야 함.
CREATE EXTENSION IF NOT EXISTS vector;
