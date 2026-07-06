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

## 판정 규칙 (§7 — 사전 등록, eval/verdict.py)

1. 크리티컬 미스 총합 차 **≤ 1 → 근소 → Gemini 채택**(기결정 규칙)
2. **Claude 채택**: 크리티컬 미스 2개 이상 적음 **그리고** 경어체 블라인드 A/B 열세 아님
3. 개수 무관 탈락: 체계적 실패 — 특정 tag 그룹(2건 이상) 전멸, 또는 환각 날짜/금액 3건 이상
4. 규칙 개정이 필요해 보이면 판정을 바꾸지 않고 '개정 필요' 플래그만(개정 결정은 탕지수)
5. vi(베트남어) 해설 품질은 미검증 리스크 — vi 출력 원문(ab_pairs.md)을 육안 점검

A/B는 블라인드 수동 평가이므로 하네스는 `pending` 상태의 **잠정 판정**만 출력한다.
평가 후 `ab_key.json`을 열어 규칙 2를 사람이 확정한다.

## 테스트 (실 API 없음)

```bash
pytest ai/pilots/llm_sku/tests   # 채점기 회귀 테스트만 — 실 API 호출은 pytest에 넣지 않는다
```
