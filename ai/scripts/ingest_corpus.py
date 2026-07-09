"""
코퍼스 인제스트 CLI — data/corpus → kb_embeddings (F-CORE-2, 오프라인 배치 · 수동 스크립트).

BE 런타임(chain_deps)과 무관하게 DATABASE_URL로 자체 psycopg async 풀을 만든다.
클래스 디렉토리(class_a/b/c)를 순회해 매니페스트 검증 → 섹션 인식 청킹(§17.9) →
KURE 임베딩 → ingest(replace_source=True)(고아 청크 방지)로 적재한다.

실 인제스트(KURE 모델·DB 필요, `pip install -e "ai[rag]"`):
    set -a; source .env; set +a && python ai/scripts/ingest_corpus.py

매니페스트 검증 + 청킹 통계만(임베딩·DB 불필요):
    python ai/scripts/ingest_corpus.py --dry-run
"""

from __future__ import annotations

import argparse
import asyncio
import sys
from pathlib import Path
from time import perf_counter

from gaon_ai.corpus import CORPUS_CLASS_DIRS, manifest_to_docs
from gaon_ai.ingest import (
    Chunk,
    SentenceSplitter,
    SourceDoc,
    chunk_document_sectioned,
    ingest,
    kss_splitter,
    simple_splitter,
)

DEFAULT_CORPUS_DIR = Path(__file__).resolve().parents[2] / "data" / "corpus"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="코퍼스 인제스트(F-CORE-2, 오프라인 배치)")
    parser.add_argument(
        "--corpus-dir",
        type=Path,
        default=DEFAULT_CORPUS_DIR,
        help=f"코퍼스 루트(기본 {DEFAULT_CORPUS_DIR})",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="임베딩·DB 없이 매니페스트 검증 + 청킹 통계(청크 수·section 충전률)만 출력",
    )
    return parser.parse_args()


def resolve_splitter() -> SentenceSplitter:
    """kss(rag extra) 우선, 미설치면 simple_splitter 폴백(경고 출력)."""
    try:
        import kss  # noqa: F401
    except ImportError:
        print(
            '⚠️  kss 미설치 — simple_splitter 폴백(문장 분할 품질 저하). pip install -e "ai[rag]"'
        )
        return simple_splitter
    return kss_splitter


def chunk_stats(
    docs: list[SourceDoc], splitter: SentenceSplitter
) -> tuple[list[Chunk], dict[str, int], float]:
    """섹션 인식 청킹 → (청크, source별 청크 수, section 충전률)."""
    chunks: list[Chunk] = []
    for doc in docs:
        chunks.extend(chunk_document_sectioned(doc, splitter=splitter))
    per_source: dict[str, int] = {}
    for chunk in chunks:
        per_source[chunk.source] = per_source.get(chunk.source, 0) + 1
    filled = sum(1 for chunk in chunks if chunk.section)
    fill_rate = filled / len(chunks) if chunks else 0.0
    return chunks, per_source, fill_rate


def print_stats(name: str, docs: list[SourceDoc], per_source: dict[str, int], fill_rate: float):
    total = sum(per_source.values())
    print(f"\n[{name}] 문서 {len(docs)}건 → 청크 {total}건, section 충전률 {fill_rate:.0%}")
    for source, count in sorted(per_source.items()):
        print(f"  - {source}: {count}청크")


async def main() -> int:
    args = parse_args()
    splitter = resolve_splitter()

    # 매니페스트 검증(누락 키·미지원 확장자·없는 파일은 여기서 명시 에러)
    class_docs: list[tuple[str, list[SourceDoc]]] = []
    for name in CORPUS_CLASS_DIRS:
        docs = manifest_to_docs(args.corpus_dir / name)
        class_docs.append((name, docs))
        print(
            f"{name}: 매니페스트 검증 통과 — 문서 {len(docs)}건"
            + ("(수집 대기)" if not docs else "")
        )

    if args.dry_run:
        for name, docs in class_docs:
            if not docs:
                continue
            _, per_source, fill_rate = chunk_stats(docs, splitter)
            print_stats(name, docs, per_source, fill_rate)
        print("\n✅ dry-run 완료(임베딩·DB 미접속)")
        return 0

    # 실 적재 — 무거운 의존성은 여기서만 임포트(rag extra)
    from gaon_ai.embedders.kure import KureEmbedder
    from gaon_ai.stores.pgvector import PgVectorKbStore

    print("\nKURE 임베더 로드 중(최초 실행은 모델 다운로드로 오래 걸릴 수 있음)…")
    embedder = KureEmbedder()
    store = PgVectorKbStore.from_database_url()
    try:
        for name, docs in class_docs:
            if not docs:
                print(f"\n[{name}] 문서 0건 — 건너뜀(수집 대기)")
                continue
            _, per_source, fill_rate = chunk_stats(docs, splitter)
            started = perf_counter()
            upserted = await ingest(
                docs,
                embedder=embedder,
                store=store,
                chunker=lambda doc: chunk_document_sectioned(doc, splitter=splitter),
                replace_source=True,  # 고아 청크 방지(§17.9)
            )
            elapsed = perf_counter() - started
            print_stats(name, docs, per_source, fill_rate)
            print(f"  업서트 {upserted}건, 소요 {elapsed:.1f}s")
    finally:
        await store.close()
    print("\n✅ 인제스트 완료")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
