"""
GAON AI — RAG 인제스트 파이프라인 (F-CORE-2, 코퍼스 → kb_embeddings)

코퍼스 문서를 청킹 → 임베딩 → KbStore.upsert(멱등)로 적재한다. 실 임베딩(KURE/BGE-M3)·
pgvector 저장은 각각 Embedder·KbStore Protocol(rag.py) 뒤에 있으며 여기서는 무관하다.
멱등키는 content_hash = sha256(source|content) — 재적재·재임베딩이 안전하다.
프로비넌스(source/title/section/doc_type)는 청크마다 보존한다.
"""

from __future__ import annotations

import hashlib
import re
from typing import Callable

from pydantic import BaseModel

from gaon_ai.rag import Embedder, KbStore


class SourceDoc(BaseModel):
    """인제스트 입력(코퍼스 1건). text는 청킹 전 원문."""

    source: str
    title: str | None = None
    url: str | None = None
    doc_type: str | None = None  # notice/consent/survey/general
    text: str


class Chunk(BaseModel):
    """청킹 결과(임베딩 전). 프로비넌스 보존 + 멱등키."""

    content: str
    source: str
    title: str | None = None
    url: str | None = None
    section: str | None = None
    doc_type: str | None = None
    content_hash: str  # sha256(source|content) → 멱등키


class EmbeddedChunk(Chunk):
    """임베딩까지 끝난 청크. KbStore.upsert 입력."""

    embedding: list[float]


SentenceSplitter = Callable[[str], list[str]]  # 기본=정규식, 프로덕션=kss 등 주입

# 문장 경계: 마침표류 뒤 공백 또는 줄바꿈. 프로덕션은 kss로 교체(신규 의존성은 후속).
_SENTENCE_BOUNDARY = re.compile(r"(?<=[.!?。？！])\s+|\n+")


def simple_splitter(text: str) -> list[str]:
    """기본 문장 분할기(정규식). 빈 조각은 버린다."""
    parts = (segment.strip() for segment in _SENTENCE_BOUNDARY.split(text))
    return [segment for segment in parts if segment]


def _content_hash(source: str, content: str) -> str:
    """멱등키: 같은 source·content면 항상 같은 해시."""
    return hashlib.sha256(f"{source}|{content}".encode()).hexdigest()


def _make_chunk(doc: SourceDoc, content: str) -> Chunk:
    return Chunk(
        content=content,
        source=doc.source,
        title=doc.title,
        url=doc.url,
        doc_type=doc.doc_type,
        content_hash=_content_hash(doc.source, content),
    )


def _carry_overlap(sentences: list[str], overlap_chars: int) -> tuple[list[str], int]:
    """직전 청크 꼬리에서 overlap_chars 이상이 되도록 문장을 이어받아 새 버퍼 시작점으로."""
    if overlap_chars <= 0:
        return [], 0
    tail: list[str] = []
    length = 0
    for sentence in reversed(sentences):
        tail.insert(0, sentence)
        length += len(sentence) + 1
        if length >= overlap_chars:
            break
    return tail, length


def chunk_document(
    doc: SourceDoc,
    *,
    splitter: SentenceSplitter = simple_splitter,
    target_chars: int = 500,
    overlap_chars: int = 80,
) -> list[Chunk]:
    """문장 경계 존중 + target_chars 근처로 묶기 + overlap + content_hash.

    문장을 자르지 않고, 버퍼가 target_chars를 넘어서려 하면 확정한 뒤 overlap만큼
    꼬리 문장을 이어받아 다음 버퍼를 시작한다(맥락 연속성 유지).
    """
    sentences = splitter(doc.text)
    if not sentences:
        return []
    chunks: list[Chunk] = []
    buffer: list[str] = []
    buffer_len = 0
    for sentence in sentences:
        if buffer and buffer_len + len(sentence) > target_chars:
            chunks.append(_make_chunk(doc, " ".join(buffer)))
            buffer, buffer_len = _carry_overlap(buffer, overlap_chars)
        buffer.append(sentence)
        buffer_len += len(sentence) + 1
    if buffer:
        chunks.append(_make_chunk(doc, " ".join(buffer)))
    return chunks


async def ingest(
    docs: list[SourceDoc],
    *,
    embedder: Embedder,
    store: KbStore,
    splitter: SentenceSplitter = simple_splitter,
) -> int:
    """docs → 청킹 → 임베딩 → KbStore.upsert(멱등). 반환=업서트 건수."""
    chunks: list[Chunk] = []
    for doc in docs:
        chunks.extend(chunk_document(doc, splitter=splitter))
    if not chunks:
        return 0
    vectors = await embedder.embed([chunk.content for chunk in chunks])
    embedded = [
        EmbeddedChunk(**chunk.model_dump(), embedding=vector)
        for chunk, vector in zip(chunks, vectors)
    ]
    return await store.upsert(embedded)
