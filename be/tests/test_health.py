from fastapi.testclient import TestClient

from app.main import app


def test_health_defaults_to_real_modes(monkeypatch) -> None:
    monkeypatch.delenv("GAON_LLM_MODE", raising=False)
    monkeypatch.delenv("GAON_RAG_MODE", raising=False)
    client = TestClient(app)
    res = client.get("/health")
    assert res.status_code == 200
    assert res.json() == {"ok": True, "llm_mode": "gemini", "rag_mode": "kb"}


def test_health_exposes_fake_modes(monkeypatch) -> None:
    """배포 서버가 fake로 떠 고정 더미 데이터를 내는 사고를 밖에서 감지(2026-07-11 보고)."""
    monkeypatch.setenv("GAON_LLM_MODE", "fake")
    monkeypatch.setenv("GAON_RAG_MODE", "fake")
    client = TestClient(app)
    res = client.get("/health")
    assert res.status_code == 200
    body = res.json()
    assert body["llm_mode"] == "fake"
    assert body["rag_mode"] == "fake"
