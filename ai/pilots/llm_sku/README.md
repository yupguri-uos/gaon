# LLM SKU 파일럿 — 결정 #4 생성 절반 (Gemini vs Claude)

생성 멀티모달 LLM SKU를 확정하기 위한 미니 구현 2벌 + 평가 하네스.
**실전 프롬프트로 평가한다** — `gaon_ai.agents`의 `DocumentParsingAgent`(파싱)와
`TeacherCommunicationAgent`(경어체)를 그대로 import해 벤더 클라이언트만 주입한다.
우승 벤더의 미니 구현이 이후 실 `LLMClient` 본구현의 뼈대가 된다(승격은 별도 작업).

- 후보(조사 페이지 §11 v2, 2026-07-06 사전등록 — 티어별 판정):
  - **FAST(파싱) 3-way**: `gemini-3-flash-preview`($0.50/$3) · `gemini-3.5-flash`($1.50/$9)
    · Claude Haiku 4.5
  - **QUALITY(경어체 A/B) 2-way**: `gemini-3.1-pro-preview` · Claude Sonnet 4.6
  - OpenAI 배제(기결정). run_pilot은 2벤더 구조 그대로 두고 FAST 3-way는 2회 실행으로 커버.
- 이 디렉토리는 `gaon-ai` 패키지 빌드(`packages=["gaon_ai"]`)에 포함되지 않는다.

## 설치

```bash
# gaon-shared·gaon-ai는 이미 editable 설치돼 있다고 가정 (CLAUDE.md 참조)
pip install -r ai/pilots/llm_sku/requirements.txt
```

`minio`는 `image_ref`가 `minio://`일 때만 지연 import — 로컬 파일만 쓰면 미설치여도 동작.

## 환경변수

| env | 필수 | 기본값 | 비고 |
|---|---|---|---|
| `GOOGLE_API_KEY` (또는 `GEMINI_API_KEY`) | Gemini 실행 시 | — | 없으면 Gemini만 스킵 |
| `ANTHROPIC_API_KEY` | Claude 실행 시 | — | 없으면 Claude만 스킵 |
| `GEMINI_MODEL_FAST` | | `gemini-2.5-flash` | **기본값은 v2 후보가 아님** — 실행 시퀀스대로 run별 지정 |
| `GEMINI_MODEL_QUALITY` | | `gemini-3-pro` | **v2 후보는 `gemini-3.1-pro-preview`** — env 지정, 문자열은 models.list로 확인(아래) |
| `ANTHROPIC_MODEL_FAST` | | `claude-haiku-4-5` | v2 후보와 일치 |
| `ANTHROPIC_MODEL_QUALITY` | | `claude-sonnet-4-6` | v2 후보와 일치 |
| `MINIO_ENDPOINT` / `MINIO_ACCESS_KEY` / `MINIO_SECRET_KEY` / `MINIO_SECURE` | minio:// 사용 시 | `MINIO_SECURE`=false | |

Gemini QUALITY 모델 문자열 확인:

```bash
python -c "from google import genai; [print(m.name) for m in genai.Client().models.list()]"
# 다르면: export GEMINI_MODEL_QUALITY=<확인된 문자열>
```

## 실행 시퀀스 (§11 v2 — run1 → run2 → 블라인드 평가 → manual_review.json → verdict)

```bash
# run1 — 풀 실행: Gemini FAST=3 Flash Preview 파싱 + Claude(Haiku) 파싱
#        + QUALITY A/B(gemini-3.1-pro-preview vs Sonnet 4.6)
GEMINI_MODEL_FAST=gemini-3-flash-preview \
GEMINI_MODEL_QUALITY=gemini-3.1-pro-preview \
python ai/pilots/llm_sku/run_pilot.py --out ai/pilots/llm_sku/results/run1

# run2 — Gemini FAST=3.5 Flash 파싱만(3-way의 세 번째 후보)
GEMINI_MODEL_FAST=gemini-3.5-flash \
python ai/pilots/llm_sku/run_pilot.py --only-vendor gemini --skip-ab \
  --out ai/pilots/llm_sku/results/run2

# 블라인드 평가 — results/run1/ab_pairs.md를 평가하고(ab_key.json 미개봉)
#   results/run1/manual_review.json 작성(아래 '수동 평가 입력' 형식)

# 판정(§11 v2) — API 재호출 없음, 덤프 재채점
python ai/pilots/llm_sku/eval/verdict.py \
  --fast-run ai/pilots/llm_sku/results/run1 \
  --fast-run ai/pilots/llm_sku/results/run2 \
  --ab-run   ai/pilots/llm_sku/results/run1
# → results/run1/verdict_final.md
```

API 키가 없는 벤더는 경고 후 스킵된다(크래시 없음). 각 실행은 실제 사용한 티어별 모델
ID를 `run_meta.json`에 기록한다 — 후보 식별의 전제이므로 env를 바꿔 실행할 때마다
`--out`을 분리할 것.

### 산출물 (run 디렉토리별, 예: `results/run1/`)

| 파일 | 내용 |
|---|---|
| `run_meta.json` | 이 실행이 실제 사용한 티어별 모델 ID(후보 식별 메타데이터) |
| `{vendor}/{doc_id}.json` | 파싱 원출력(ExtractedItem) 그대로 — 사후 검증용 원자료 |
| `{vendor}/{doc_id}.error.txt` | 파싱 실패 시 에러 |
| `scores.md` | 문서×필드 채점 매트릭스 + 벤더별 크리티컬 미스 총합 + 수동 검토 원문 |
| `ab_pairs.md` | 경어체 블라인드 A/B 5문항(벤더명 제거, 문항별 무작위 배정) — run1만 |
| `ab_key.json` | A/B 배정표 — **평가 완료 전에는 열지 말 것** — run1만 |
| `run_report.md` | 실행 리포트(파싱 집계 + 재시도·토큰·지연 요약). 판정은 verdict CLI로 |
| `verdict_final.md` | §11 v2 최종 판정 — verdict CLI 산출(ab-run 디렉토리에 생성) |

## 입력셋 (dataset/manifest.json)

이미지·골드라벨은 탕지수가 수집·투입한다(실제 가정통신문 5~10장, PII 마스킹 완료본).
이미지를 `dataset/images/`에 넣고 `manifest.json`의 `documents`에 항목을 추가하면 된다.
이미지 파일이 없는 문서는 API 호출 없이 스킵된다(채점 제외).

- `received_date`: 문서별 상대날짜 해석 기준일
- `gold.dates`/`gold.amounts`: 값만 채점(라벨 무시)
- `tags`: 실패 유형 분석용(예: `print`, `handwritten`, `table`, `low-res`, `relative-date`)

## 채점 규칙 요약 (§6 — eval/scorer.py)

- `deadline` 정확 일치(null 포함) / `requires_reply` bool 일치 / `doc_type` 일치(참고용)
- `dates`·`amounts`: 값 집합 비교(라벨 무시) + **환각**(골드에 없는 값) 별도 카운트
- `supplies`: 정규화(공백 제거) 후 부분문자열 매칭 — recall/precision 기록(크리티컬 미스 미포함)
- `title`·`raw_text`·`checkboxes`: 자동 채점 제외(scores.md에 원문 병기 — 수동 검토)
- **크리티컬 미스** = deadline 불일치(1) + requires_reply 불일치(1) + dates 누락·환각 각 1 + amounts 동일

## 판정 규칙 (정본: 조사 페이지 §11 v2, 2026-07-06 사전등록 — eval/verdict.py)

- **⓪ 결격**(티어별·후보별, 판정 전 적용):
  - FAST 후보 3개 — (a) 손글씨 전멸: `handwritten` tag 문서 전부에서 크리티컬 미스
    [자동, 태그 0건이면 미발동] / (b) dates·amounts 환각 합계 3건 이상 [자동]
  - QUALITY 후보 2개 — 존대 오류(반말 혼입·비문 존대) [수동, manual_review.json 후보별]
  - **티어의 전 후보 탈락 → 판정 불가**(사람 에스컬레이션)
- **① FAST**: 후보 3개 크리티컬 미스 집계 → 벤더별 최고 후보끼리 차 ≥ 3 = **결정승**
  / ≤ 2 = 근소. Gemini 내부 SKU: 두 SKU 차 ≥ 3이면 승자, ≤ 2이면 **3 Flash**(단가 1/3·무료 티어).
  임계값은 §11 개정(2026-07-06, 입력셋 19장 확정 — 채점 포인트 배증 ~40→~76에 비례해
  구 기준 대비 +1 상향). 단, ⓪의 환각 결격 게이트 **≥ 3은 불변**(비대칭 치명 결함 —
  표본 비례 완화하지 않음).
- **② QUALITY**: 블라인드 A/B **만장일치급**(무승부 제외 승패가 갈린 항목 전승 + 승리
  항목 수 ≥ 3) = **결정승** / 미만 = 근소.
- **③ 조합**: (i) 양측 결정승·동일 벤더 → **단일** / (ii) 양측 결정승·교차 → **혼합** /
  (iii) 편측 결정승 → 근소 티어는 결정승 벤더로 **수렴** / (iv) 양측 근소 → **Gemini 단일**
  (FAST=3 Flash·QUALITY=3.1 Pro — 괄호는 내부 근소 시 기본값, 내부 결정승은 ①이 우선).

최종 출력: **FAST SKU + QUALITY SKU + 구성(단일/혼합) + 적용 경로(i~iv) + 원자료 전체**.
불변: verdict는 판정을 스스로 바꾸지 않는다 — 규칙 개정이 필요해 보이면 '개정 필요'
플래그와 사유만(개정 결정은 탕지수). 수동 입력 부재 시 `pending` 잠정 판정.
vi(베트남어) 해설 품질은 미검증 리스크 — ab_pairs.md의 vi 출력 원문을 육안 점검.

### 수동 평가 입력 (`<ab-run>/manual_review.json`, 예: results/run1/)

평가자는 `ab_key.json`을 **열지 않는다** — A/B 결과를 A/B 라벨로만 기록하면 verdict가
`ab_key.json`과 조합해 벤더 매핑을 수행한다. `politeness_violations`의 키는 벤더명이며
그 벤더의 **QUALITY 후보**를 지칭한다(`gemini`→3.1 Pro Preview, `claude`→Sonnet 4.6).
파일이 없으면 `pending` 잠정 판정만 출력된다.

```json
{
  "politeness_violations": {"gemini": 0, "claude": 0},
  "ab_results": [
    {"item_id": "1", "winner": "A"},
    {"item_id": "2", "winner": "tie"}
  ]
}
```

### 판정 산출 — API 재호출 없이 (verdict CLI)

`run_pilot.py` 재실행은 API를 재호출하므로, 판정은 verdict를 단독 실행해 산출한다.
각 run의 원출력 덤프를 재채점하고 `run_meta.json`으로 후보(SKU)를 식별해 §11 v2를
적용한다. 실행 커맨드는 위 '실행 시퀀스' 참조. 옵션:

- `--fast-run DIR` (반복): FAST 후보를 읽을 run 디렉토리
- `--ab-run DIR`: A/B run 디렉토리(ab_key.json·manual_review.json 위치, 판정 파일 생성처)
- `--manual-review PATH` / `--out PATH` / `--manifest PATH`: 기본값 대체(선택)

## 테스트 (실 API 없음)

```bash
pytest ai/pilots/llm_sku/tests   # 채점기·판정 회귀 테스트 — 실 API 호출은 pytest에 넣지 않는다
```
