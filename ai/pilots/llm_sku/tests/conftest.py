"""tests가 llm_sku 루트의 eval/ 패키지를 import할 수 있도록 sys.path에 추가."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
