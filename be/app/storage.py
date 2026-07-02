"""이미지 객체 스토리지(MinIO/S3 호환, F-DOC-1). image_ref = 버킷 키(§15 documents.image_ref)."""

from __future__ import annotations

import uuid

import boto3

from app.config import settings

_client = boto3.client(
    "s3",
    endpoint_url=settings.s3_endpoint,
    aws_access_key_id=settings.s3_access_key,
    aws_secret_access_key=settings.s3_secret_key,
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
