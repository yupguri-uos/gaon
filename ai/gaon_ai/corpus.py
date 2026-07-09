"""
GAON AI — 코퍼스 매니페스트 계약 + 로더 (F-CORE-2, 코퍼스 큐레이션 계획 a)

data/corpus/{class_a,class_b,class_c}/manifest.json이 수집 감사 추적의 유일한 근거다
— 라이선스는 per-chunk로 저장하지 않는다(§15 kb_embeddings에 라이선스 컬럼 없음).
로더는 매니페스트를 검증해 ingest 입력(SourceDoc)으로 변환한다.
v1은 txt/md만 지원(PDF 정제는 사람이 txt로 변환해 투입).

평가셋 골드(retrieval_gold.jsonl) 스키마도 여기서 고정한다 — 러너·테스트가 공유.
"""

from __future__ import annotations

import json
from datetime import date
from pathlib import Path
from typing import Literal

from pydantic import BaseModel, ConfigDict, ValidationError

from gaon_ai.ingest import SourceDoc

# 콘텐츠 3클래스: A 가정통신문 표준안 · B 용어·관행 glossary(자체작성) · C 제도·가이드라인
CORPUS_CLASS_DIRS: tuple[str, ...] = ("class_a", "class_b", "class_c")
MANIFEST_NAME = "manifest.json"
SUPPORTED_SUFFIXES: frozenset[str] = frozenset({".txt", ".md"})

# §15 kb_embeddings.doc_type CHECK와 일치 — 매니페스트 값을 그대로 적재한다
CorpusDocType = Literal["notice", "consent", "survey", "policy", "glossary"]


class ManifestEntry(BaseModel):
    """매니페스트 1항목(코퍼스 파일 1건). 모든 키 명시 필수 — 누락은 검증 에러.

    url·kogl_type은 자체작성분에 해당 없음 → null을 '명시'해야 한다(생략 불가,
    감사 추적이 목적이므로 '몰라서 빠짐'과 '해당 없음'을 구분한다).
    """

    model_config = ConfigDict(extra="forbid")

    file: str  # 클래스 디렉토리 기준 상대 경로(txt/md)
    title: str
    url: str | None  # 원문 URL(자체작성이면 null)
    retrieved_at: date  # 수집일(자체작성이면 작성일)
    license: str  # 예: "공공누리 제1유형", "자체작성"
    kogl_type: str | None  # KOGL 유형(예: "제1유형") — 비KOGL이면 null
    source_org: str  # 발행 기관(자체작성이면 "GAON")
    doc_type: CorpusDocType
    source: str  # kb_embeddings.source — KOGL 출처표시 문자열의 근원


def load_manifest(class_dir: Path) -> list[ManifestEntry]:
    """클래스 디렉토리의 manifest.json → 검증된 항목 목록. 빈 목록([]) 허용(수집 대기)."""
    path = class_dir / MANIFEST_NAME
    if not path.is_file():
        raise FileNotFoundError(f"매니페스트가 없다: {path}")
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise ValueError(f"매니페스트 JSON 파싱 실패: {path} — {exc}") from exc
    if not isinstance(raw, list):
        raise ValueError(f"매니페스트는 항목 배열이어야 한다: {path}")
    entries: list[ManifestEntry] = []
    for index, item in enumerate(raw):
        try:
            entries.append(ManifestEntry.model_validate(item))
        except ValidationError as exc:
            raise ValueError(f"매니페스트 항목 검증 실패: {path} [{index}] — {exc}") from exc
    return entries


def manifest_to_docs(
    class_dir: Path, entries: list[ManifestEntry] | None = None
) -> list[SourceDoc]:
    """매니페스트 → SourceDoc 목록(본문 읽기 포함). ingest 입력."""
    if entries is None:
        entries = load_manifest(class_dir)
    docs: list[SourceDoc] = []
    for entry in entries:
        path = class_dir / entry.file
        if path.suffix.lower() not in SUPPORTED_SUFFIXES:
            raise ValueError(f"v1은 txt/md만 지원한다: {path} (PDF는 txt로 정제해 투입)")
        if not path.is_file():
            raise FileNotFoundError(f"매니페스트가 가리키는 파일이 없다: {path}")
        docs.append(
            SourceDoc(
                source=entry.source,
                title=entry.title,
                url=entry.url,
                doc_type=entry.doc_type,
                text=path.read_text(encoding="utf-8"),
            )
        )
    return docs


# ── retrieval 평가셋 골드(data/evalset/retrieval_gold.jsonl) ────────────────
class GoldItem(BaseModel):
    """평가 질의 1건. expected_term은 glossary 카드 title(있으면 title 일치까지 요구)."""

    model_config = ConfigDict(extra="forbid")

    query: str
    expected_source: str  # kb_embeddings.source
    expected_term: str | None = None


def load_gold(path: Path) -> list[GoldItem]:
    """jsonl → 검증된 골드 목록. 스키마 위반은 줄 번호와 함께 명시 에러."""
    if not path.is_file():
        raise FileNotFoundError(f"골드 파일이 없다: {path}")
    items: list[GoldItem] = []
    for line_no, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if not line.strip():
            continue
        try:
            items.append(GoldItem.model_validate_json(line))
        except ValidationError as exc:
            raise ValueError(f"골드 항목 검증 실패: {path}:{line_no} — {exc}") from exc
    return items
