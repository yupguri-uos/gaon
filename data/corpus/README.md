# GAON RAG 코퍼스 (F-CORE-2, 코퍼스 큐레이션 계획 a)

도메인 = 초등 저학년 학교생활. KB 본문은 전부 한국어(KURE 1024, 한국어→한국어 검색).

- `class_a/` — 가정통신문 표준안(notice/consent/survey). 공공누리(KOGL) 제1유형 개별 확인분만 — 확인은 사람 몫.
- `class_b/` — 학교 용어·관행 glossary. 독립 자체작성(국립국어원 CC BY-SA 사전 배제·패러프레이즈 금지).
- `class_c/` — 제도·가이드라인(policy). KOGL 제1유형 개별 확인분만.

클래스별 `manifest.json`이 수집 감사 추적의 유일한 근거다(라이선스는 per-chunk 저장 안 함).
항목 스키마: `{file, title, url, retrieved_at, license, kogl_type, source_org, doc_type, source}`
— `source`는 kb_embeddings.source로 들어가는 출처 식별자(KOGL 출처표시 문자열 근원).
계약 정본: `ai/gaon_ai/corpus.py`. v1은 txt/md만 지원(PDF는 사람이 txt로 정제해 투입).

적재: `python ai/scripts/ingest_corpus.py` (검증·청킹 통계만: `--dry-run`)
