"""pending 마이그레이션 중 '데이터 파괴 DDL'을 포함한 리비전을 표준출력에 나열한다.

파괴적으로 보는 것(데이터 손실 위험):
  - op.drop_table / op.drop_column
  - op.alter_column   (타입 변경·NOT NULL 강제 등)
  - op.rename_table
  - op.execute("... DROP / TRUNCATE / DELETE ...")   (raw SQL)

제외(데이터 손실 아님, 정상 패턴):
  - op.drop_constraint / op.drop_index
    → CHECK 제약 교체(0008/0009처럼 drop_constraint + create_check_constraint)는 안전하므로 게이트하지 않는다.
    (constraint drop 까지 막고 싶으면 DESTRUCTIVE 패턴에 한 줄 추가하면 됨)

사용: python scan_destructive.py <current_revision>
  - 현재 리비전(=이미 적용된 지점) 위로 head 까지의 pending 리비전만 스캔.
  - 파괴적 리비전이 있으면 그 id 들을 공백구분으로 출력(없으면 아무것도 출력 안 함).
"""

from __future__ import annotations

import re
import sys

from alembic.config import Config
from alembic.script import ScriptDirectory

lower = sys.argv[1] if len(sys.argv) > 1 else ""
if lower in ("", "base", "None"):
    sys.exit(0)  # 빈 DB — 잃을 데이터가 없으므로 게이트 불필요

DESTRUCTIVE = re.compile(
    r"op\.drop_table\b"
    r"|op\.drop_column\b"
    r"|op\.alter_column\b"
    r"|op\.rename_table\b"
    r"|op\.execute\s*\(\s*[\"'][^\"']*\b(?:DROP|TRUNCATE|DELETE)\b",
    re.IGNORECASE,
)

try:
    script = ScriptDirectory.from_config(Config("alembic.ini"))
    pending = list(script.iterate_revisions("heads", lower))
except Exception as exc:  # 스캔 불가 → fail-open 하되 경고(가드는 보안경계 아님)
    print(f"[scan_destructive] 경고: 스캔 실패({exc}) — 가드 건너뜀", file=sys.stderr)
    sys.exit(0)

hits: list[str] = []
for rev in pending:
    if rev.revision == lower:  # 이미 적용된 지점은 제외
        continue
    try:
        src = open(rev.path, encoding="utf-8").read()
    except OSError:
        continue
    if DESTRUCTIVE.search(src):
        hits.append(rev.revision)

if hits:
    print(" ".join(reversed(hits)))  # 적용 순서대로
