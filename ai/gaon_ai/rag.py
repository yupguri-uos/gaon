"""
GAON AI — RAG 검색 추상화 (F-CORE-2)

§9 체인 규칙: DocParsing 후 'supplies·용어'로 kb_embeddings를 검색해 rag_context를 만들고,
CulturalTranslation 입력에 주입한다. 검색은 '체인 단계'이며, 에이전트는 rag_context를
주어진 것으로 받는다(§8). 임베딩·pgvector(hnsw cosine) 구현은 이 Protocol 뒤에 숨긴다.
"""

from __future__ import annotations

from typing import Protocol, runtime_checkable

from pydantic import BaseModel

from gaon_shared import ExtractedItem


class RetrievedChunk(BaseModel):
    content: str
    source: str | None = None  # 출처(예: 교육부 가이드라인) — kb_embeddings.source
    score: float | None = None  # 코사인 유사도(선택)


@runtime_checkable
class Retriever(Protocol):
    async def retrieve(self, queries: list[str], *, top_k: int = 4) -> list[RetrievedChunk]: ...


def build_rag_queries(extracted: ExtractedItem) -> list[str]:
    """검색 시드(F-CORE-2): 준비물 원문 + 문서 제목. 용어 해설·관행 청크를 끌어오기 위한 질의."""
    queries: list[str] = list(extracted.supplies)
    if extracted.title:
        queries.append(extracted.title)
    return queries


def chunks_to_context(chunks: list[RetrievedChunk]) -> list[str]:
    """CulturalTranslationInput.rag_context(list[str]) 형태로 변환."""
    return [c.content for c in chunks]
