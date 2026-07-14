"""이미지 객체 스토리지(MinIO/S3 호환, F-DOC-1). image_ref = 버킷 키(§15 documents.image_ref)."""

from __future__ import annotations

import uuid

import boto3
from botocore.config import Config as _BotoConfig

from app.config import settings

# MinIO가 느리거나 죽으면 put/get이 기본 60초 이상 매달려 업스트림 타임아웃(502)이 난다.
# 짧은 타임아웃 + 제한 재시도로 빠르게 명시적 실패(핸들러 500·로그)로 전환한다.
_client = boto3.client(
    "s3",
    endpoint_url=settings.s3_endpoint,
    aws_access_key_id=settings.s3_access_key,
    aws_secret_access_key=settings.s3_secret_key,
    config=_BotoConfig(
        connect_timeout=5,
        read_timeout=15,
        retries={"max_attempts": 2, "mode": "standard"},
    ),
)


def object_key(user_id: str, filename: str) -> str:
    ext = filename.rsplit(".", 1)[-1] if "." in filename else "bin"
    return f"{user_id}/{uuid.uuid4()}.{ext}"


def upload_image(key: str, data: bytes, content_type: str | None) -> None:
    _client.put_object(
        Bucket=settings.s3_bucket,
        Key=key,
        Body=data,
        ContentType=content_type or "application/octet-stream",
    )


def download_image(key: str) -> bytes:
    """버킷 키로 이미지 바이트를 내려받는다 — Chain A LLM 이미지 로더용(chain_deps 참조)."""
    response = _client.get_object(Bucket=settings.s3_bucket, Key=key)
    return response["Body"].read()


def delete_image(key: str) -> None:
    """이미지 오브젝트 삭제 — 회원탈퇴 시 best-effort 정리용(QA A-4).

    실패는 호출자가 삼킨다(계정 삭제가 우선) — 여기서는 예외를 그대로 전파만 한다."""
    _client.delete_object(Bucket=settings.s3_bucket, Key=key)
