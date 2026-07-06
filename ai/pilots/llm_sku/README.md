# LLM SKU 파일럿 — 결정 #4 생성 절반 (Gemini vs Claude)

생성 멀티모달 LLM SKU를 확정하기 위한 미니 구현 2벌 + 평가 하네스.
**실전 프롬프트로 평가한다** — `gaon_ai.agents`의 `DocumentParsingAgent`(파싱)와
`TeacherCommunicationAgent`(경어체)를 그대로 import해 벤더 클라이언트만 주입한다.
우승 벤더의 미니 구현이 이후 실 `LLMClient` 본구현의 뼈대가 된다(승격은 별도 작업).

- 후보: **Gemini**(FAST=Gemini 2.5 Flash / QUALITY=Gemini 3 Pro)
  vs **Claude**(FAST=Claude Haiku 4.5 / QUALITY=Claude Sonnet 4.6). OpenAI 배제(기결정).
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
| `GEMINI_MODEL_FAST` | | `gemini-2.5-flash` | |
| `GEMINI_MODEL_QUALITY` | | `gemini-3-pro` | 정확한 공개 문자열은 실행 전 models.list로 확인(아래) |
| `ANTHROPIC_MODEL_FAST` | | `claude-haiku-4-5` | |
| `ANTHROPIC_MODEL_QUALITY` | | `claude-sonnet-4-6` | |
| `MINIO_ENDPOINT` / `MINIO_ACCESS_KEY` / `MINIO_SECRET_KEY` / `MINIO_SECURE` | minio:// 사용 시 | `MINIO_SECURE`=false | |

Gemini QUALITY 모델 문자열 확인:

```bash
python -c "from google import genai; [print(m.name) for m in genai.Client().models.list()]"
# 다르면: export GEMINI_MODEL_QUALITY=<확인된 문자열>
```

## 실행

```bash
python ai/pilots/llm_sku/run_pilot.py                        # 전체(파싱 + A/B + 판정)
python ai/pilots/llm_sku/run_pilot.py --only-vendor claude   # 한 벤더 스모크
python ai/pilots/llm_sku/run_pilot.py --skip-ab              # 경어체 A/B 생략
```

API 키가 없는 벤더는 경고 후 스킵된다(크래시 없음). 비교 판정·A/B는 두 벤더 모두 필요.

### 산출물 (`results/`)

| 파일 | 내용 |
|---|---|
| `{vendor}/{doc_id}.json` | 파싱 원출력(ExtractedItem) 그대로 — 사후 검증용 원자료 |
| `{vendor}/{doc_id}.error.txt` | 파싱 실패 시 에러 |
| `scores.md` | 문서×필드 채점 매트릭스 + 벤더별 크리티컬 미스 총합 + 수동 검토 원문 |
| `ab_pairs.md` | 경어체 블라인드 A/B 5문항(벤더명 제거, 문항별 무작위 배정) |
| `ab_key.json` | A/B 배정표 — **평가 완료 전에는 열지 말 것** |
| `verdict.md` | 잠정 판정 + 근거 수치 + 재시도·토큰·지연 요약 |

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

## 판정 규칙 (정본: 노션 'AI 모델 조사 — 결정 #4' §11, 2026-07-06 사전 등록 — eval/verdict.py)

- **⓪ 결격 게이트**(벤더 중립, 판정 전 적용). 하나라도 해당하면 그 벤더 탈락:
  - (i) 손글씨 전멸 — manifest tag `handwritten` 문서 전부에서 크리티컬 미스 발생 [자동]
  - (ii) dates·amounts 환각(골드에 없는 값 생성) 합계 3건 이상 [자동]
  - (iii) 존대 오류 — QUALITY 출력에 반말 혼입·비문 존대 [수동 입력]
  - 양쪽 다 탈락 시 **판정 불가** 플래그(사람 에스컬레이션)
- **①** 크리티컬 미스 총합 차 **≥ 2 → 적은 쪽 채택**(벤더 대칭)
- **②** 차 ≤ 1 → 블라인드 A/B **만장일치급 우세**면 그쪽 채택
  (수치화: 무승부 제외 승패가 갈린 항목에서 전승 + 승리 항목 수 ≥ 3)
- **③** 그 외(둘 다 근소/불명확) → **Gemini**

불변: verdict는 판정을 스스로 바꾸지 않는다 — 규칙 개정이 필요해 보이면 '개정 필요'
플래그와 사유만 출력한다(개정 결정은 탕지수). 리포트에는 원자료 전체를 첨부한다.
vi(베트남어) 해설 품질은 미검증 리스크 — ab_pairs.md의 vi 출력 원문을 육안 점검.

### 수동 평가 입력 (results/manual_review.json)

평가자는 `ab_key.json`을 **열지 않는다** — A/B 결과를 A/B 라벨로만 기록하면
verdict가 `ab_key.json`과 조합해 벤더 매핑을 수행한다. 파일이 없으면 `pending`
상태의 잠정 판정만 출력된다.

```json
{
  "politeness_violations": {"gemini": 0, "claude": 0},
  "ab_results": [
    {"item_id": "1", "winner": "A"},
    {"item_id": "2", "winner": "tie"}
  ]
}
```

### 수동 평가 반영 — API 재호출 없이 최종 판정

`run_pilot.py`를 다시 돌리면 API가 재호출되므로, 수동 평가 후에는 verdict를 단독
실행한다. `results/`의 원출력 덤프를 재채점해 §11을 다시 적용한다:

```bash
python ai/pilots/llm_sku/eval/verdict.py            # 기본: results/ + dataset/manifest.json
# → results/verdict_final.md (실행 시 잠정 리포트 results/verdict.md는 보존)
```

## 테스트 (실 API 없음)

```bash
pytest ai/pilots/llm_sku/tests   # 채점기·판정 회귀 테스트 — 실 API 호출은 pytest에 넣지 않는다
```
