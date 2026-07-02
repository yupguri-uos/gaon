"""환경설정. .env는 모노레포 루트 하나를 공유한다(README 셋업 참조)."""

from __future__ import annotations

from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict

_ROOT_ENV_FILE = Path(__file__).resolve().parents[2] / ".env"


class Settings(BaseSettings):
    app_env: str = "development"
    session_secret: str = "change-me"
    database_url: str = "postgresql://gaon:password@localhost:5432/gaon"

    kakao_rest_api_key: str = ""
    kakao_redirect_uri: str = ""

    s3_endpoint: str = "http://localhost:9000"
    s3_access_key: str = ""
    s3_secret_key: str = ""
    s3_bucket: str = "gaon-documents"

    model_config = SettingsConfigDict(
        env_file=_ROOT_ENV_FILE, env_file_encoding="utf-8", extra="ignore"
    )


settings = Settings()
