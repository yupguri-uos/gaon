"""F-CORE-2 코퍼스 파이프라인 검증(계획 a) — 실 임베딩·DB 없이 fake로.

섹션 인식 청커의 section 충전(§17.9), 매니페스트 로더(필수 키 누락 시 명시 에러),
repo 실데이터(class_b glossary·retrieval 골드)의 스키마 정합.
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from gaon_ai.corpus import load_gold, load_manifest, manifest_to_docs
from gaon_ai.ingest import (
    SourceDoc,
    chunk_document,
    chunk_document_sectioned,
    ingest,
    split_sections,
)
from gaon_ai.testing import FakeEmbedder, FakeKbStore

REPO_ROOT = Path(__file__).resolve().parents[2]
CLASS_B_DIR = REPO_ROOT / "data" / "corpus" / "class_b"
GOLD_PATH = REPO_ROOT / "data" / "evalset" / "retrieval_gold.jsonl"

VALID_ENTRY = {
    "file": "용어.md",
    "title": "용어",
    "url": None,
    "retrieved_at": "2026-07-10",
    "license": "자체작성",
    "kogl_type": None,
    "source_org": "GAON",
    "doc_type": "glossary",
    "source": "gaon-glossary-v1",
}


def _doc(text: str) -> SourceDoc:
    return SourceDoc(source="src", title="문서", doc_type="glossary", text=text)


# ── 섹션 인식 청커(§17.9 section 충전) ──────────────────────────────────────
def test_split_sections_recognizes_header_styles():
    text = (
        "머리말 본문입니다.\n"
        "# 마크다운 제목\n첫 섹션 본문입니다.\n"
        "■ 기호 제목\n둘째 섹션 본문입니다.\n"
        "[대괄호 제목]\n셋째 섹션 본문입니다.\n"
        "1. 번호 제목\n넷째 섹션 본문입니다.\n"
    )
    sections = split_sections(text)
    assert [title for title, _ in sections] == [
        None,  # 첫 헤더 이전 머리말
        "마크다운 제목",
        "기호 제목",
        "대괄호 제목",
        "번호 제목",
    ]
    assert all(body.strip() for _, body in sections)


def test_split_sections_numbered_sentence_is_body():
    # 종결부호로 끝나는 번호 줄(예: 안내문 목록 문장)은 헤더가 아니라 본문
    text = "■ 준비물\n1. 도시락을 챙겨 주세요.\n2. 물통도 챙겨 주세요.\n"
    sections = split_sections(text)
    assert len(sections) == 1
    title, body = sections[0]
    assert title == "준비물"
    assert "도시락" in body and "물통" in body


def test_split_sections_long_line_is_body():
    long_line = "1. " + "가" * 60  # _MAX_HEADER_CHARS 초과 → 본문 취급
    sections = split_sections(f"# 제목\n{long_line}\n")
    assert len(sections) == 1
    assert sections[0][0] == "제목"


def test_chunk_document_sectioned_fills_section():
    doc = _doc("# 첫 섹션\n첫 본문입니다.\n# 둘째 섹션\n둘째 본문입니다.")
    chunks = chunk_document_sectioned(doc)
    assert {chunk.section for chunk in chunks} == {"첫 섹션", "둘째 섹션"}
    for chunk in chunks:  # 기존 프로비넌스·멱등키 계약 유지
        assert chunk.source == "src"
        assert chunk.content_hash


def test_chunk_document_sectioned_without_headers_matches_plain():
    doc = _doc("첫째 문장입니다. 둘째 문장입니다. 셋째 문장입니다.")
    sectioned = chunk_document_sectioned(doc)
    plain = chunk_document(doc)
    assert [chunk.content for chunk in sectioned] == [chunk.content for chunk in plain]
    assert all(chunk.section is None for chunk in sectioned)


async def test_ingest_with_chunker_stores_section():
    store = FakeKbStore()
    docs = [_doc("# 섹션 제목\n섹션 본문 문장입니다.")]
    upserted = await ingest(
        docs, embedder=FakeEmbedder(dim=32), store=store, chunker=chunk_document_sectioned
    )
    assert upserted > 0
    assert all(chunk.section == "섹션 제목" for chunk in store._store.values())


# ── 매니페스트 로더 ─────────────────────────────────────────────────────────
def _write_manifest(tmp_path: Path, entries: list[dict]) -> Path:
    (tmp_path / "manifest.json").write_text(json.dumps(entries, ensure_ascii=False))
    return tmp_path


def test_load_manifest_valid(tmp_path: Path):
    _write_manifest(tmp_path, [VALID_ENTRY])
    entries = load_manifest(tmp_path)
    assert len(entries) == 1
    assert entries[0].source == "gaon-glossary-v1"
    assert entries[0].doc_type == "glossary"


def test_load_manifest_missing_key_is_explicit_error(tmp_path: Path):
    broken = {key: value for key, value in VALID_ENTRY.items() if key != "license"}
    _write_manifest(tmp_path, [broken])
    with pytest.raises(ValueError, match="manifest.json"):
        load_manifest(tmp_path)


def test_load_manifest_bad_doc_type(tmp_path: Path):
    _write_manifest(tmp_path, [{**VALID_ENTRY, "doc_type": "diary"}])
    with pytest.raises(ValueError, match="검증 실패"):
        load_manifest(tmp_path)


def test_load_manifest_missing_file(tmp_path: Path):
    with pytest.raises(FileNotFoundError):
        load_manifest(tmp_path)


def test_manifest_to_docs_rejects_unsupported_suffix(tmp_path: Path):
    _write_manifest(tmp_path, [{**VALID_ENTRY, "file": "문서.pdf"}])
    with pytest.raises(ValueError, match="txt/md"):
        manifest_to_docs(tmp_path)


def test_manifest_to_docs_missing_body_file(tmp_path: Path):
    _write_manifest(tmp_path, [VALID_ENTRY])  # 용어.md 미작성
    with pytest.raises(FileNotFoundError):
        manifest_to_docs(tmp_path)


def test_manifest_to_docs_builds_source_docs(tmp_path: Path):
    _write_manifest(tmp_path, [VALID_ENTRY])
    (tmp_path / "용어.md").write_text("# 용어\n본문입니다.", encoding="utf-8")
    [doc] = manifest_to_docs(tmp_path)
    assert doc.source == "gaon-glossary-v1"
    assert doc.title == "용어"
    assert doc.doc_type == "glossary"
    assert "본문" in doc.text


# ── repo 실데이터 정합(class_b glossary 배치 1 · 평가셋 골드) ────────────────
def test_class_b_manifest_and_files():
    entries = load_manifest(CLASS_B_DIR)
    assert len(entries) >= 20  # 배치 1 = 25항목 내외
    for entry in entries:
        assert entry.doc_type == "glossary"
        assert entry.license == "자체작성"
        assert entry.source == "gaon-glossary-v1"
        assert (CLASS_B_DIR / entry.file).is_file()


def test_class_b_chunks_fully_sectioned():
    # glossary 카드는 파일마다 '# 용어' 헤더 1개 → section 충전률 100%
    docs = manifest_to_docs(CLASS_B_DIR)
    for doc in docs:
        chunks = chunk_document_sectioned(doc)
        assert chunks, f"{doc.title}: 청크 0건"
        assert all(chunk.section for chunk in chunks), f"{doc.title}: section 미충전"


def test_empty_manifests_for_class_a_and_c():
    for name in ("class_a", "class_c"):
        assert load_manifest(REPO_ROOT / "data" / "corpus" / name) == []


def test_gold_schema_and_terms_exist_in_glossary():
    items = load_gold(GOLD_PATH)
    assert len(items) >= 30
    titles = {entry.title for entry in load_manifest(CLASS_B_DIR)}
    for item in items:
        assert item.query.strip()
        assert item.expected_source
        if item.expected_source == "gaon-glossary-v1" and item.expected_term:
            assert (
                item.expected_term in titles
            ), f"골드 용어가 glossary에 없음: {item.expected_term}"


def test_load_gold_invalid_line_reports_line_number(tmp_path: Path):
    path = tmp_path / "gold.jsonl"
    path.write_text('{"query": "질의", "expected_source": "s"}\n{"query": "누락"}\n')
    with pytest.raises(ValueError, match=":2"):
        load_gold(path)
