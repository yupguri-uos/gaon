"""GAON AI — 에이전트 4종 + RAG. Chain A 핵심(파싱→번역) 우선 구현.

주입 지점:
    run_chain_a_core(document, user, llm=<LLMClient>, retriever=<Retriever>, on_status=...)
실제 LLMClient/Retriever 구현체는 결정 #4(SKU)·DB 셋업 후 추가한다.
"""

from gaon_ai.agents import (
    Agent,
    CulturalTranslationAgent,
    DocumentParsingAgent,
    LifestyleActionAgent,
)
from gaon_ai.chain_a import ChainAResult, ChainError, run_chain_a_core
from gaon_ai.llm import LLMClient, ModelTier
from gaon_ai.rag import Retriever, RetrievedChunk, build_rag_queries

__all__ = [
    "Agent",
    "DocumentParsingAgent",
    "CulturalTranslationAgent",
    "LifestyleActionAgent",
    "run_chain_a_core",
    "ChainAResult",
    "ChainError",
    "LLMClient",
    "ModelTier",
    "Retriever",
    "RetrievedChunk",
    "build_rag_queries",
]
__version__ = "0.1.0"
