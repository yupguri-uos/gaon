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


def kss_splitter(text: str) -> list[str]:
    """kss 문장 분할기(한국어 특화). rag extra 전용 — import는 지연(kure.py 패턴)."""
    try:
        import kss
    except ImportError as exc:  # pragma: no cover - 의존성 미설치 환경 안내용
        raise ImportError('kss_splitter에는 kss가 필요하다: pip install -e "ai[rag]"') from exc
    return [sentence.strip() for sentence in kss.split_sentences(text) if sentence.strip()]


def _content_hash(source: str, content: str) -> str:
    """멱등키: 같은 source·content면 항상 같은 해시."""
    return hashlib.sha256(f"{source}|{content}".encode()).hexdigest()


def _make_chunk(doc: SourceDoc, content: str, section: str | None = None) -> Chunk:
    return Chunk(
        content=content,
        source=doc.source,
        title=doc.title,
        url=doc.url,
        section=section,
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


def _pack_sentences(
    doc: SourceDoc,
    sentences: list[str],
    *,
    section: str | None,
    target_chars: int,
    overlap_chars: int,
) -> list[Chunk]:
    """문장 목록 → 청크(문장 경계 존중 + target_chars 근처 묶기 + overlap)."""
    if not sentences:
        return []
    chunks: list[Chunk] = []
    buffer: list[str] = []
    buffer_len = 0
    for sentence in sentences:
        if buffer and buffer_len + len(sentence) > target_chars:
            chunks.append(_make_chunk(doc, " ".join(buffer), section))
            buffer, buffer_len = _carry_overlap(buffer, overlap_chars)
        buffer.append(sentence)
        buffer_len += len(sentence) + 1
    if buffer:
        chunks.append(_make_chunk(doc, " ".join(buffer), section))
    return chunks


def chunk_document(
    doc: SourceDoc,
    *,
    splitter: SentenceSplitter = simple_splitter,
    target_chars: int = 500,
    overlap_chars: int = 80,
) -> list[Chunk]:
    """문장 경계 존중 + target_chars 근처로 묶기 + overlap + content_hash.

    문장을 자르지 않고, 버퍼가 target_chars를 넘어서려 하면 확정한 뒤 overlap만큼
    꼬리 문장을 이어받아 다음 버퍼를 시작한다(맥락 연속성 유지). section은 채우지 않는다
    — 섹션 충전이 필요하면 chunk_document_sectioned(§17.9).
    """
    return _pack_sentences(
        doc,
        splitter(doc.text),
        section=None,
        target_chars=target_chars,
        overlap_chars=overlap_chars,
    )


# ── 섹션 인식 청킹(§17.9 'section 미충전' 백로그 해소) ──────────────────────
# 헤더로 인정하는 줄: 마크다운 # / 번호(1. · 2)) / 기호(■ 등) / [제목].
# 가정통신문·glossary의 제목 줄 관행 기준 — 본문 문장 오인을 줄이려 길이·종결부호 가드를 둔다.
_HEADER_PATTERNS: tuple[re.Pattern[str], ...] = (
    re.compile(r"^#{1,6}\s+(?P<title>.+)$"),  # 마크다운 헤더
    re.compile(r"^[■□◆◇▶►●]\s*(?P<title>.+)$"),  # 기호 헤더(■ 제목)
    re.compile(r"^\[(?P<title>[^\[\]]+)\]$"),  # [제목]
    re.compile(r"^\d{1,2}[.)]\s+(?P<title>.+)$"),  # 번호 헤더(1. 제목 / 2) 제목)
)
_MAX_HEADER_CHARS = 40  # 이보다 길면 본문 취급(번호 매긴 문단 오인 방지)
_SENTENCE_ENDING = re.compile(r"[.!?。？！]$")  # 종결부호로 끝나면 헤더가 아니라 문장


def _match_header(line: str) -> str | None:
    stripped = line.strip()
    if not stripped or len(stripped) > _MAX_HEADER_CHARS:
        return None
    for pattern in _HEADER_PATTERNS:
        matched = pattern.match(stripped)
        if matched:
            title = matched.group("title").strip()
            if _SENTENCE_ENDING.search(title):  # 예: "1. 도시락을 챙겨 주세요." → 본문
                return None
            return title
    return None


def split_sections(text: str) -> list[tuple[str | None, str]]:
    """헤더 줄 기준으로 (섹션 제목, 본문) 목록으로 나눈다. 첫 헤더 이전 본문은 제목 None."""
    sections: list[tuple[str | None, str]] = []
    title: str | None = None
    buffer: list[str] = []

    def flush() -> None:
        body = "\n".join(buffer)
        if body.strip():
            sections.append((title, body))

    for line in text.splitlines():
        header = _match_header(line)
        if header is not None:
            flush()
            title = header
            buffer = []
        else:
            buffer.append(line)
    flush()
    return sections


def chunk_document_sectioned(
    doc: SourceDoc,
    *,
    splitter: SentenceSplitter = simple_splitter,
    target_chars: int = 500,
    overlap_chars: int = 80,
) -> list[Chunk]:
    """섹션 헤더 인식 청커 — 각 Chunk.section을 충전한다(§17.9).

    헤더가 없는 문서는 chunk_document와 동일하게 동작한다(section=None).
    청크는 섹션 경계를 넘지 않는다(overlap도 섹션 안에서만).
    """
    chunks: list[Chunk] = []
    for section, body in split_sections(doc.text):
        chunks.extend(
            _pack_sentences(
                doc,
                splitter(body),
                section=section,
                target_chars=target_chars,
                overlap_chars=overlap_chars,
            )
        )
    return chunks


DocChunker = Callable[[SourceDoc], list[Chunk]]  # 문서 → 청크. 섹션 인식 등 청킹 전략 주입점


def embedding_text(chunk: Chunk) -> str:
    """임베딩 입력 전용 텍스트 — title·section 접두(§18.5 보강). 저장 content는 불변.

    섹션 청커가 헤더를 section 필드로 분리하면 임베딩 본문에 용어 자체가 없는 청크가
    생겨 용어-청크 결합이 약해진다(골드 미스 '가정통신문'). title·section을 " — "로 이어
    접두해 결합을 복원한다. content·content_hash는 그대로 두므로 재적재 시
    ON CONFLICT (content_hash) DO UPDATE가 기존 행의 embedding만 교체한다(멱등 유지).
    """
    # title == section이면 한 번만(중복 접두 방지) — dict.fromkeys로 순서 보존 중복 제거
    labels = list(dict.fromkeys(label for label in (chunk.title, chunk.section) if label))
    if not labels:
        return chunk.content
    return " — ".join(labels) + "\n" + chunk.content


async def ingest(
    docs: list[SourceDoc],
    *,
    embedder: Embedder,
    store: KbStore,
    splitter: SentenceSplitter = simple_splitter,
    chunker: DocChunker | None = None,
    replace_source: bool = False,
) -> int:
    """docs → 청킹 → 임베딩 → KbStore.upsert(멱등). 반환=업서트 건수.

    chunker를 주면 그것으로 청킹한다(섹션 충전 등) — 없으면 기존 계약 그대로
    chunk_document(splitter) 폴백. replace_source=True면 적재 전에 배치의 distinct
    source를 모아 delete_by_source로 전부 지운다 — 내용이 줄어든 코퍼스 갱신에서
    남는 고아 청크 방지(§17.9).
    """
    if replace_source:
        for source in dict.fromkeys(doc.source for doc in docs):
            await store.delete_by_source(source)
    chunks: list[Chunk] = []
    for doc in docs:
        chunks.extend(
            chunker(doc) if chunker is not None else chunk_document(doc, splitter=splitter)
        )
    if not chunks:
        return 0
    # 임베딩 입력만 접두(§18.5) — EmbeddedChunk.content에는 원본 content가 그대로 실린다
    vectors = await embedder.embed([embedding_text(chunk) for chunk in chunks])
    embedded = [
        EmbeddedChunk(**chunk.model_dump(), embedding=vector)
        for chunk, vector in zip(chunks, vectors)
    ]
    return await store.upsert(embedded)
