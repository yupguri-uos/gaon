"""
GAON AI — 실 Embedder: KURE self-host (F-CORE-2)

nlpai-lab/KURE-v1(고려대 NLP&AI Lab)을 sentence-transformers로 in-process 로드한다(외부 API 없음).
- dim=1024 고정(SSOT §15: kb_embeddings vector(1024)) — 로드 직후 검증, 불일치 시 즉시 실패.
- normalize_embeddings=True → 단위벡터. pgvector cosine(<=>) 검색과 정합.
- encode(sync·연산 무거움)는 asyncio.to_thread로 감싸 이벤트 루프를 막지 않는다.

무거운 의존성(sentence-transformers/torch)은 __init__에서 지연 임포트한다.
설치: `pip install -e "ai[rag]"`.
"""

from __future__ import annotations

import asyncio
import os

DEFAULT_MODEL = "nlpai-lab/KURE-v1"
EXPECTED_DIM = 1024  # SSOT §15: kb_embeddings.embedding = vector(1024)


class KureEmbedder:
    """Embedder Protocol 실구현. 모델 로드는 생성 시 1회 — 무거우니 프로세스당 1개를 재사용한다."""

    dim: int

    def __init__(self, model_name: str | None = None, device: str | None = None) -> None:
        try:
            from sentence_transformers import SentenceTransformer
        except ImportError as exc:  # pragma: no cover - 의존성 미설치 환경 안내용
            raise ImportError(
                'KureEmbedder에는 sentence-transformers가 필요하다: pip install -e "ai[rag]"'
            ) from exc

        model_name = model_name or os.getenv("EMBEDDING_MODEL") or DEFAULT_MODEL
        # device 미지정(None)이면 sentence-transformers가 cuda/mps/cpu를 자동 선택한다.
        device = device or os.getenv("EMBEDDING_DEVICE") or None
        self._model = SentenceTransformer(model_name, device=device)

        dim = self._model.get_sentence_embedding_dimension()
        if dim != EXPECTED_DIM:
            raise ValueError(
                f"임베딩 차원 불일치: {model_name} dim={dim}, "
                f"kb_embeddings는 vector({EXPECTED_DIM}) 고정(SSOT §15)"
            )
        self.dim = dim

    async def embed(self, texts: list[str]) -> list[list[float]]:
        if not texts:
            return []
        return await asyncio.to_thread(self._encode, texts)

    def _encode(self, texts: list[str]) -> list[list[float]]:
        vectors = self._model.encode(texts, normalize_embeddings=True)
        return [vector.tolist() for vector in vectors]
