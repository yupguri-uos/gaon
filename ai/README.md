# ai — 에이전트 4종 + RAG

문서 체인(A)과 교사소통(B)을 구동하는 에이전트 파이프라인.

- **에이전트 I/O 명세**: 노션 SSOT 8절. shared-schema(`../shared`)대로.
- **에이전트**: ① Document Parsing(이미지→구조화) ② Cultural Translation(+RAG) ③ Lifestyle Action(행동카드) ④ Teacher Communication(경어체)
- **모델**: 멀티모달 LLM 단일 호출, 한 모델 패밀리 (결정 #4 — API 셋업 시 SKU 확정)
- **RAG**: 교육 용어·관행·가이드라인 → `kb_embeddings`(pgvector, hnsw cosine). 기능 F-CORE-2.

## 설치
`gaon-ai`는 `gaon-shared`에 의존한다. 루트에서 순서대로:
`pip install -e shared/python && pip install -e "ai[dev]"` (자세한 건 루트 README).