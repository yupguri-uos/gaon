"""
image_ref → (bytes, mime) 공용 로더 (§4.1).

두 벤더 클라이언트가 반드시 이 로더 하나를 공유한다 — 이미지 전처리 차이가
벤더 비교를 오염시키면 안 되므로 리사이즈·압축 등 어떤 전처리도 하지 않는다.
"""

from __future__ import annotations

import os
from pathlib import Path

_MIME_BY_EXT = {
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".png": "image/png",
    ".webp": "image/webp",
}

_MINIO_PREFIX = "minio://"


def load_image(image_ref: str) -> tuple[bytes, str]:
    """image_ref(로컬 경로 또는 minio://{bucket}/{key})를 (bytes, mime)로 해석한다."""
    if image_ref.startswith(_MINIO_PREFIX):
        return _load_from_minio(image_ref)
    path = Path(image_ref)
    mime = _mime_for(path.suffix)  # 미지원 확장자는 파일을 읽기 전에 실패
    return path.read_bytes(), mime


def _mime_for(suffix: str) -> str:
    mime = _MIME_BY_EXT.get(suffix.lower())
    if mime is None:
        raise ValueError(f"지원하지 않는 이미지 확장자: {suffix!r} (jpg/jpeg/png/webp만 지원)")
    return mime


def _load_from_minio(image_ref: str) -> tuple[bytes, str]:
    # minio SDK는 minio:// 참조를 실제로 쓸 때만 필요 — 로컬 파일만 쓰는 환경에선 미설치여도 동작.
    from minio import Minio

    rest = image_ref[len(_MINIO_PREFIX) :]
    bucket, _, key = rest.partition("/")
    if not bucket or not key:
        raise ValueError(f"잘못된 minio 참조: {image_ref!r} (minio://{{bucket}}/{{key}} 형식)")
    client = Minio(
        os.environ["MINIO_ENDPOINT"],
        access_key=os.environ["MINIO_ACCESS_KEY"],
        secret_key=os.environ["MINIO_SECRET_KEY"],
        secure=os.environ.get("MINIO_SECURE", "false").lower() == "true",
    )
    response = client.get_object(bucket, key)
    try:
        data = response.read()
    finally:
        response.close()
        response.release_conn()
    return data, _mime_for(Path(key).suffix)
