"""
LLM SKU 파일럿 하네스 (결정 #4 생성 절반) — 실행 방법은 README.md 참조.

핵심 원칙(§4.3): 실전 프롬프트로 평가한다. 파싱 평가는 gaon_ai.agents.DocumentParsingAgent,
경어체 평가는 TeacherCommunicationAgent를 그대로 import해 벤더 클라이언트를 주입한다
(프롬프트 복사·변형 금지).

사용법:
    python ai/pilots/llm_sku/run_pilot.py [--only-vendor gemini|claude] [--skip-ab]

API 키(GOOGLE_API_KEY 또는 GEMINI_API_KEY / ANTHROPIC_API_KEY)가 없는 벤더는 경고 후
스킵된다 — 한쪽만으로도 스모크 실행 가능하나, 비교 판정과 A/B는 두 벤더가 모두 필요.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import random
import sys
from datetime import date, datetime, timezone
from pathlib import Path
from typing import Any

PILOT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(PILOT_DIR))  # common/·clients/·eval/ 임포트 경로

from gaon_ai.agents import DocumentParsingAgent, TeacherCommunicationAgent  # noqa: E402
from gaon_ai.llm import LLMClient, ModelTier  # noqa: E402
from gaon_shared import DocParsingInput, ExtractedItem, User  # noqa: E402

from eval.ab_fixtures import AB_FIXTURES  # noqa: E402
from eval.scorer import DocScore, score_document  # noqa: E402
from eval.verdict import VendorStats  # noqa: E402

VENDORS = ("gemini", "claude")
INSTALL_HINT = "pip install -r ai/pilots/llm_sku/requirements.txt"


def _dummy_user() -> User:
    # DocParsingInput.user_profile 채우기용 더미(vi 기본, §4.3). 파싱 프롬프트는 미사용 필드.
    return User(
        user_id="pilot-dummy",
        origin_country="VN",
        native_language="vi",
        created_at=datetime(2026, 1, 1, tzinfo=timezone.utc),
    )


def _empty_extracted() -> ExtractedItem:
    # 파싱 실패 문서를 '빈 출력'으로 채점하기 위한 최악 케이스(결정적 필드 전부 미스로 계산)
    return ExtractedItem(doc_type="notice", title="", raw_text="")


def _classify_failure(error: str | None) -> str:
    """실패 계열 분류 — common/retry.py의 PilotCallError 접두 마커 기반(README 신뢰성 정책).

    validation(절단·스키마) ≤2 → 채점 인정 / ≥3 → 계측 결함 재실행 규칙을 계열별로
    적용할 수 있게 run_report에서 컬럼을 분리한다.
    """
    if error:
        if error.startswith("[availability]"):
            return "availability"
        if error.startswith("[validation]"):
            return "validation"
    return "other"


def make_clients(only_vendor: str | None) -> dict[str, Any]:
    """API 키가 설정된 벤더만 생성. 없으면 명확히 경고하고 스킵(§4.2 스모크 지원)."""
    clients: dict[str, Any] = {}
    wanted = [only_vendor] if only_vendor else list(VENDORS)

    if "gemini" in wanted:
        if os.environ.get("GOOGLE_API_KEY") or os.environ.get("GEMINI_API_KEY"):
            try:
                from clients.gemini_client import GeminiLLMClient

                clients["gemini"] = GeminiLLMClient()
            except ImportError as exc:
                print(f"[경고] gemini 스킵 — google-genai 미설치({exc}). {INSTALL_HINT}")
        else:
            print("[경고] gemini 스킵 — GOOGLE_API_KEY(또는 GEMINI_API_KEY) 미설정.")

    if "claude" in wanted:
        if os.environ.get("ANTHROPIC_API_KEY"):
            try:
                from clients.claude_client import AnthropicLLMClient

                clients["claude"] = AnthropicLLMClient()
            except ImportError as exc:
                print(f"[경고] claude 스킵 — anthropic 미설치({exc}). {INSTALL_HINT}")
        else:
            print("[경고] claude 스킵 — ANTHROPIC_API_KEY 미설정.")

    for name, client in clients.items():
        # §4.2: runtime_checkable Protocol 준수 확인
        assert isinstance(client, LLMClient), f"{name} 클라이언트가 LLMClient를 구현하지 않음"
    return clients


# ── 1) 파싱 실행 + 원출력 덤프 ──────────────────────────────────────────────
async def run_parsing(clients: dict[str, Any], docs: list[dict[str, Any]], out_dir: Path) -> tuple[
    dict[str, VendorStats],
    dict[str, dict[str, ExtractedItem | None]],
    dict[str, dict[str, str]],
]:
    user = _dummy_user()
    stats: dict[str, VendorStats] = {}
    outputs: dict[str, dict[str, ExtractedItem | None]] = {}
    failures: dict[str, dict[str, str]] = {}  # vendor → doc_id → 실패 계열(분류는 리포트용)

    # 이미지가 아직 투입되지 않은 문서(§5: 탕지수 투입 예정)는 API 호출 없이 채점에서 제외
    runnable: list[dict[str, Any]] = []
    for doc in docs:
        image_path = (PILOT_DIR / "dataset" / doc["image"]).resolve()
        if image_path.exists():
            runnable.append(doc)
        else:
            print(f"[경고] doc {doc['doc_id']}: 이미지 없음({image_path}) — 스킵(채점 제외).")

    for vendor, client in clients.items():
        agent = DocumentParsingAgent(client, tier=ModelTier.FAST)  # 기본 FAST(§4.3)
        vendor_dir = out_dir / vendor
        vendor_dir.mkdir(parents=True, exist_ok=True)
        doc_scores: list[DocScore] = []
        failed: list[str] = []
        tags_by_doc: dict[str, list[str]] = {}
        outputs[vendor] = {}
        failures[vendor] = {}

        for doc in runnable:
            doc_id = doc["doc_id"]
            tags_by_doc[doc_id] = list(doc.get("tags", []))
            image_path = (PILOT_DIR / "dataset" / doc["image"]).resolve()
            payload = DocParsingInput(
                image_ref=str(image_path),
                user_profile=user,
                received_date=date.fromisoformat(doc["received_date"]),
            )
            resp = await agent.run(payload)
            if resp.status == "ok" and resp.data is not None:
                # 원출력을 그대로 덤프 — 원자료 보존이 사후 검증의 전제(§4.3)
                (vendor_dir / f"{doc_id}.json").write_text(
                    resp.data.model_dump_json(indent=2), encoding="utf-8"
                )
                extracted: ExtractedItem = resp.data
                outputs[vendor][doc_id] = extracted
                print(f"  [{vendor}] doc {doc_id}: OK ({resp.latency_ms}ms)")
            else:
                (vendor_dir / f"{doc_id}.error.txt").write_text(
                    resp.error or "unknown error", encoding="utf-8"
                )
                extracted = _empty_extracted()
                outputs[vendor][doc_id] = None
                failed.append(doc_id)
                kind = _classify_failure(resp.error)
                failures[vendor][doc_id] = kind
                print(f"  [{vendor}] doc {doc_id}: 실패({kind}) — {resp.error}")
            doc_scores.append(score_document(doc_id, extracted, doc["gold"]))

        stats[vendor] = VendorStats(
            vendor=vendor, doc_scores=doc_scores, tags_by_doc=tags_by_doc, failed_docs=failed
        )
    return stats, outputs, failures


# ── 2) 채점 리포트(scores.md) ───────────────────────────────────────────────
def _ratio(v: float | None) -> str:
    return "-" if v is None else f"{v:.2f}"


def _mark(ok: bool) -> str:
    return "✓" if ok else "✗"


def write_scores_md(
    stats: dict[str, VendorStats],
    outputs: dict[str, dict[str, ExtractedItem | None]],
    path: Path,
) -> None:
    lines = ["# 파싱 채점 결과 (scores.md)", ""]
    lines += [
        "## 벤더별 총합",
        "",
        "| 벤더 | 크리티컬 미스 | 환각(날짜+금액) | 파싱 실패 |",
        "|---|---|---|---|",
    ]
    for vendor, vs in stats.items():
        lines.append(
            f"| {vendor} | {vs.total_critical} | {vs.total_hallucination} "
            f"| {len(vs.failed_docs)} |"
        )
    for vendor, vs in stats.items():
        lines += [
            "",
            f"## {vendor} — 문서×필드 매트릭스",
            "",
            "| doc | tags | doc_type | deadline | requires_reply "
            "| dates 누락/환각 | amounts 누락/환각 | supplies R/P | 크리티컬 |",
            "|---|---|---|---|---|---|---|---|---|",
        ]
        for ds in vs.doc_scores:
            tags = ",".join(vs.tags_by_doc.get(ds.doc_id, [])) or "-"
            lines.append(
                f"| {ds.doc_id} | {tags} | {_mark(ds.doc_type_match)} "
                f"| {_mark(ds.deadline_match)} | {_mark(ds.requires_reply_match)} "
                f"| {len(ds.dates.missing)}/{len(ds.dates.hallucinated)} "
                f"| {len(ds.amounts.missing)}/{len(ds.amounts.hallucinated)} "
                f"| {_ratio(ds.supplies.recall)}/{_ratio(ds.supplies.precision)} "
                f"| {ds.critical_misses} |"
            )
        for ds in vs.doc_scores:
            details = []
            if ds.dates.missing:
                details.append(f"dates 누락: {', '.join(ds.dates.missing)}")
            if ds.dates.hallucinated:
                details.append(f"dates 환각: {', '.join(ds.dates.hallucinated)}")
            if ds.amounts.missing:
                details.append(f"amounts 누락: {', '.join(ds.amounts.missing)}")
            if ds.amounts.hallucinated:
                details.append(f"amounts 환각: {', '.join(ds.amounts.hallucinated)}")
            if ds.supplies.missing:
                details.append(f"supplies 미검출: {', '.join(ds.supplies.missing)}")
            if details:
                lines += ["", f"- doc {ds.doc_id}: " + " / ".join(details)]

    lines += ["", "## 수동 검토 (자동 채점 제외: title·raw_text·checkboxes)", ""]
    for vendor, by_doc in outputs.items():
        for doc_id, item in by_doc.items():
            lines.append(f"### {vendor} / doc {doc_id}")
            if item is None:
                lines += ["(파싱 실패 — results/" + vendor + f"/{doc_id}.error.txt 참조)", ""]
                continue
            checkboxes = ", ".join(c.label for c in item.checkboxes) or "(없음)"
            lines += [
                f"- title: {item.title}",
                f"- checkboxes: {checkboxes}",
                "- raw_text:",
                "",
                "```",
                item.raw_text,
                "```",
                "",
            ]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


# ── 3) 경어체 블라인드 A/B ──────────────────────────────────────────────────
async def run_ab(clients: dict[str, Any], out_dir: Path) -> bool:
    """두 벤더(QUALITY)로 고정 입력 5건을 생성해 블라인드 페어를 덤프한다(§4.3-5)."""
    if not {"gemini", "claude"} <= set(clients):
        print("[경고] A/B 스킵 — gemini·claude 두 벤더가 모두 필요합니다.")
        return False
    agents = {
        vendor: TeacherCommunicationAgent(client, tier=ModelTier.QUALITY)
        for vendor, client in clients.items()
    }
    lines = [
        "# 경어체 블라인드 A/B (ab_pairs.md)",
        "",
        "평가자 안내: 벤더명은 제거됐고 문항별로 A/B가 무작위 배정됐다.",
        "배정표는 ab_key.json에 있으니 평가 완료 전에는 열지 말 것.",
        "vi 문항의 admin_guide_native 원문은 육안 점검 대상(조사 페이지 §11, 2026-07-06 사전등록).",
        "",
    ]
    key: dict[str, dict[str, str]] = {}
    for i, fixture in enumerate(AB_FIXTURES, start=1):
        rendered: dict[str, list[str]] = {}
        for vendor, agent in agents.items():
            resp = await agent.run(fixture)
            if resp.status == "ok" and resp.data is not None:
                rendered[vendor] = [
                    "- output_ko:",
                    "",
                    "```",
                    resp.data.output_ko,
                    "```",
                    "",
                    "- admin_guide_native:",
                    "",
                    "```",
                    resp.data.admin_guide_native,
                    "```",
                ]
                print(f"  [A/B] 문항 {i} × {vendor}: OK ({resp.latency_ms}ms)")
            else:
                rendered[vendor] = [f"(생성 실패: {resp.error})"]
                print(f"  [A/B] 문항 {i} × {vendor}: 실패 — {resp.error}")
        order = random.sample(["gemini", "claude"], 2)  # 문항별 무작위 배정
        key[str(i)] = {"A": order[0], "B": order[1]}
        lines += [
            f"## 문항 {i} — situation={fixture.situation}, lang={fixture.native_language}",
            "",
            f"[입력] {fixture.input_native}",
            "",
            "### A",
            "",
            *rendered[order[0]],
            "",
            "### B",
            "",
            *rendered[order[1]],
            "",
        ]
    (out_dir / "ab_pairs.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    (out_dir / "ab_key.json").write_text(
        json.dumps(key, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"A/B 페어 저장: {out_dir / 'ab_pairs.md'} (배정표: ab_key.json — 평가 전 열람 금지)")
    return True


# ── 4) 실행 리포트(신뢰성·비용 요약) — 판정은 전 시퀀스 후 eval/verdict.py로 ──
def render_run_report(
    clients: dict[str, Any],
    stats: dict[str, VendorStats],
    ab_ran: bool,
    failures: dict[str, dict[str, str]],
) -> str:
    lines = ["# 실행 리포트 (run_report.md)", ""]
    lines += [
        "## 파싱 집계(이 실행분 — 상세 매트릭스는 scores.md)",
        "",
        "| 벤더 | 크리티컬 미스 | 환각(날짜+금액) | 실패:절단(검증) | 실패:5xx(가용성) | 실패:기타 |",
        "|---|---|---|---|---|---|",
    ]
    for vendor, vs in stats.items():
        kinds = list(failures.get(vendor, {}).values())
        lines.append(
            f"| {vendor} | {vs.total_critical} | {vs.total_hallucination} "
            f"| {kinds.count('validation')} | {kinds.count('availability')} "
            f"| {kinds.count('other')} |"
        )
    failed_lines = [
        f"  - {vendor}/doc {doc_id}: {kind}"
        for vendor, by_doc in failures.items()
        for doc_id, kind in sorted(by_doc.items())
    ]
    if failed_lines:
        lines += ["", "- 실패 문서(계열별 — 상세는 {vendor}/{doc_id}.error.txt):"] + failed_lines
    lines += [
        "",
        "- 계측 결함 규칙(사전 선언): 절단(검증 실패) ≤2건 → 채점 인정 / ≥3건 → 계측 결함,",
        "  해당 run **전체** 재실행(실패 문서만 부분 재실행 금지 — 체리피킹).",
        "  5xx(가용성)는 인프라 노이즈로 별도 집계 — 백오프 재시도 후에도 남은 건 재실행 사유.",
    ]
    if not ab_ran:
        lines += ["", "- 경어체 A/B: 이 실행에서는 미실행(--skip-ab 또는 벤더 부족)."]
    lines += ["", "## 신뢰성·비용 요약 (재시도·토큰·지연시간)", ""]
    lines += [
        "| 벤더 | 재시도:가용성(백오프) | 재시도:검증(1회) | 호출 수 | 입력 토큰 | 출력 토큰 | 평균 지연(ms) |",
        "|---|---|---|---|---|---|---|",
    ]
    for vendor, client in clients.items():
        m = client.metrics
        avg = m.total_latency_ms // len(m.calls) if m.calls else 0
        lines.append(
            f"| {vendor} | {m.availability_retries} | {m.validation_retries} | {len(m.calls)} "
            f"| {m.total_input_tokens} | {m.total_output_tokens} | {avg} |"
        )
    scored = {vendor: len(vs.doc_scores) for vendor, vs in stats.items()}
    lines += ["", f"- 채점 문서 수: {scored}", "- 사용 모델(티어별): run_meta.json 참조"]
    lines += [
        "",
        "판정: 전체 실행 시퀀스(run1·run2)와 블라인드 평가(manual_review.json 작성) 완료 후",
        "`python ai/pilots/llm_sku/eval/verdict.py`로 산출 — 조사 페이지 §11 v2, README 참조.",
    ]
    return "\n".join(lines) + "\n"


# ── 엔트리포인트 ────────────────────────────────────────────────────────────
async def _amain(args: argparse.Namespace) -> int:
    clients = make_clients(args.only_vendor)
    if not clients:
        print()
        print("실행할 벤더가 없습니다. API 키를 설정한 뒤 다시 실행하세요:")
        print("  export GOOGLE_API_KEY=...     # Gemini (GEMINI_API_KEY도 인식)")
        print("  export ANTHROPIC_API_KEY=...  # Claude")
        print("env 전체 목록과 실행 방법은 ai/pilots/llm_sku/README.md 참조.")
        return 0

    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    docs = manifest["documents"]
    args.out.mkdir(parents=True, exist_ok=True)

    # 후보 식별 메타데이터(§11 v2의 전제): 이 실행이 실제 사용한 티어별 모델 ID를 기록.
    # 파일럿 한정으로 클라이언트 내부 매핑(_models)을 그대로 읽는다(clients/는 수정 범위 밖).
    run_meta = {
        "models": {
            vendor: {tier.value: model for tier, model in client._models.items()}
            for vendor, client in clients.items()
        }
    }
    (args.out / "run_meta.json").write_text(
        json.dumps(run_meta, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"사용 모델 기록(run_meta.json): {run_meta['models']}")

    print(f"파싱 실행 — 벤더: {', '.join(clients)} / 문서 {len(docs)}건")
    stats, outputs, failures = await run_parsing(clients, docs, args.out)

    scores_path = args.out / "scores.md"
    write_scores_md(stats, outputs, scores_path)
    print(f"채점 매트릭스 저장: {scores_path}")

    ab_ran = False
    if args.skip_ab:
        print("A/B 스킵(--skip-ab).")
    else:
        ab_ran = await run_ab(clients, args.out)

    # 판정(§11 v2)은 다중 run 입력이 필요해 이 실행에서 내리지 않는다 — verdict CLI로 산출
    report = render_run_report(clients, stats, ab_ran, failures)
    (args.out / "run_report.md").write_text(report, encoding="utf-8")
    print()
    print(report)
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="GAON LLM SKU 파일럿 하네스(결정 #4)")
    parser.add_argument("--only-vendor", choices=list(VENDORS), help="한 벤더만 실행(스모크)")
    parser.add_argument("--skip-ab", action="store_true", help="경어체 A/B 생략")
    parser.add_argument("--manifest", type=Path, default=PILOT_DIR / "dataset" / "manifest.json")
    parser.add_argument("--out", type=Path, default=PILOT_DIR / "results")
    args = parser.parse_args()
    return asyncio.run(_amain(args))


if __name__ == "__main__":
    sys.exit(main())
