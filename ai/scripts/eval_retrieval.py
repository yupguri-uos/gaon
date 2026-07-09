"""
retrieval 평가 러너 — 골드 질의로 hit@k(3·5) 측정 (F-CORE-2, 수동 스크립트 · pytest 아님).

실 KURE + 실 pgvector가 필요하다(코퍼스는 ingest_corpus.py로 먼저 적재).
hit 기준: top-k 안에 expected_source 청크가 있고, expected_term이 주어졌으면
그 청크의 title까지 일치해야 한다.

실행법:
    set -a; source .env; set +a && python ai/scripts/eval_retrieval.py
"""

from __future__ import annotations

import argparse
import asyncio
import sys
from pathlib import Path

from gaon_ai.corpus import GoldItem, load_gold
from gaon_ai.embedders.kure import KureEmbedder
from gaon_ai.rag import HybridRetriever, RetrievedChunk
from gaon_ai.stores.pgvector import PgVectorKbStore

DEFAULT_GOLD = Path(__file__).resolve().parents[2] / "data" / "evalset" / "retrieval_gold.jsonl"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="retrieval hit@k 평가(실 KURE+DB)")
    parser.add_argument(
        "--gold", type=Path, default=DEFAULT_GOLD, help=f"골드 jsonl(기본 {DEFAULT_GOLD})"
    )
    return parser.parse_args()


def is_hit(chunks: list[RetrievedChunk], item: GoldItem) -> bool:
    return any(
        chunk.source == item.expected_source
        and (item.expected_term is None or chunk.title == item.expected_term)
        for chunk in chunks
    )


async def main() -> int:
    args = parse_args()
    items = load_gold(args.gold)
    print(f"골드 {len(items)}건 로드: {args.gold}")

    embedder = KureEmbedder()
    store = PgVectorKbStore.from_database_url()
    retriever = HybridRetriever(embedder, store, use_sparse=False)  # v1 dense-only
    hits3 = hits5 = 0
    misses: list[tuple[GoldItem, list[RetrievedChunk]]] = []
    try:
        for item in items:
            chunks = await retriever.retrieve([item.query], top_k=5)
            if is_hit(chunks[:3], item):
                hits3 += 1
            if is_hit(chunks[:5], item):
                hits5 += 1
            else:
                misses.append((item, chunks))
    finally:
        await store.close()

    total = len(items)
    print(f"\nhit@3 = {hits3}/{total} ({hits3 / total:.0%})")
    print(f"hit@5 = {hits5}/{total} ({hits5 / total:.0%})")
    if misses:
        print(f"\n미스(top-5 밖) {len(misses)}건:")
        for item, chunks in misses:
            got = [f"{chunk.title}({chunk.score:.2f})" for chunk in chunks]
            print(f"  - '{item.query}' → 기대 {item.expected_term or item.expected_source}")
            print(f"    top-5: {got or '(결과 없음)'}")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
